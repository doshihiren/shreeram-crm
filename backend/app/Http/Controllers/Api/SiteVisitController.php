<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Lead;
use App\Models\LeadActivity;
use App\Models\SiteVisit;
use App\Models\SiteVisitStatus;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SiteVisitController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $query = SiteVisit::query()
            ->with(['lead:id,name,mobile', 'status', 'assignee:id,name'])
            ->when(! $user->canViewAllLeads(), fn ($q) => $q->where('assigned_to', $user->id))
            ->when($request->string('when') === 'today', fn ($q) => $q->whereDate('scheduled_at', today()))
            ->latest('scheduled_at');

        return response()->json($query->paginate(min((int) $request->integer('per_page', 20), 50)));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'lead_id' => ['required', 'exists:leads,id'],
            'scheduled_at' => ['required', 'date'],
            'remarks' => ['nullable', 'string', 'max:5000'],
            'assigned_to' => ['nullable', 'exists:users,id'],
        ]);

        /** @var User $user */
        $user = $request->user();
        $lead = Lead::query()->findOrFail($data['lead_id']);
        abort_unless($user->canViewAllLeads() || $lead->assigned_to === $user->id, 403);

        $planned = SiteVisitStatus::query()->where('code', 'PLANNED')->firstOrFail();
        $visit = SiteVisit::query()->create([
            'lead_id' => $lead->id,
            'assigned_to' => $data['assigned_to'] ?? $lead->assigned_to ?? $user->id,
            'created_by' => $user->id,
            'site_visit_status_id' => $planned->id,
            'scheduled_at' => $data['scheduled_at'],
            'remarks' => $data['remarks'] ?? null,
        ]);

        $lead->update([
            'interested_in_site_visit' => true,
            'preferred_visit_date' => $visit->scheduled_at?->toDateString(),
            'preferred_visit_time' => $visit->scheduled_at?->format('H:i'),
            'site_visit_status_id' => $planned->id,
        ]);

        LeadActivity::query()->create([
            'lead_id' => $lead->id,
            'user_id' => $user->id,
            'type' => 'site_visit',
            'body' => 'Site visit planned.',
            'meta' => ['site_visit_id' => $visit->id],
        ]);

        return response()->json(['data' => $visit->load(['status', 'assignee'])], 201);
    }

    public function update(Request $request, SiteVisit $siteVisit): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        abort_unless($user->canViewAllLeads() || $siteVisit->assigned_to === $user->id, 403);

        $data = $request->validate([
            'scheduled_at' => ['sometimes', 'date'],
            'remarks' => ['nullable', 'string', 'max:5000'],
            'site_visit_status_id' => ['sometimes', 'exists:site_visit_statuses,id'],
            'mark_done' => ['sometimes', 'boolean'],
        ]);

        if ($request->boolean('mark_done')) {
            $done = SiteVisitStatus::query()->where('code', 'DONE')->firstOrFail();
            $data['site_visit_status_id'] = $done->id;
            $data['completed_at'] = now();
        }

        $siteVisit->update($data);
        if (isset($data['site_visit_status_id'])) {
            $siteVisit->lead?->update(['site_visit_status_id' => $data['site_visit_status_id']]);
        }

        return response()->json(['data' => $siteVisit->fresh(['status', 'assignee', 'lead'])]);
    }
}
