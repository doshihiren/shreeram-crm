<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\FollowUpController;
use App\Http\Controllers\Api\LeadController;
use App\Http\Controllers\Api\LookupController;
use App\Http\Controllers\Api\MetaController;
use App\Http\Controllers\Api\SiteVisitController;
use App\Http\Controllers\Api\UserController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::post('/auth/login', [AuthController::class, 'login']);

    // Meta webhook must be public (verified via token/signature).
    Route::get('/meta/webhook', [MetaController::class, 'verifyWebhook']);
    Route::post('/meta/webhook', [MetaController::class, 'receiveWebhook']);

    Route::middleware(['auth:sanctum', 'active'])->group(function () {
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::get('/auth/me', [AuthController::class, 'me']);

        Route::get('/dashboard/summary', [DashboardController::class, 'summary']);

        Route::get('/lead-sources', [LookupController::class, 'sources']);
        Route::post('/lead-sources', [LookupController::class, 'storeSource']);
        Route::get('/lead-stages', [LookupController::class, 'stages']);
        Route::post('/lead-stages', [LookupController::class, 'storeStage']);
        Route::patch('/lead-stages/{leadStage}', [LookupController::class, 'updateStage']);
        Route::get('/property-types', [LookupController::class, 'propertyTypes']);
        Route::get('/property-configurations', [LookupController::class, 'propertyConfigurations']);
        Route::get('/purposes', [LookupController::class, 'purposes']);
        Route::get('/site-visit-statuses', [LookupController::class, 'siteVisitStatuses']);
        Route::get('/follow-up-statuses', [LookupController::class, 'followUpStatuses']);

        Route::get('/leads', [LeadController::class, 'index']);
        Route::post('/leads', [LeadController::class, 'store']);
        Route::get('/leads/{lead}', [LeadController::class, 'show']);
        Route::patch('/leads/{lead}', [LeadController::class, 'update']);
        Route::patch('/leads/{lead}/stage', [LeadController::class, 'updateStage']);
        Route::patch('/leads/{lead}/assign', [LeadController::class, 'assign']);
        Route::post('/leads/{lead}/remarks', [LeadController::class, 'addRemark']);
        Route::get('/leads/{lead}/activities', [LeadController::class, 'activities']);

        Route::get('/follow-ups', [FollowUpController::class, 'index']);
        Route::post('/follow-ups', [FollowUpController::class, 'store']);
        Route::patch('/follow-ups/{followUp}', [FollowUpController::class, 'update']);

        Route::get('/site-visits', [SiteVisitController::class, 'index']);
        Route::post('/site-visits', [SiteVisitController::class, 'store']);
        Route::patch('/site-visits/{siteVisit}', [SiteVisitController::class, 'update']);

        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::patch('/users/{user}', [UserController::class, 'update']);

        Route::get('/meta/connection', [MetaController::class, 'showConnection']);
        Route::post('/meta/connection', [MetaController::class, 'upsertConnection']);
        Route::post('/meta/forms/sync', [MetaController::class, 'syncForms']);
        Route::post('/meta/webhook-token', [MetaController::class, 'generateVerifyToken']);
    });
});
