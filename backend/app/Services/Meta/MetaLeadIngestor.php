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
        $existing = MetaLeadIngestion::query()->where('leadgen_id', $leadgenId)->first();
        if ($existing && in_array($existing->status, ['processed', 'duplicate', 'test_skipped'], true)) {
            return $existing;
        }

        $ingestion = $existing ?? MetaLeadIngestion::query()->create([
            'leadgen_id' => $leadgenId,
            'meta_webhook_event_id' => $event?->id,
            'status' => 'received',
            'payload' => $value,
        ]);

        // Meta Developer Console "Test" button sends stub IDs like 444444444444.
        // Those are not real leads and Graph will return HTTP 400.
        if ($this->isMetaSampleLeadgen($leadgenId, $value)) {
            $ingestion->update([
                'status' => 'test_skipped',
                'message' => 'Meta sample webhook stub ignored. Use Lead Ads Testing Tool or a real form submit.',
                'payload' => $value,
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

        return [
            'name' => $fields['full_name'] ?? $fields['name'] ?? $fields['first_name'] ?? null,
            'mobile' => $fields['phone_number'] ?? $fields['mobile'] ?? $fields['phone'] ?? null,
            'email' => $fields['email'] ?? null,
            'preferred_location' => $fields['preferred_location'] ?? $fields['city'] ?? null,
        ];
    }
}
