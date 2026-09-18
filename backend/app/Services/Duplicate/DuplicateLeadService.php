<?php

namespace App\Services\Duplicate;

use App\Models\Lead;

class DuplicateLeadService
{
    /**
     * @return array{exact_external: ?Lead, mobile_match: ?Lead}
     */
    public function findMatches(?string $sourceId, ?string $externalLeadId, string $mobile): array
    {
        $exact = null;
        if ($sourceId && $externalLeadId) {
            $exact = Lead::query()
                ->where('lead_source_id', $sourceId)
                ->where('external_lead_id', $externalLeadId)
                ->first();
        }

        $normalized = Lead::normalizeMobile($mobile);
        $mobileMatch = null;
        if ($normalized !== '') {
            $mobileMatch = Lead::query()
                ->where('mobile_normalized', $normalized)
                ->where('is_duplicate', false)
                ->orderBy('id')
                ->first();
        }

        return [
            'exact_external' => $exact,
            'mobile_match' => $mobileMatch,
        ];
    }
}
