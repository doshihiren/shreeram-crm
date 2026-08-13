<?php

namespace App\Console\Commands;

use App\Models\Lead;
use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use App\Models\MetaLeadIngestion;
use App\Models\MetaWebhookEvent;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class CheckMetaLogs extends Command
{
    protected $signature = 'meta:check-logs
        {--lines=80 : How many laravel.log Meta lines to show}
        {--ingestions=20 : Recent meta_lead_ingestions rows}
        {--events=15 : Recent meta_webhook_events rows}';

    protected $description = 'Show Meta webhook/ingest errors + token health (use this when real leads are missing)';

    public function handle(): int
    {
        $this->info('=== A) Meta connection ===');
        $connection = MetaConnection::query()->latest('id')->first();
        if (! $connection) {
            $this->error('No meta_connections row. Save Meta settings in CRM first.');

            return self::FAILURE;
        }

        $token = $connection->page_access_token ?: config('services.meta.page_access_token');
        $version = config('services.meta.api_version', 'v21.0');
        $formId = (string) (MetaLeadForm::query()->latest('id')->value('form_id') ?: '1301528194957429');

        $this->table(['Field', 'Value'], [
            ['connection_id', (string) $connection->id],
            ['app_id', (string) ($connection->app_id ?: '(empty)')],
            ['page_id', (string) ($connection->page_id ?: '(empty)')],
            ['page_name', (string) ($connection->page_name ?: '')],
            ['status', (string) $connection->status],
            ['has_token', $token ? 'yes' : 'NO'],
            ['token_prefix', $token ? substr($token, 0, 14).'…' : ''],
            ['forms', MetaLeadForm::query()->pluck('form_id')->implode(', ') ?: '(none)'],
            ['webhook_url', rtrim((string) config('app.url'), '/').'/api/v1/meta/webhook'],
        ]);

        $this->newLine();
        $this->info('=== B) Token identity (/me) ===');
        if (! $token) {
            $this->error('No token saved.');
        } else {
            $me = Http::timeout(20)->get("https://graph.facebook.com/{$version}/me", [
                'access_token' => $token,
                'fields' => 'id,name',
            ]);
            $this->line('HTTP '.$me->status().' '.$me->body());
            $meId = (string) ($me->json('id') ?? '');
            if ($me->successful() && $connection->page_id && $meId === (string) $connection->page_id) {
                $this->info('OK: PAGE token');
            } elseif ($me->successful()) {
                $this->warn('This looks like a USER/System token identity, not the Page id. Form pull may still work if permissions are granted.');
            }
        }

        if ($token && $connection->page_id) {
            $this->newLine();
            $this->info('=== C) Page leadgen forms ===');
            $forms = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$connection->page_id}/leadgen_forms", [
                'access_token' => $token,
                'fields' => 'id,name,status,leads_count',
                'limit' => 25,
            ]);
            $this->line('HTTP '.$forms->status());
            if ($forms->successful()) {
                foreach ($forms->json('data') ?? [] as $f) {
                    $mark = ((string) ($f['id'] ?? '')) === $formId ? ' <== CRM form' : '';
                    $this->line(sprintf(
                        '  %s | %s | %s | leads=%s%s',
                        $f['id'] ?? '',
                        $f['name'] ?? '',
                        $f['status'] ?? '',
                        $f['leads_count'] ?? '?',
                        $mark
                    ));
                }
            } else {
                $this->error($forms->body());
            }

            $this->newLine();
            $this->info('=== D) Form leads sample (/'.$formId.'/leads) ===');
            $leads = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$formId}/leads", [
                'access_token' => $token,
                'limit' => 3,
                'fields' => 'id,created_time',
            ]);
            $this->line('HTTP '.$leads->status().' '.substr($leads->body(), 0, 600));

            $this->newLine();
            $this->info('=== E) Page subscribed_apps (webhook delivery) ===');
            $apps = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$connection->page_id}/subscribed_apps", [
                'access_token' => $token,
            ]);
            $this->line('HTTP '.$apps->status().' '.substr($apps->body(), 0, 700));
            if ($apps->successful()) {
                $hasLeadgen = false;
                foreach ($apps->json('data') ?? [] as $app) {
                    $fields = $app['subscribed_fields'] ?? [];
                    if (in_array('leadgen', $fields, true)) {
                        $hasLeadgen = true;
                    }
                    $this->line('  app='.($app['id'] ?? '?').' fields='.implode(',', is_array($fields) ? $fields : []));
                }
                if (! $hasLeadgen) {
                    $this->error('Page is NOT subscribed to leadgen for this app. Real leads will not webhook in.');
                    $this->warn('Fix with (Page token required):');
                    $this->line('  php artisan meta:subscribe-page');
                } else {
                    $this->info('OK: leadgen subscription present');
                }
            }
        }

        $this->newLine();
        $this->info('=== F) Recent webhook events ===');
        $events = MetaWebhookEvent::query()->latest('id')->limit((int) $this->option('events'))->get([
            'id', 'status', 'error_message', 'created_at',
        ]);
        if ($events->isEmpty()) {
            $this->warn('No webhook events in DB. Meta is not POSTing to your callback (or URL/app mismatch).');
        } else {
            $this->table(
                ['id', 'status', 'error', 'created_at'],
                $events->map(fn ($e) => [
                    $e->id,
                    $e->status,
                    \Illuminate\Support\Str::limit((string) $e->error_message, 60),
                    (string) $e->created_at,
                ])->all()
            );
        }

        $this->newLine();
        $this->info('=== G) Recent lead ingestions ===');
        $ingestions = MetaLeadIngestion::query()->latest('id')->limit((int) $this->option('ingestions'))->get([
            'id', 'leadgen_id', 'status', 'message', 'lead_id', 'created_at',
        ]);
        if ($ingestions->isEmpty()) {
            $this->warn('No ingestions yet.');
        } else {
            $this->table(
                ['id', 'leadgen_id', 'status', 'message', 'lead_id', 'created_at'],
                $ingestions->map(fn ($i) => [
                    $i->id,
                    \Illuminate\Support\Str::limit((string) $i->leadgen_id, 28),
                    $i->status,
                    \Illuminate\Support\Str::limit((string) $i->message, 50),
                    $i->lead_id,
                    (string) $i->created_at,
                ])->all()
            );
        }

        $counts = [
            'ingestions_processed' => MetaLeadIngestion::query()->where('status', 'processed')->count(),
            'ingestions_sample' => MetaLeadIngestion::query()->where('status', 'processed_sample')->count(),
            'ingestions_failed' => MetaLeadIngestion::query()->where('status', 'failed')->count(),
            'ingestions_duplicate' => MetaLeadIngestion::query()->where('status', 'duplicate')->count(),
            'leads_total' => Lead::query()->count(),
            'leads_meta_source' => Lead::query()->whereHas('source', fn ($q) => $q->where('code', 'META'))->count(),
        ];
        $this->newLine();
        $this->info('=== H) Counts ===');
        $this->table(['metric', 'count'], collect($counts)->map(fn ($v, $k) => [$k, $v])->values()->all());

        $this->newLine();
        $this->info('=== I) Laravel log (Meta lines) ===');
        $logPath = storage_path('logs/laravel.log');
        if (! is_file($logPath)) {
            $this->warn('No laravel.log at '.$logPath);
        } else {
            $lines = (int) $this->option('lines');
            $cmd = 'grep -E "Meta Graph|Meta webhook|leadgen|GraphMethodException|OAuthException" '.escapeshellarg($logPath).' | tail -n '.$lines;
            $this->line('$ '.$cmd);
            passthru($cmd, $exit);
            if ($exit !== 0) {
                $this->warn('No matching Meta lines in laravel.log (or grep found none).');
            }
        }

        $this->newLine();
        $this->info('=== Next actions ===');
        $this->line('1) If section E says no leadgen: php artisan meta:subscribe-page');
        $this->line('2) Backfill July → now:');
        $this->line('   php artisan meta:import-leads --form='.$formId.' --since=2026-07-01 --limit=500');
        $this->line('3) Re-check: php artisan meta:check-logs');

        return self::SUCCESS;
    }
}
