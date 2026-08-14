<?php

namespace App\Console\Commands;

use App\Models\MetaWebhookEvent;
use App\Services\Meta\MetaLeadIngestor;
use Illuminate\Console\Command;

class ReprocessMetaWebhooks extends Command
{
    protected $signature = 'meta:reprocess-webhooks {--id= : Specific meta_webhook_events id}';

    protected $description = 'Reprocess stored Meta webhook events into leads';

    public function handle(MetaLeadIngestor $ingestor): int
    {
        $query = MetaWebhookEvent::query()->orderBy('id');
        if ($this->option('id')) {
            $query->where('id', (int) $this->option('id'));
        }

        $events = $query->get();
        if ($events->isEmpty()) {
            $this->warn('No webhook events found.');

            return self::SUCCESS;
        }

        foreach ($events as $event) {
            $payload = $event->payload ?? [];
            $this->info("Reprocessing webhook event #{$event->id}");

            foreach ($payload['entry'] ?? [] as $entry) {
                foreach ($entry['changes'] ?? [] as $change) {
                    if (($change['field'] ?? null) !== 'leadgen') {
                        continue;
                    }
                    $value = $change['value'] ?? [];
                    $leadgenId = (string) ($value['leadgen_id'] ?? '');
                    if ($leadgenId === '') {
                        continue;
                    }
                    $ingestion = $ingestor->processLeadgen($leadgenId, $value, $event);
                    $this->line("  leadgen={$leadgenId} status={$ingestion->status} lead_id=".($ingestion->lead_id ?? 'null'));
                }
            }
        }

        return self::SUCCESS;
    }
}
