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
        {--limit=50 : Max leads to pull when using --form}
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

        $ids = collect($this->argument('leadgen_ids'))
            ->map(fn ($id) => preg_replace('/^l:/i', '', trim((string) $id)))
            ->filter()
            ->values();

        $formId = $this->option('form')
            ?: MetaLeadForm::query()->latest('id')->value('form_id');

        if ($ids->isEmpty()) {
            if (! $formId) {
                $this->error('Pass lead IDs and/or --form=FORM_ID');

                return self::FAILURE;
            }
            $ids = collect($this->fetchFormLeadIds((string) $formId, $token, (int) $this->option('limit')));
            $this->info('Pulled '.$ids->count().' lead id(s) from form '.$formId);
        }

        if ($ids->isEmpty()) {
            $this->warn('No lead IDs to import.');

            return self::SUCCESS;
        }

        $pageId = $this->option('page') ?: $connection?->page_id;
        $ok = 0;
        $fail = 0;

        foreach ($ids as $leadgenId) {
            $value = array_filter([
                'leadgen_id' => $leadgenId,
                'page_id' => $pageId,
                'form_id' => $formId,
            ]);

            $ingestion = $ingestor->processLeadgen($leadgenId, $value);
            $line = "leadgen={$leadgenId} status={$ingestion->status} lead_id=".($ingestion->lead_id ?? 'null');
            if ($ingestion->message) {
                $line .= " msg={$ingestion->message}";
            }
            $this->line($line);

            if (in_array($ingestion->status, ['processed', 'duplicate'], true)) {
                $ok++;
            } else {
                $fail++;
            }
        }

        $this->newLine();
        $this->info("Done. ok={$ok} failed_or_sample={$fail}");
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
        $response = Http::timeout(30)->get("https://graph.facebook.com/{$version}/{$formId}/leads", [
            'access_token' => $token,
            'limit' => max(1, min($limit, 100)),
            'fields' => 'id,created_time',
        ]);

        if (! $response->successful()) {
            $this->error('Form leads pull failed HTTP '.$response->status().': '.$response->body());

            return [];
        }

        $data = $response->json('data') ?? [];

        return collect($data)
            ->map(fn ($row) => (string) ($row['id'] ?? ''))
            ->filter()
            ->values()
            ->all();
    }
}
