<?php

namespace App\Services\Lead;

use App\Models\Lead;
use App\Models\LeadActivity;
use App\Models\LeadAssignment;
use App\Models\LeadMetaAttribution;
use App\Models\LeadSource;
use App\Models\LeadStage;
use App\Models\User;
use App\Services\Duplicate\DuplicateLeadService;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

class LeadIntakeService
{
    public function __construct(
        private readonly DuplicateLeadService $duplicates,
    ) {}

    /**
     * @param  array<string, mixed>  $data
     * @param  array<string, mixed>  $metaAttribution
     * @return array{lead: Lead, created: bool, duplicate: bool}
     */
    public function intake(array $data, array $metaAttribution = [], ?User $actor = null): array
    {
        $source = isset($data['lead_source_id'])
            ? LeadSource::query()->findOrFail($data['lead_source_id'])
            : LeadSource::query()->where('code', $data['lead_source_code'] ?? 'OTHER')->firstOrFail();

        $stage = isset($data['lead_stage_id'])
            ? LeadStage::query()->findOrFail($data['lead_stage_id'])
            : LeadStage::query()->where('code', 'NEW_LEAD')->firstOrFail();

        $mobile = (string) $data['mobile'];
        $matches = $this->duplicates->findMatches(
            (string) $source->id,
            $data['external_lead_id'] ?? null,
            $mobile,
        );

        if ($matches['exact_external']) {
            return [
                'lead' => $matches['exact_external'],
                'created' => false,
                'duplicate' => true,
            ];
        }

        return DB::transaction(function () use ($data, $metaAttribution, $actor, $source, $stage, $mobile, $matches) {
            $isDuplicate = $matches['mobile_match'] !== null;
            $primary = $matches['mobile_match'];

            $lead = Lead::query()->create([
                'name' => $data['name'],
                'mobile' => $mobile,
                'mobile_normalized' => Lead::normalizeMobile($mobile),
                'email' => $data['email'] ?? null,
                'lead_source_id' => $source->id,
                'external_lead_id' => $data['external_lead_id'] ?? null,
                'lead_stage_id' => $stage->id,
                'property_type_id' => $data['property_type_id'] ?? null,
                'property_configuration_id' => $data['property_configuration_id'] ?? null,
                'preferred_location' => $data['preferred_location'] ?? null,
                'purpose_id' => $data['purpose_id'] ?? null,
                'assigned_to' => $data['assigned_to'] ?? null,
                'created_by' => $actor?->id,
                'is_duplicate' => $isDuplicate,
                'duplicate_of_lead_id' => $primary?->id,
                'duplicate_confidence' => $isDuplicate ? 'mobile' : null,
                'interested_in_site_visit' => (bool) ($data['interested_in_site_visit'] ?? false),
                'preferred_visit_date' => $data['preferred_visit_date'] ?? null,
                'preferred_visit_time' => $data['preferred_visit_time'] ?? null,
            ]);

            if ($metaAttribution !== []) {
                LeadMetaAttribution::query()->create(array_merge(
                    ['lead_id' => $lead->id],
                    $metaAttribution,
                ));
            }

            LeadActivity::query()->create([
                'lead_id' => $lead->id,
                'user_id' => $actor?->id,
                'type' => 'system',
                'body' => $isDuplicate
                    ? 'Lead created and linked as duplicate of existing lead.'
                    : 'Lead created.',
                'meta' => [
                    'source' => $source->code,
                    'duplicate_of' => $primary?->id,
                ],
            ]);

            if (! empty($data['assigned_to'])) {
                LeadAssignment::query()->create([
                    'lead_id' => $lead->id,
                    'assigned_to' => $data['assigned_to'],
                    'assigned_by' => $actor?->id,
                    'reason' => 'initial_assignment',
                ]);
            }

            return [
                'lead' => $lead->fresh(['stage', 'source', 'assignee', 'metaAttribution']),
                'created' => true,
                'duplicate' => $isDuplicate,
            ];
        });
    }

    public function changeStage(Lead $lead, LeadStage $stage, ?User $actor = null, ?string $lostReason = null): Lead
    {
        if (! $stage->is_active) {
            throw new InvalidArgumentException('Stage is not active.');
        }

        $from = $lead->lead_stage_id;
        $lead->lead_stage_id = $stage->id;
        if ($stage->is_lost) {
            $lead->lost_reason = $lostReason;
            $lead->closed_at = now();
        } elseif ($stage->is_terminal) {
            $lead->closed_at = now();
            $lead->lost_reason = null;
        } else {
            $lead->lost_reason = null;
        }
        if (in_array($stage->code, ['CONTACTED', 'CALL_DONE', 'CALL_NOTE_RECEIVED', 'CALL_NOT_RECEIVED'], true) && $lead->contacted_at === null) {
            $lead->contacted_at = now();
        }
        $lead->save();

        LeadActivity::query()->create([
            'lead_id' => $lead->id,
            'user_id' => $actor?->id,
            'type' => 'stage_change',
            'body' => 'Stage updated.',
            'meta' => [
                'from_stage_id' => $from,
                'to_stage_id' => $stage->id,
                'to_stage_code' => $stage->code,
            ],
        ]);

        return $lead->fresh(['stage']);
    }
}
