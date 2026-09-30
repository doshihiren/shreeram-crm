<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FollowUp;
use App\Models\FollowUpStatus;
use App\Models\Lead;
use App\Models\LeadActivity;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FollowUpController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $query = FollowUp::query()
            ->with(['lead:id,name,mobile', 'status', 'assignee:id,name'])
            ->when(! $user->canViewAllLeads(), fn ($q) => $q->where('assigned_to', $user->id))
            ->when($request->filled('due'), function ($q) use ($request) {
                if ($request->string('due') === 'today') {
                    $q->whereDate('due_at', today());
                } elseif ($request->string('due') === 'overdue') {
                    $q->where('due_at', '<', now());
                }
            })
            ->latest('due_at');

        return response()->json($query->paginate(min((int) $request->integer('per_page', 20), 50)));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'lead_id' => ['required', 'exists:leads,id'],
            'due_at' => ['required', 'date'],
            'remarks' => ['nullable', 'string', 'max:5000'],
            'assigned_to' => ['nullable', 'exists:users,id'],
        ]);

        /** @var User $user */
        $user = $request->user();
        $lead = Lead::query()->findOrFail($data['lead_id']);
        abort_unless($user->canViewAllLeads() || $lead->assigned_to === $user->id, 403);

        $pending = FollowUpStatus::query()->where('code', 'PENDING')->firstOrFail();
        $followUp = FollowUp::query()->create([
            'lead_id' => $lead->id,
            'assigned_to' => $data['assigned_to'] ?? $lead->assigned_to ?? $user->id,
            'created_by' => $user->id,
            'follow_up_status_id' => $pending->id,
            'due_at' => $data['due_at'],
            'remarks' => $data['remarks'] ?? null,
        ]);

        $lead->update([
            'next_follow_up_at' => $data['due_at'],
            'follow_up_status_id' => $pending->id,
        ]);

        LeadActivity::query()->create([
            'lead_id' => $lead->id,
            'user_id' => $user->id,
            'type' => 'follow_up',
            'body' => 'Follow-up scheduled.',
            'meta' => ['follow_up_id' => $followUp->id, 'due_at' => $followUp->due_at],
        ]);

        return response()->json(['data' => $followUp->load(['status', 'assignee'])], 201);
    }

    public function update(Request $request, FollowUp $followUp): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        abort_unless($user->canViewAllLeads() || $followUp->assigned_to === $user->id, 403);

        $data = $request->validate([
            'due_at' => ['sometimes', 'date'],
            'remarks' => ['nullable', 'string', 'max:5000'],
            'follow_up_status_id' => ['sometimes', 'exists:follow_up_statuses,id'],
            'complete' => ['sometimes', 'boolean'],
        ]);

        if ($request->boolean('complete')) {
            $done = FollowUpStatus::query()->where('code', 'DONE')->firstOrFail();
            $data['follow_up_status_id'] = $done->id;
            $data['completed_at'] = now();
        }

        $followUp->update($data);
        if (isset($data['due_at'])) {
            $followUp->lead?->update(['next_follow_up_at' => $data['due_at']]);
        }

        return response()->json(['data' => $followUp->fresh(['status', 'assignee', 'lead'])]);
    }
}
