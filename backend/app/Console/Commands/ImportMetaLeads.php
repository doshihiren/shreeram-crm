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
        {--limit=100 : Max leads to pull when using --form}
        {--page= : Optional page_id for attribution}';

    protected $description = 'Import real Meta leads by leadgen ID or by pulling a form feed (backfill)';

    public function handle(MetaLeadIngestor $ingestor): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            $this->error('No Page access token. Save it in CRM Meta settings (or META_PAGE_ACCESS_TOKEN).');

            return self::FAILURE;
        }

        // If a USER token was saved, try to exchange it for a PAGE token first.
        $token = $this->ensurePageToken($connection, $token);

        $ids = collect($this->argument('leadgen_ids'))
            ->map(fn ($id) => preg_replace('/^l:/i', '', trim((string) $id)))
            ->filter()
            ->values();

        $formId = $this->option('form')
            ?: MetaLeadForm::query()->latest('id')->value('form_id')
            ?: '1301528194957429';

        if ($ids->isEmpty()) {
            if (! $formId) {
                $this->error('Pass lead IDs and/or --form=FORM_ID');

                return self::FAILURE;
            }
            $limit = max(1, (int) $this->option('limit'));
            $this->info("Pulling last {$limit} lead(s) from form {$formId}…");
            $ids = collect($this->fetchFormLeadIds((string) $formId, $token, $limit));
            if ($ids->isEmpty() && $connection?->page_id) {
                $this->warn('Direct form pull failed/empty.');
                $this->warn('If diagnose says USER token, run: php artisan meta:exchange-page-token');
                $this->listPageForms((string) $connection->page_id, $token);
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
            $this->warn('If status=failed: renew Page access token with leads_retrieval and re-run.');
        }

        return $fail > 0 ? self::FAILURE : self::SUCCESS;
    }

    /**
     * @return list<string>
     */
    private function fetchFormLeadIds(string $formId, string $token, int $limit): array
    {
        $version = config('services.meta.api_version', 'v21.0');
        $url = "https://graph.facebook.com/{$version}/{$formId}/leads";
        $ids = [];
        $params = [
            'access_token' => $token,
            'limit' => min(100, $limit),
            'fields' => 'id,created_time',
        ];

        while (count($ids) < $limit) {
            $response = Http::timeout(30)->get($url, $params);
            if (! $response->successful()) {
                $this->error('Form leads pull failed HTTP '.$response->status().': '.$response->body());
                break;
            }

            $json = $response->json() ?? [];
            foreach ($json['data'] ?? [] as $row) {
                $id = (string) ($row['id'] ?? '');
                if ($id !== '') {
                    $ids[] = $id;
                }
                if (count($ids) >= $limit) {
                    break 2;
                }
            }

            $next = $json['paging']['next'] ?? null;
            if (! is_string($next) || $next === '') {
                break;
            }
            // Absolute next URL already includes token/cursor
            $url = $next;
            $params = [];
        }

        return $ids;
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
            $this->warn('Run: php artisan meta:exchange-page-token');

            return $token;
        }

        $match = collect($accounts->json('data') ?? [])
            ->first(fn ($p) => (string) ($p['id'] ?? '') === $pageId);
        $pageToken = (string) ($match['access_token'] ?? '');
        if ($pageToken === '') {
            $this->error("Page {$pageId} not found in /me/accounts.");

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
