<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use App\Models\MetaWebhookEvent;
use App\Services\Meta\MetaLeadIngestor;
use App\Services\Meta\MetaWebhookHealth;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class MetaController extends Controller
{
    public function __construct(
        private readonly MetaLeadIngestor $ingestor,
        private readonly MetaWebhookHealth $webhookHealth,
    ) {}

    public function showConnection(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('meta.manage'), 403);
        $connection = MetaConnection::query()->with('forms')->latest('id')->first();
        $webhookUrl = rtrim((string) config('app.url'), '/').'/api/v1/meta/webhook';

        return response()->json([
            'data' => [
                'id' => $connection?->id,
                'app_id' => $connection?->app_id,
                'page_id' => $connection?->page_id,
                'page_name' => $connection?->page_name,
                'status' => $connection?->status ?? 'disconnected',
                'connected_at' => $connection?->connected_at?->toIso8601String(),
                'has_page_token' => filled($connection?->page_access_token),
                'has_app_secret' => filled($connection?->app_secret),
                'has_verify_token' => filled($connection?->webhook_verify_token_hash),
                'forms' => $connection?->forms ?? [],
                'webhook_callback_url' => $webhookUrl,
                'setup_steps' => [
                    'Create a Meta App and add the Lead Ads / Webhooks product.',
                    'Paste App ID and App Secret below (must be the SAME app that owns the webhook URL).',
                    'Generate a verify token here, then use the same token in Meta webhook settings.',
                    'Set Callback URL to the webhook URL shown below and subscribe to leadgen.',
                    'Generate a Page access token FROM THAT SAME APP, then save Page ID + token here.',
                    'On VPS run: php artisan meta:subscribe-page (Page must subscribe CRM app to leadgen).',
                    'Register the Lead Form ID(s). Use Meta → Diagnose webhook health to verify.',
                ],
                'webhook_note' => 'Dummy Test + manual fetch can work even when LIVE auto-webhook is broken. Live leads only reach the app listed on the Page subscribed_apps with field=leadgen.',
            ],
        ]);
    }

    public function webhookHealth(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('meta.manage'), 403);

        return response()->json([
            'data' => $this->webhookHealth->diagnose(),
        ]);
    }

    public function upsertConnection(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('meta.manage'), 403);

        $data = $request->validate([
            'app_id' => ['nullable', 'string', 'max:255'],
            'app_secret' => ['nullable', 'string', 'max:2000'],
            'page_id' => ['nullable', 'string', 'max:255'],
            'page_name' => ['nullable', 'string', 'max:255'],
            'page_access_token' => ['nullable', 'string', 'max:5000'],
            'webhook_verify_token' => ['nullable', 'string', 'max:255'],
            'status' => ['nullable', 'string', 'max:32'],
        ]);

        if (! filled(config('app.key'))) {
            return response()->json([
                'message' => 'APP_KEY is missing on server. Run php artisan key:generate in backend/.env',
            ], 500);
        }

        try {
            $connection = MetaConnection::query()->latest('id')->first() ?? new MetaConnection();
            $connection->fill([
                'app_id' => $data['app_id'] ?? $connection->app_id,
                'page_id' => $data['page_id'] ?? $connection->page_id,
                'page_name' => $data['page_name'] ?? $connection->page_name,
                'status' => $data['status'] ?? 'connected',
                'connected_at' => now(),
                'updated_by' => $request->user()->id,
            ]);

            if (! empty($data['app_secret'])) {
                $connection->app_secret = $data['app_secret'];
            }
            if (! empty($data['page_access_token'])) {
                $connection->page_access_token = $data['page_access_token'];
            }
            if (! empty($data['webhook_verify_token'])) {
                $connection->webhook_verify_token_hash = Hash::make($data['webhook_verify_token']);
            }

            $connection->save();
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'message' => 'Failed to store Meta credentials: '.$e->getMessage(),
            ], 500);
        }

        AuditLog::query()->create([
            'actor_id' => $request->user()->id,
            'action' => 'meta.connection_updated',
            'entity_type' => MetaConnection::class,
            'entity_id' => $connection->id,
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'data' => [
                'id' => $connection->id,
                'status' => $connection->status,
                'page_name' => $connection->page_name,
                'webhook_callback_url' => rtrim((string) config('app.url'), '/').'/api/v1/meta/webhook',
            ],
        ]);
    }

    public function syncForms(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('meta.manage'), 403);
        $data = $request->validate([
            'forms' => ['required', 'array', 'min:1'],
            'forms.*.form_id' => ['required', 'string'],
            'forms.*.form_name' => ['nullable', 'string'],
            'forms.*.is_active' => ['sometimes', 'boolean'],
        ]);

        $connection = MetaConnection::query()->latest('id')->firstOrFail();
        $saved = [];
        foreach ($data['forms'] as $form) {
            $saved[] = MetaLeadForm::query()->updateOrCreate(
                [
                    'meta_connection_id' => $connection->id,
                    'form_id' => $form['form_id'],
                ],
                [
                    'form_name' => $form['form_name'] ?? null,
                    'is_active' => $form['is_active'] ?? true,
                ]
            );
        }

        return response()->json(['data' => $saved]);
    }

    public function verifyWebhook(Request $request)
    {
        $mode = $request->query('hub_mode', $request->query('hub.mode'));
        $token = $request->query('hub_verify_token', $request->query('hub.verify_token'));
        $challenge = $request->query('hub_challenge', $request->query('hub.challenge'));

        if ($mode === 'subscribe' && is_string($token) && $this->ingestor->verifyToken($token)) {
            return response($challenge ?? '', 200)->header('Content-Type', 'text/plain');
        }

        return response('Forbidden', 403);
    }

    public function receiveWebhook(Request $request): JsonResponse
    {
        $signature = $request->header('X-Hub-Signature-256');
        $connection = MetaConnection::query()->latest('id')->first();
        $appSecret = $connection?->app_secret ?: config('services.meta.app_secret');

        if ($appSecret && $signature) {
            $expected = 'sha256='.hash_hmac('sha256', $request->getContent(), $appSecret);
            if (! hash_equals($expected, $signature)) {
                Log::warning('Meta webhook rejected: invalid X-Hub-Signature-256 (App Secret mismatch?)', [
                    'has_app_secret' => filled($appSecret),
                    'app_id' => $connection?->app_id,
                ]);
                // Persist so meta:check-logs / webhook-health can surface the mismatch.
                MetaWebhookEvent::query()->create([
                    'payload' => $request->all(),
                    'status' => 'rejected_signature',
                    'error_message' => 'Invalid X-Hub-Signature-256 — App Secret in CRM must match the Meta App sending webhooks.',
                ]);

                return response()->json(['message' => 'Invalid signature'], 403);
            }
        } elseif ($appSecret && ! $signature) {
            // Live Meta webhooks normally sign; missing signature is unusual but allow for some Test tools.
            Log::info('Meta webhook received without X-Hub-Signature-256');
        }

        // Fast ACK path: persist + process synchronously for V1 (queue optional later).
        $event = $this->ingestor->handleWebhookPayload($request->all());

        return response()->json([
            'status' => 'ok',
            'event_id' => $event->id,
        ]);
    }

    public function generateVerifyToken(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('meta.manage'), 403);
        $token = Str::random(40);

        return response()->json([
            'webhook_verify_token' => $token,
            'note' => 'Save this token via POST /meta/connection. It is shown once.',
        ]);
    }
}
