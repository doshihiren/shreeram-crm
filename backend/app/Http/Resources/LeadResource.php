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
        $meta = $this->relationLoaded('metaAttribution') ? $this->metaAttribution : null;

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
                'color' => $this->stage->color,
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
            // Always useful for sales: Meta form Q&A + platform
            'platform' => $meta?->platform,
            'form_answers' => $meta ? $this->formatFormAnswers($meta->raw_field_data) : [],
            'meta_attribution' => $this->when(
                $canViewMeta && $meta,
                fn () => [
                    'page_id' => $meta->page_id,
                    'page_name' => $meta->page_name,
                    'form_id' => $meta->form_id,
                    'form_name' => $meta->form_name,
                    'campaign_id' => $meta->campaign_id,
                    'campaign_name' => $meta->campaign_name,
                    'adset_id' => $meta->adset_id,
                    'adset_name' => $meta->adset_name,
                    'ad_id' => $meta->ad_id,
                    'ad_name' => $meta->ad_name,
                    'leadgen_id' => $meta->leadgen_id,
                    'platform' => $meta->platform,
                    'is_organic' => $meta->is_organic,
                    'raw_field_data' => $meta->raw_field_data,
                ]
            ),
        ];
    }

    /**
     * @param  mixed  $raw
     * @return list<array{question: string, answer: string}>
     */
    private function formatFormAnswers(mixed $raw): array
    {
        if (! is_array($raw)) {
            return [];
        }

        $out = [];
        foreach ($raw as $field) {
            if (! is_array($field)) {
                continue;
            }
            $name = trim((string) ($field['name'] ?? ''));
            if ($name === '' || $name === 'inbox_url') {
                continue;
            }
            $values = $field['values'] ?? [];
            $answer = is_array($values) ? implode(', ', array_map('strval', $values)) : (string) $values;
            $out[] = [
                'question' => $this->humanizeQuestion($name),
                'answer' => $answer,
            ];
        }

        return $out;
    }

    private function humanizeQuestion(string $name): string
    {
        $name = str_replace(['_', '?'], [' ', ''], $name);
        $name = preg_replace('/\s+/', ' ', $name) ?? $name;

        return ucwords(trim($name));
    }
}
