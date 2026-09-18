<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Dashboard\DashboardSummaryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function __construct(
        private readonly DashboardSummaryService $summary,
    ) {}

    public function summary(Request $request): JsonResponse
    {
        return response()->json([
            'data' => $this->summary->summarize($request->user()),
        ]);
    }
}
