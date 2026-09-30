<?php

namespace App\Services\Dashboard;

use App\Models\FollowUp;
use App\Models\FollowUpStatus;
use App\Models\Lead;
use App\Models\LeadStage;
use App\Models\SiteVisit;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class DashboardSummaryService
{
    /**
     * @return array<string, mixed>
     */
    public function summarize(User $user): array
    {
        $leadQuery = Lead::query()->where('is_duplicate', false);
        if (! $user->canViewAllLeads()) {
            $leadQuery->where('assigned_to', $user->id);
        }

        $stageCounts = (clone $leadQuery)
            ->select('lead_stage_id', DB::raw('count(*) as aggregate'))
            ->groupBy('lead_stage_id')
            ->pluck('aggregate', 'lead_stage_id');

        $stages = LeadStage::query()
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->get()
            ->map(fn (LeadStage $stage) => [
                'id' => $stage->id,
                'code' => $stage->code,
                'name' => $stage->name,
                'is_lost' => $stage->is_lost,
                'count' => (int) ($stageCounts[$stage->id] ?? 0),
            ])
            ->values();

        $todayStart = Carbon::today();
        $todayEnd = Carbon::today()->endOfDay();

        $pendingFollowUpStatusIds = FollowUpStatus::query()
            ->whereIn('code', ['PENDING'])
            ->pluck('id');

        $followUpQuery = FollowUp::query();
        $siteVisitQuery = SiteVisit::query();
        if (! $user->canViewAllLeads()) {
            $followUpQuery->where('assigned_to', $user->id);
            $siteVisitQuery->where('assigned_to', $user->id);
        }

        return [
            'total_leads' => (clone $leadQuery)->count(),
            'stages' => $stages,
            'today_new_leads' => (clone $leadQuery)->whereBetween('created_at', [$todayStart, $todayEnd])->count(),
            'today_follow_ups' => (clone $followUpQuery)
                ->whereBetween('due_at', [$todayStart, $todayEnd])
                ->when($pendingFollowUpStatusIds->isNotEmpty(), fn ($q) => $q->whereIn('follow_up_status_id', $pendingFollowUpStatusIds))
                ->count(),
            'today_site_visits' => (clone $siteVisitQuery)
                ->whereBetween('scheduled_at', [$todayStart, $todayEnd])
                ->count(),
            'overdue_follow_ups' => (clone $followUpQuery)
                ->where('due_at', '<', now())
                ->when($pendingFollowUpStatusIds->isNotEmpty(), fn ($q) => $q->whereIn('follow_up_status_id', $pendingFollowUpStatusIds))
                ->count(),
            'duplicate_submissions' => Lead::query()
                ->when(! $user->canViewAllLeads(), fn ($q) => $q->where('assigned_to', $user->id))
                ->where('is_duplicate', true)
                ->count(),
            'generated_at' => now()->toIso8601String(),
        ];
    }
}
