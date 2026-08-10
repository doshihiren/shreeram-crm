<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Lead */
class LeadResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $user = $request->user();
        $canViewMeta = $user?->hasPermission('meta.view_attribution') ?? false;

        return [
            'id' => $this->id,
            'public_id' => $this->public_id,
            'name' => $this->name,
            'mobile' => $this->mobile,
            'email' => $this->email,
            'source' => $this->whenLoaded('source', fn () => [
                'id' => $this->source->id,
                'code' => $this->source->code,
                'name' => $this->source->name,
            ]),
            'stage' => $this->whenLoaded('stage', fn () => [
                'id' => $this->stage->id,
                'code' => $this->stage->code,
                'name' => $this->stage->name,
                'is_lost' => $this->stage->is_lost,
            ]),
            'property_type' => $this->whenLoaded('propertyType', fn () => $this->propertyType ? [
                'id' => $this->propertyType->id,
                'code' => $this->propertyType->code,
                'name' => $this->propertyType->name,
            ] : null),
            'property_configuration' => $this->whenLoaded('propertyConfiguration', fn () => $this->propertyConfiguration ? [
                'id' => $this->propertyConfiguration->id,
                'code' => $this->propertyConfiguration->code,
                'name' => $this->propertyConfiguration->name,
            ] : null),
            'purpose' => $this->whenLoaded('purpose', fn () => $this->purpose ? [
                'id' => $this->purpose->id,
                'code' => $this->purpose->code,
                'name' => $this->purpose->name,
            ] : null),
            'preferred_location' => $this->preferred_location,
            'assigned_to' => $this->whenLoaded('assignee', fn () => $this->assignee ? [
                'id' => $this->assignee->id,
                'name' => $this->assignee->name,
            ] : null),
            'is_duplicate' => $this->is_duplicate,
            'duplicate_of_lead_id' => $this->duplicate_of_lead_id,
            'interested_in_site_visit' => $this->interested_in_site_visit,
            'preferred_visit_date' => $this->preferred_visit_date?->toDateString(),
            'preferred_visit_time' => $this->preferred_visit_time,
            'next_follow_up_at' => $this->next_follow_up_at?->toIso8601String(),
            'lost_reason' => $this->lost_reason,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
            'meta_attribution' => $this->when(
                $canViewMeta && $this->relationLoaded('metaAttribution') && $this->metaAttribution,
                fn () => [
                    'page_id' => $this->metaAttribution->page_id,
                    'page_name' => $this->metaAttribution->page_name,
                    'form_id' => $this->metaAttribution->form_id,
                    'form_name' => $this->metaAttribution->form_name,
                    'campaign_id' => $this->metaAttribution->campaign_id,
                    'campaign_name' => $this->metaAttribution->campaign_name,
                    'adset_id' => $this->metaAttribution->adset_id,
                    'adset_name' => $this->metaAttribution->adset_name,
                    'ad_id' => $this->metaAttribution->ad_id,
                    'ad_name' => $this->metaAttribution->ad_name,
                    'leadgen_id' => $this->metaAttribution->leadgen_id,
                ]
            ),
        ];
    }
}
