<?php

namespace App\Services\Meta;

use App\Models\LeadSource;
use App\Models\MetaConnection;
use App\Models\MetaLeadIngestion;
use App\Models\MetaWebhookEvent;
use App\Services\Lead\LeadIntakeService;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class MetaLeadIngestor
{
    public function __construct(
        private readonly LeadIntakeService $intake,
    ) {}

    public function verifyToken(string $token): bool
    {
        $connection = MetaConnection::query()->latest('id')->first();
        if (! $connection || ! $connection->webhook_verify_token_hash) {
            $fallback = config('services.meta.webhook_verify_token');
            return $fallback !== null && hash_equals((string) $fallback, $token);
        }

        return Hash::check($token, $connection->webhook_verify_token_hash);
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    public function handleWebhookPayload(array $payload): MetaWebhookEvent
    {
        $event = MetaWebhookEvent::query()->create([
            'event_id' => $payload['entry'][0]['id'] ?? null,
            'payload' => $payload,
            'status' => 'received',
        ]);

        try {
            $entries = $payload['entry'] ?? [];
            foreach ($entries as $entry) {
                foreach ($entry['changes'] ?? [] as $change) {
                    if (($change['field'] ?? null) !== 'leadgen') {
                        continue;
                    }
                    $value = $change['value'] ?? [];
                    $leadgenId = (string) ($value['leadgen_id'] ?? '');
                    if ($leadgenId === '') {
                        continue;
                    }
                    $this->processLeadgen($leadgenId, $value, $event);
                }
            }
            $event->update(['status' => 'processed']);
        } catch (\Throwable $e) {
            Log::error('Meta webhook processing failed', ['error' => $e->getMessage()]);
            $event->update([
                'status' => 'failed',
                'error_message' => $e->getMessage(),
            ]);
        }

        return $event;
    }

    /**
     * @param  array<string, mixed>  $value
     */
    public function processLeadgen(string $leadgenId, array $value, ?MetaWebhookEvent $event = null): MetaLeadIngestion
    {
        $isSample = $this->isMetaSampleLeadgen($leadgenId, $value);

        // Real leads: idempotent by Meta leadgen_id.
        // Sample stubs always reuse 4444..., so key them per webhook event for demo visibility.
        $ingestionKey = $isSample
            ? 'sample-'.($event?->id ?? 'x').'-'.$leadgenId.'-'.Str::lower(Str::random(6))
            : $leadgenId;

        if (! $isSample) {
            $existing = MetaLeadIngestion::query()->where('leadgen_id', $leadgenId)->first();
            if ($existing && in_array($existing->status, ['processed', 'duplicate', 'test_skipped'], true)) {
                return $existing;
            }
        }

        $ingestion = MetaLeadIngestion::query()->create([
            'leadgen_id' => $ingestionKey,
            'meta_webhook_event_id' => $event?->id,
            'status' => 'received',
            'payload' => $value,
        ]);

        // Meta Developer Console "Test" button sends stub IDs like 444444444444.
        // Create a visible demo lead so each Test click appears in the CRM.
        if ($isSample) {
            $source = LeadSource::query()->where('code', 'META')->firstOrFail();
            $seq = MetaLeadIngestion::query()->where('status', 'processed_sample')->count() + 1;
            $result = $this->intake->intake([
                'name' => 'Meta Test Lead #'.$seq,
                'mobile' => '9000000'.str_pad((string) min($seq, 999), 3, '0', STR_PAD_LEFT),
                'email' => null,
                'lead_source_id' => $source->id,
                'external_lead_id' => $ingestionKey,
                'preferred_location' => 'Meta webhook test',
            ], [
                'page_id' => $value['page_id'] ?? null,
                'form_id' => $value['form_id'] ?? null,
                'ad_id' => $value['ad_id'] ?? null,
                'adset_id' => $value['adgroup_id'] ?? ($value['adset_id'] ?? null),
                'campaign_id' => $value['campaign_id'] ?? null,
                'leadgen_id' => $leadgenId,
                'raw_field_data' => [
                    'note' => 'Created from Meta Webhooks Test stub (not a real form submit).',
                ],
            ]);

            $ingestion->update([
                'lead_id' => $result['lead']->id,
                'status' => 'processed_sample',
                'message' => 'Meta sample webhook: demo lead created (Graph has no real field data for 4444... IDs).',
                'payload' => array_merge($value, ['sample' => true]),
            ]);

            return $ingestion->fresh();
        }

        $details = $this->fetchLeadDetails($leadgenId);
        $mapped = $this->mapLeadFields($details, $value);

        if (empty($mapped['name']) && empty($mapped['mobile']) && empty($mapped['email'])) {
            $ingestion->update([
                'status' => 'failed',
                'message' => 'Graph API returned no lead fields. Check Page access token permissions (leads_retrieval).',
                'payload' => array_merge($value, ['graph' => $details]),
            ]);

            return $ingestion->fresh();
        }

        $source = LeadSource::query()->where('code', 'META')->firstOrFail();
        $result = $this->intake->intake([
            'name' => $mapped['name'] ?: 'Meta Lead',
            'mobile' => $mapped['mobile'] ?: '0000000000',
            'email' => $mapped['email'],
            'lead_source_id' => $source->id,
            'external_lead_id' => $leadgenId,
            'preferred_location' => $mapped['preferred_location'],
        ], [
            'page_id' => $value['page_id'] ?? null,
            'form_id' => $value['form_id'] ?? null,
            'ad_id' => $value['ad_id'] ?? null,
            'adset_id' => $value['adgroup_id'] ?? ($value['adset_id'] ?? null),
            'campaign_id' => $value['campaign_id'] ?? null,
            'leadgen_id' => $leadgenId,
            'raw_field_data' => $details['field_data'] ?? null,
        ]);

        $ingestion->update([
            'lead_id' => $result['lead']->id,
            'status' => $result['duplicate'] && ! $result['created'] ? 'duplicate' : 'processed',
            'message' => $result['duplicate'] ? 'Duplicate detected' : 'Lead created',
            'payload' => array_merge($value, ['mapped' => $mapped]),
        ]);

        return $ingestion->fresh();
    }

    /**
     * @param  array<string, mixed>  $value
     */
    private function isMetaSampleLeadgen(string $leadgenId, array $value): bool
    {
        if (preg_match('/^4+$/', $leadgenId) === 1) {
            return true;
        }

        foreach (['page_id', 'form_id', 'ad_id', 'adgroup_id'] as $key) {
            $v = (string) ($value[$key] ?? '');
            if ($v !== '' && preg_match('/^4+$/', $v) === 1) {
                return true;
            }
        }

        return false;
    }

    /**
     * @return array<string, mixed>
     */
    private function fetchLeadDetails(string $leadgenId): array
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            return [];
        }

        $version = config('services.meta.api_version', 'v21.0');
        $response = Http::timeout(15)->get("https://graph.facebook.com/{$version}/{$leadgenId}", [
            'access_token' => $token,
        ]);

        if (! $response->successful()) {
            Log::warning('Meta Graph lead fetch failed', [
                'leadgen_id' => $leadgenId,
                'status' => $response->status(),
                'body' => Str::limit($response->body(), 500),
            ]);

            return [];
        }

        return $response->json() ?? [];
    }

    /**
     * @param  array<string, mixed>  $details
     * @param  array<string, mixed>  $value
     * @return array{name: ?string, mobile: ?string, email: ?string, preferred_location: ?string}
     */
    private function mapLeadFields(array $details, array $value): array
    {
        $fields = [];
        foreach ($details['field_data'] ?? [] as $field) {
            $name = strtolower((string) ($field['name'] ?? ''));
            $values = $field['values'] ?? [];
            $fields[$name] = $values[0] ?? null;
        }

        $mobile = $fields['phone_number']
            ?? $fields['mobile']
            ?? $fields['phone']
            ?? $fields['work_phone_number']
            ?? null;
        if (is_string($mobile)) {
            // Lead Center exports often look like "p:+9198..."
            $mobile = preg_replace('/^p:/i', '', $mobile) ?? $mobile;
        }

        return [
            'name' => $fields['full_name'] ?? $fields['name'] ?? $fields['first_name'] ?? null,
            'mobile' => $mobile,
            'email' => $fields['email'] ?? null,
            'preferred_location' => $fields['preferred_location'] ?? $fields['city'] ?? null,
        ];
    }
}
