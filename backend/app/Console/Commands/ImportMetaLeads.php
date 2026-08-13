<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use App\Services\Meta\MetaLeadIngestor;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class ImportMetaLeads extends Command
{
    protected $signature = 'meta:import-leads
        {leadgen_ids?* : One or more Meta lead IDs (without l: prefix)}
        {--form= : Pull recent leads from this Meta form ID}
        {--limit=500 : Max leads to pull when using --form}
        {--since= : Only leads on/after date (YYYY-MM-DD), e.g. 2026-07-01}
        {--until= : Only leads on/before date (YYYY-MM-DD)}
        {--page= : Optional page_id for attribution}
        {--csv= : Path to Meta Lead Center export (csv/tsv) — imports by lead id}';

    protected $description = 'Import real Meta leads by leadgen ID, CSV export, or form feed (supports --since for backfill)';

    public function handle(MetaLeadIngestor $ingestor): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            $this->error('No access token. Save it in CRM Meta settings (or META_PAGE_ACCESS_TOKEN).');

            return self::FAILURE;
        }

        // If a USER token was saved, try to exchange it for a PAGE token first.
        $token = $this->ensurePageToken($connection, $token);

        $ids = collect($this->argument('leadgen_ids'))
            ->map(fn ($id) => preg_replace('/^l:/i', '', trim((string) $id)))
            ->filter()
            ->values();

        $csv = $this->option('csv');
        if ($ids->isEmpty() && is_string($csv) && $csv !== '') {
            $ids = collect($this->extractLeadIdsFromCsv($csv));
            $this->info('CSV lead ids found: '.$ids->count());
        }

        $formId = $this->option('form')
            ?: MetaLeadForm::query()->latest('id')->value('form_id')
            ?: '1301528194957429';

        if ($ids->isEmpty()) {
            if (! $formId) {
                $this->error('Pass lead IDs, --csv=file, and/or --form=FORM_ID');

                return self::FAILURE;
            }
            $limit = max(1, (int) $this->option('limit'));
            $since = $this->option('since') ? (string) $this->option('since') : null;
            $until = $this->option('until') ? (string) $this->option('until') : null;
            $this->info("Pulling up to {$limit} lead(s) from form {$formId}"
                .($since ? " since={$since}" : '')
                .($until ? " until={$until}" : '')
                .'…');
            $ids = collect($this->fetchFormLeadIds((string) $formId, $token, $limit, $since, $until));
            if ($ids->isEmpty()) {
                $this->warn('Form pull failed/empty.');
                $this->warn('Run: php artisan meta:check-logs');
                $this->warn('Workaround: export Lead Center CSV → php artisan meta:import-leads --csv=/path/file.csv');
                if ($connection?->page_id) {
                    $this->listPageForms((string) $connection->page_id, $token);
                }
            }
            $this->info('Got '.$ids->count().' lead id(s)');
        }

        if ($ids->isEmpty()) {
            $this->warn('No lead IDs to import.');

            return self::SUCCESS;
        }

        $pageId = $this->option('page') ?: $connection?->page_id;
        $ok = 0;
        $fail = 0;
        $bar = $this->output->createProgressBar($ids->count());
        $bar->start();

        foreach ($ids as $leadgenId) {
            $value = array_filter([
                'leadgen_id' => $leadgenId,
                'page_id' => $pageId,
                'form_id' => $formId,
            ]);

            $ingestion = $ingestor->processLeadgen($leadgenId, $value);
            $bar->advance();
            $this->newLine();
            $line = "  leadgen={$leadgenId} status={$ingestion->status} lead_id=".($ingestion->lead_id ?? 'null');
            if ($ingestion->message) {
                $line .= " msg={$ingestion->message}";
            }
            $this->line($line);

            if (in_array($ingestion->status, ['processed', 'duplicate', 'processed_sample'], true)) {
                $ok++;
            } else {
                $fail++;
            }
        }

        $bar->finish();
        $this->newLine(2);
        $this->info("Done. imported_or_duplicate={$ok} failed={$fail}");
        if ($fail > 0) {
            $this->warn('Failed rows usually mean token/permission issues for that lead id.');
        }

        return $fail > 0 ? self::FAILURE : self::SUCCESS;
    }

    /**
     * @return list<string>
     */
    private function extractLeadIdsFromCsv(string $path): array
    {
        if (! is_file($path)) {
            $this->error('CSV not found: '.$path);

            return [];
        }

        $raw = file_get_contents($path);
        if ($raw === false || $raw === '') {
            return [];
        }

        preg_match_all('/(?:^|[,\t\s"])l?:?(\d{10,})/m', $raw, $m);
        $ids = collect($m[1] ?? [])
            ->map(fn ($id) => (string) $id)
            ->unique()
            ->values()
            ->all();

        // Prefer IDs that look like leadgen (exclude obvious page/form/campaign if mixed)
        return $ids;
    }

    /**
     * @return list<string>
     */
    private function fetchFormLeadIds(
        string $formId,
        string $token,
        int $limit,
        ?string $since = null,
        ?string $until = null,
    ): array {
        $version = config('services.meta.api_version', 'v21.0');
        $url = "https://graph.facebook.com/{$version}/{$formId}/leads";
        $ids = [];
        $params = [
            'access_token' => $token,
            'limit' => min(100, $limit),
            'fields' => 'id,created_time',
        ];

        // Meta filtering for time_created (unix seconds)
        $filters = [];
        if ($since) {
            $filters[] = [
                'field' => 'time_created',
                'operator' => 'GREATER_THAN',
                'value' => max(0, strtotime($since.' 00:00:00 UTC') - 1),
            ];
        }
        if ($until) {
            $filters[] = [
                'field' => 'time_created',
                'operator' => 'LESS_THAN',
                'value' => strtotime($until.' 23:59:59 UTC') ?: time(),
            ];
        }
        if ($filters !== []) {
            $params['filtering'] = json_encode($filters);
        }

        $sinceTs = $since ? strtotime($since.' 00:00:00 UTC') : null;
        $untilTs = $until ? strtotime($until.' 23:59:59 UTC') : null;

        while (count($ids) < $limit) {
            $response = Http::timeout(45)->get($url, $params);
            if (! $response->successful()) {
                $this->error('Form leads pull failed HTTP '.$response->status().': '.$response->body());
                break;
            }

            $json = $response->json() ?? [];
            $pageHadRows = false;
            foreach ($json['data'] ?? [] as $row) {
                $pageHadRows = true;
                $id = (string) ($row['id'] ?? '');
                $created = isset($row['created_time']) ? strtotime((string) $row['created_time']) : null;

                // Client-side date guard (in case filtering unsupported)
                if ($sinceTs && $created && $created < $sinceTs) {
                    continue;
                }
                if ($untilTs && $created && $created > $untilTs) {
                    continue;
                }

                if ($id !== '') {
                    $ids[] = $id;
                }
                if (count($ids) >= $limit) {
                    break 2;
                }
            }

            $next = $json['paging']['next'] ?? null;
            if (! is_string($next) || $next === '' || ! $pageHadRows) {
                break;
            }
            $url = $next;
            $params = [];
        }

        return array_values(array_unique($ids));
    }

    private function ensurePageToken(?MetaConnection $connection, string $token): string
    {
        if (! $connection?->page_id) {
            return $token;
        }

        $version = config('services.meta.api_version', 'v21.0');
        $pageId = (string) $connection->page_id;
        $me = Http::timeout(15)->get("https://graph.facebook.com/{$version}/me", [
            'access_token' => $token,
            'fields' => 'id,name',
        ]);
        if ($me->successful() && (string) $me->json('id') === $pageId) {
            return $token;
        }

        $this->warn('Saved token is not a Page token ('.($me->json('name') ?? 'unknown').'). Trying /me/accounts exchange…');
        $accounts = Http::timeout(30)->get("https://graph.facebook.com/{$version}/me/accounts", [
            'access_token' => $token,
            'fields' => 'id,name,access_token',
            'limit' => 100,
        ]);
        if (! $accounts->successful()) {
            $this->error('Exchange failed HTTP '.$accounts->status().': '.$accounts->body());

            return $token;
        }

        $pages = collect($accounts->json('data') ?? []);
        $match = $pages->first(fn ($p) => (string) ($p['id'] ?? '') === $pageId);
        if (! $match) {
            $this->error("Page {$pageId} not found in /me/accounts.");
            $this->warn('Hiren Doshi can manage these Pages instead:');
            foreach ($pages->take(15) as $p) {
                $this->line('  - '.($p['id'] ?? '').' '.($p['name'] ?? ''));
            }
            $this->warn('Ask Business Admin to assign "Shreeram Developer" to your user (Advertise or Full control).');

            return $token;
        }

        $pageToken = (string) ($match['access_token'] ?? '');
        if ($pageToken === '') {
            return $token;
        }

        $connection->page_access_token = $pageToken;
        if (! empty($match['name'])) {
            $connection->page_name = $match['name'];
        }
        $connection->save();
        $this->info('Exchanged and saved Page token for '.$pageId);

        return $pageToken;
    }

    private function listPageForms(string $pageId, string $token): void
    {
        $version = config('services.meta.api_version', 'v21.0');
        $response = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$pageId}/leadgen_forms", [
            'access_token' => $token,
            'fields' => 'id,name,status,leads_count',
            'limit' => 50,
        ]);
        if (! $response->successful()) {
            $this->error('Page forms list failed HTTP '.$response->status().': '.$response->body());

            return;
        }
        foreach ($response->json('data') ?? [] as $f) {
            $this->line(sprintf(
                '  form=%s name=%s status=%s leads=%s',
                $f['id'] ?? '',
                $f['name'] ?? '',
                $f['status'] ?? '',
                $f['leads_count'] ?? '?'
            ));
        }
    }
}
