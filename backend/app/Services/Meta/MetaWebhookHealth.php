<?php

namespace App\Services\Meta;

use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use App\Models\MetaLeadIngestion;
use App\Models\MetaWebhookEvent;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class MetaWebhookHealth
{
    /**
     * Diagnose why live Meta leads may not auto-arrive in CRM.
     *
     * @return array<string, mixed>
     */
    public function diagnose(?MetaConnection $connection = null): array
    {
        $connection ??= MetaConnection::query()->latest('id')->first();
        $version = config('services.meta.api_version', 'v21.0');
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        $crmAppId = (string) ($connection?->app_id ?: config('services.meta.app_id') ?: '');
        $pageId = (string) ($connection?->page_id ?: '');

        $issues = [];
        $apps = [];
        $crmAppHasLeadgen = false;
        $anyLeadgen = false;
        $tokenIdentity = null;

        if (! $connection) {
            $issues[] = [
                'code' => 'no_connection',
                'severity' => 'error',
                'message' => 'No Meta connection saved in CRM.',
            ];
        }
        if ($crmAppId === '') {
            $issues[] = [
                'code' => 'missing_app_id',
                'severity' => 'error',
                'message' => 'CRM App ID is empty. Save the Meta App ID that has the webhook callback URL.',
            ];
        }
        if (! $token || $pageId === '') {
            $issues[] = [
                'code' => 'missing_page_token',
                'severity' => 'error',
                'message' => 'Page ID or Page access token missing.',
            ];
        }

        if ($token) {
            $me = Http::timeout(20)->get("https://graph.facebook.com/{$version}/me", [
                'access_token' => $token,
                'fields' => 'id,name',
            ]);
            if ($me->successful()) {
                $tokenIdentity = [
                    'id' => (string) ($me->json('id') ?? ''),
                    'name' => (string) ($me->json('name') ?? ''),
                    'is_page_token' => $pageId !== '' && (string) ($me->json('id') ?? '') === $pageId,
                ];
            } else {
                $issues[] = [
                    'code' => 'token_invalid',
                    'severity' => 'error',
                    'message' => 'Page token rejected by Graph: HTTP '.$me->status(),
                ];
            }
        }

        if ($token && $pageId !== '') {
            $appsRes = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$pageId}/subscribed_apps", [
                'access_token' => $token,
            ]);
            if ($appsRes->successful()) {
                foreach ($appsRes->json('data') ?? [] as $app) {
                    $appId = (string) ($app['id'] ?? '');
                    $fields = $app['subscribed_fields'] ?? [];
                    $fields = is_array($fields) ? $fields : [];
                    $hasLeadgen = in_array('leadgen', $fields, true);
                    if ($hasLeadgen) {
                        $anyLeadgen = true;
                    }
                    $isCrm = $crmAppId !== '' && $appId === $crmAppId;
                    if ($isCrm && $hasLeadgen) {
                        $crmAppHasLeadgen = true;
                    }
                    $apps[] = [
                        'id' => $appId,
                        'name' => (string) ($app['name'] ?? ''),
                        'subscribed_fields' => $fields,
                        'has_leadgen' => $hasLeadgen,
                        'is_crm_app' => $isCrm,
                    ];
                }

                if (! $anyLeadgen) {
                    $issues[] = [
                        'code' => 'no_leadgen_subscription',
                        'severity' => 'error',
                        'message' => 'Page has no leadgen subscription. Live form submits will not webhook anywhere.',
                        'fix' => 'php artisan meta:subscribe-page',
                    ];
                } elseif (! $crmAppHasLeadgen) {
                    $other = collect($apps)->firstWhere('has_leadgen', true);
                    $issues[] = [
                        'code' => 'leadgen_on_other_app',
                        'severity' => 'error',
                        'message' => 'leadgen is subscribed on a DIFFERENT Meta app'
                            .($other ? ' ('.$other['name'].' / '.$other['id'].')' : '')
                            .', not your CRM app ('.$crmAppId.'). '
                            .'Demo Test posts to the CRM app webhook, but LIVE leads go to the other app.',
                        'fix' => 'Generate a Page token FROM the CRM Meta App, save it, then run: php artisan meta:subscribe-page',
                    ];
                }
            } else {
                $issues[] = [
                    'code' => 'subscribed_apps_failed',
                    'severity' => 'warning',
                    'message' => 'Could not read subscribed_apps (HTTP '.$appsRes->status().'). Token may lack pages_manage_metadata.',
                ];
            }
        }

        $recentEvents = MetaWebhookEvent::query()->latest('id')->limit(10)->get(['id', 'status', 'error_message', 'created_at']);
        $recentReal = MetaLeadIngestion::query()
            ->where('status', 'processed')
            ->where('leadgen_id', 'not like', 'sample-%')
            ->where('leadgen_id', 'not like', '444%')
            ->latest('id')
            ->limit(5)
            ->get(['id', 'leadgen_id', 'lead_id', 'created_at']);
        $sampleCount = MetaLeadIngestion::query()->where('status', 'processed_sample')->count();
        $failedSig = MetaWebhookEvent::query()->where('status', 'rejected_signature')->count();

        if ($recentEvents->isEmpty()) {
            $issues[] = [
                'code' => 'no_webhook_events',
                'severity' => 'warning',
                'message' => 'No webhook POSTs stored yet. Either Meta is not delivering to this URL, or delivery is going to another app.',
            ];
        }
        if ($failedSig > 0) {
            $issues[] = [
                'code' => 'signature_rejections',
                'severity' => 'error',
                'message' => "{$failedSig} webhook(s) rejected for bad X-Hub-Signature-256. App Secret in CRM must match the Meta App that sends webhooks.",
                'fix' => 'Re-copy App Secret from Meta Developer Console → save in CRM Meta settings.',
            ];
        }

        $ok = $crmAppHasLeadgen && $issues === [];

        return [
            'ok' => $ok,
            'summary' => $ok
                ? 'CRM app is subscribed to leadgen. New real submits should auto-arrive.'
                : 'Auto-webhook is NOT healthy. Manual import / Test button can still work.',
            'why_test_and_manual_work' => [
                'Meta Developer "Test" button posts a dummy payload straight to the webhook URL configured on that App — it does not use Page subscribed_apps the same way live Lead Ads do.',
                'Manual fetch (meta:import-leads) pulls leads via Graph API with the Page token — it never needs the webhook.',
                'Live form fills only notify apps listed on the Page as subscribed_apps with field=leadgen.',
            ],
            'webhook_callback_url' => rtrim((string) config('app.url'), '/').'/api/v1/meta/webhook',
            'crm_app_id' => $crmAppId !== '' ? $crmAppId : null,
            'page_id' => $pageId !== '' ? $pageId : null,
            'token_identity' => $tokenIdentity,
            'subscribed_apps' => $apps,
            'crm_app_has_leadgen' => $crmAppHasLeadgen,
            'forms' => MetaLeadForm::query()->get(['form_id', 'form_name', 'is_active']),
            'recent_webhook_events' => $recentEvents,
            'recent_real_ingestions' => $recentReal,
            'sample_ingestions_count' => $sampleCount,
            'signature_rejections_count' => $failedSig,
            'issues' => $issues,
            'fix_steps' => [
                'In Meta Developer Console open the SAME App whose App ID is saved in CRM.',
                'Webhooks → Callback URL = CRM webhook URL, Verify Token = CRM token, subscribe to leadgen.',
                'Generate a Page access token FROM THAT SAME APP (Graph API Explorer → User/Page token for Shreeram Developer).',
                'Save App ID + App Secret + Page token in CRM Meta settings.',
                'On VPS: php artisan meta:subscribe-page',
                'Confirm: php artisan meta:check-logs  (section E must show CRM app <== with leadgen)',
                'Submit a real test lead on the form; a new meta_webhook_events row should appear within seconds.',
                'Safety net: enable scheduler so meta:poll-leads runs every 5 minutes.',
            ],
        ];
    }
}
