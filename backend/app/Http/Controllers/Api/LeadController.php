<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\LeadResource;
use App\Models\Lead;
use App\Models\LeadActivity;
use App\Models\LeadAssignment;
use App\Models\LeadStage;
use App\Models\User;
use App\Services\Lead\LeadIntakeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class LeadController extends Controller
{
    public function __construct(
        private readonly LeadIntakeService $intake,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        /** @var User $user */
        $user = $request->user();
        $perPage = min((int) $request->integer('per_page', 50), 200);

        $query = Lead::query()
            ->with(['source', 'stage', 'assignee', 'propertyType', 'propertyConfiguration', 'purpose', 'metaAttribution'])
            ->when(! $user->canViewAllLeads(), function ($q) use ($user) {
                $q->where(function ($inner) use ($user) {
                    $inner->where('assigned_to', $user->id)
                        ->orWhereNull('assigned_to');
                });
            })
            ->when($request->filled('stage_id'), fn ($q) => $q->where('lead_stage_id', $request->integer('stage_id')))
            ->when($request->filled('source_id'), fn ($q) => $q->where('lead_source_id', $request->integer('source_id')))
            ->when($request->filled('assigned_to'), fn ($q) => $q->where('assigned_to', $request->integer('assigned_to')))
            ->when($request->boolean('exclude_duplicates', true), fn ($q) => $q->where('is_duplicate', false))
            ->when($request->filled('q'), function ($q) use ($request) {
                $term = '%'.$request->string('q').'%';
                $q->where(function ($inner) use ($term) {
                    $inner->where('name', 'like', $term)
                        ->orWhere('mobile', 'like', $term)
                        ->orWhere('email', 'like', $term);
                });
            })
            ->latest('id');

        return LeadResource::collection($query->paginate($perPage));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'mobile' => ['required', 'string', 'max:32'],
            'email' => ['nullable', 'email', 'max:255'],
            'lead_source_id' => ['required', 'exists:lead_sources,id'],
            'lead_stage_id' => ['nullable', 'exists:lead_stages,id'],
            'property_type_id' => ['nullable', 'exists:property_types,id'],
            'property_configuration_id' => ['nullable', 'exists:property_configurations,id'],
            'preferred_location' => ['nullable', 'string', 'max:255'],
            'purpose_id' => ['nullable', 'exists:lead_purposes,id'],
            'assigned_to' => ['nullable', 'exists:users,id'],
            'interested_in_site_visit' => ['sometimes', 'boolean'],
            'preferred_visit_date' => ['nullable', 'date'],
            'preferred_visit_time' => ['nullable', 'date_format:H:i'],
        ]);

        /** @var User $user */
        $user = $request->user();
        if (! $user->canViewAllLeads()) {
            $data['assigned_to'] = $user->id;
        }

        $result = $this->intake->intake($data, [], $user);

        return response()->json([
            'data' => new LeadResource($result['lead']),
            'created' => $result['created'],
            'duplicate' => $result['duplicate'],
        ], $result['created'] ? 201 : 200);
    }

    public function show(Request $request, Lead $lead): LeadResource
    {
        $this->authorizeLead($request->user(), $lead);
        $lead->load([
            'source', 'stage', 'assignee', 'propertyType', 'propertyConfiguration',
            'purpose', 'metaAttribution', 'followUpStatus', 'siteVisitStatus',
        ]);

        return new LeadResource($lead);
    }

    public function update(Request $request, Lead $lead): LeadResource
    {
        $this->authorizeLead($request->user(), $lead, mutate: true);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'mobile' => ['sometimes', 'string', 'max:32'],
            'email' => ['nullable', 'email', 'max:255'],
            'property_type_id' => ['nullable', 'exists:property_types,id'],
            'property_configuration_id' => ['nullable', 'exists:property_configurations,id'],
            'preferred_location' => ['nullable', 'string', 'max:255'],
            'purpose_id' => ['nullable', 'exists:lead_purposes,id'],
            'interested_in_site_visit' => ['sometimes', 'boolean'],
            'preferred_visit_date' => ['nullable', 'date'],
            'preferred_visit_time' => ['nullable', 'date_format:H:i'],
            'next_follow_up_at' => ['nullable', 'date'],
        ]);

        if (isset($data['mobile'])) {
            $data['mobile_normalized'] = Lead::normalizeMobile($data['mobile']);
        }

        $lead->update($data);

        return new LeadResource($lead->fresh([
            'source', 'stage', 'assignee', 'propertyType', 'propertyConfiguration', 'purpose',
        ]));
    }

    public function updateStage(Request $request, Lead $lead): LeadResource
    {
        $this->authorizeLead($request->user(), $lead, mutate: true);
        $data = $request->validate([
            'lead_stage_id' => ['required', 'exists:lead_stages,id'],
            'lost_reason' => ['nullable', 'string', 'max:500'],
            'next_follow_up_at' => ['nullable', 'date'],
            'remarks' => ['nullable', 'string', 'max:5000'],
        ]);

        $stage = LeadStage::query()->findOrFail($data['lead_stage_id']);
        $requiresFollowUp = ! $stage->is_lost && $stage->code !== 'UNIT_BOOKED';

        if ($requiresFollowUp && empty($data['next_follow_up_at'])) {
            // Call Not Received → tomorrow 10:00 server local if client omitted it.
            if ($stage->code === 'CALL_NOT_RECEIVED') {
                $data['next_follow_up_at'] = now()->addDay()->setTime(10, 0)->toIso8601String();
            } else {
                throw ValidationException::withMessages([
                    'next_follow_up_at' => ['Next follow-up date is required for this status.'],
                ]);
            }
        }
        if ($requiresFollowUp && empty($data['remarks'])) {
            throw ValidationException::withMessages([
                'remarks' => ['Remarks are required for this status.'],
            ]);
        }

        $lead = $this->intake->changeStage($lead, $stage, $request->user(), $data['lost_reason'] ?? null);

        if (! empty($data['next_follow_up_at'])) {
            $lead->update(['next_follow_up_at' => $data['next_follow_up_at']]);
        }

        if (! empty($data['remarks'])) {
            LeadActivity::query()->create([
                'lead_id' => $lead->id,
                'user_id' => $request->user()->id,
                'type' => 'remark',
                'body' => $data['remarks'],
            ]);

            if (! empty($data['next_follow_up_at'])) {
                $pendingStatusId = \App\Models\FollowUpStatus::query()->where('code', 'PENDING')->value('id');
                if ($pendingStatusId) {
                    \App\Models\FollowUp::query()->create([
                        'lead_id' => $lead->id,
                        'assigned_to' => $lead->assigned_to ?? $request->user()->id,
                        'due_at' => $data['next_follow_up_at'],
                        'remarks' => $data['remarks'],
                        'follow_up_status_id' => $pendingStatusId,
                        'created_by' => $request->user()->id,
                    ]);
                }
            }
        }

        return new LeadResource($lead->fresh(['source', 'stage', 'assignee', 'metaAttribution']));
    }

    public function assign(Request $request, Lead $lead): LeadResource
    {
        /** @var User $user */
        $user = $request->user();
        abort_unless($user->hasPermission('leads.assign'), 403);

        $data = $request->validate([
            'assigned_to' => ['nullable', 'exists:users,id'],
            'reason' => ['nullable', 'string', 'max:255'],
        ]);

        $lead->update(['assigned_to' => $data['assigned_to'] ?? null]);
        LeadAssignment::query()->create([
            'lead_id' => $lead->id,
            'assigned_to' => $data['assigned_to'] ?? null,
            'assigned_by' => $user->id,
            'reason' => $data['reason'] ?? 'manual_assignment',
        ]);
        LeadActivity::query()->create([
            'lead_id' => $lead->id,
            'user_id' => $user->id,
            'type' => 'assignment',
            'body' => 'Lead assignment updated.',
            'meta' => ['assigned_to' => $data['assigned_to'] ?? null],
        ]);

        return new LeadResource($lead->fresh(['source', 'stage', 'assignee']));
    }

    public function addRemark(Request $request, Lead $lead): JsonResponse
    {
        $this->authorizeLead($request->user(), $lead, mutate: true);
        $data = $request->validate([
            'body' => ['required', 'string', 'max:5000'],
        ]);

        $activity = LeadActivity::query()->create([
            'lead_id' => $lead->id,
            'user_id' => $request->user()->id,
            'type' => 'remark',
            'body' => $data['body'],
        ]);

        return response()->json(['data' => $activity], 201);
    }

    public function activities(Request $request, Lead $lead): JsonResponse
    {
        $this->authorizeLead($request->user(), $lead);

        $activities = $lead->activities()
            ->with('user:id,name')
            ->latest('id')
            ->paginate(min((int) $request->integer('per_page', 20), 50));

        return response()->json($activities);
    }

    private function authorizeLead(?User $user, Lead $lead, bool $mutate = false): void
    {
        abort_unless($user !== null, 401);
        if ($user->canViewAllLeads()) {
            return;
        }

        $allowed = $lead->assigned_to === $user->id || ($lead->assigned_to === null && ! $mutate);
        if ($mutate) {
            $allowed = $lead->assigned_to === $user->id;
        }
        abort_unless($allowed, 403);
    }
}
