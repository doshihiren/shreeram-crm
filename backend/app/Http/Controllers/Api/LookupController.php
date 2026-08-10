<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FollowUpStatus;
use App\Models\LeadPurpose;
use App\Models\LeadSource;
use App\Models\LeadStage;
use App\Models\PropertyConfiguration;
use App\Models\PropertyType;
use App\Models\SiteVisitStatus;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class LookupController extends Controller
{
    public function sources(): JsonResponse
    {
        return response()->json([
            'data' => LeadSource::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function stages(): JsonResponse
    {
        return response()->json([
            'data' => LeadStage::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function propertyTypes(): JsonResponse
    {
        return response()->json([
            'data' => PropertyType::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function propertyConfigurations(): JsonResponse
    {
        return response()->json([
            'data' => PropertyConfiguration::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function purposes(): JsonResponse
    {
        return response()->json([
            'data' => LeadPurpose::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function siteVisitStatuses(): JsonResponse
    {
        return response()->json([
            'data' => SiteVisitStatus::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function followUpStatuses(): JsonResponse
    {
        return response()->json([
            'data' => FollowUpStatus::query()->where('is_active', true)->orderBy('sort_order')->get(),
        ]);
    }

    public function storeSource(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('sources.manage'), 403);
        $data = $request->validate([
            'code' => ['required', 'string', 'max:64', 'unique:lead_sources,code'],
            'name' => ['required', 'string', 'max:255'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
        ]);
        $row = LeadSource::query()->create([
            'code' => strtoupper($data['code']),
            'name' => $data['name'],
            'sort_order' => $data['sort_order'] ?? 0,
            'is_active' => true,
        ]);

        return response()->json(['data' => $row], 201);
    }

    public function storeStage(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('stages.manage'), 403);
        $data = $request->validate([
            'code' => ['required', 'string', 'max:64', 'unique:lead_stages,code'],
            'name' => ['required', 'string', 'max:255'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
            'is_lost' => ['sometimes', 'boolean'],
            'is_terminal' => ['sometimes', 'boolean'],
            'color' => ['nullable', 'string', 'max:32'],
        ]);
        $row = LeadStage::query()->create([
            'code' => strtoupper($data['code']),
            'name' => $data['name'],
            'sort_order' => $data['sort_order'] ?? 0,
            'is_lost' => $data['is_lost'] ?? false,
            'is_terminal' => $data['is_terminal'] ?? false,
            'color' => $data['color'] ?? null,
            'is_active' => true,
        ]);

        return response()->json(['data' => $row], 201);
    }

    public function updateStage(Request $request, LeadStage $leadStage): JsonResponse
    {
        abort_unless($request->user()->hasPermission('stages.manage'), 403);
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'sort_order' => ['sometimes', 'integer', 'min:0'],
            'is_lost' => ['sometimes', 'boolean'],
            'is_terminal' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'color' => ['nullable', 'string', 'max:32'],
        ]);
        $leadStage->update($data);

        return response()->json(['data' => $leadStage]);
    }
}
