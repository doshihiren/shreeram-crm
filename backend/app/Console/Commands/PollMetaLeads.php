<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class PollMetaLeads extends Command
{
    protected $signature = 'meta:poll-leads
        {--limit=40 : Max leads per form to check}
        {--hours=48 : Look back window in hours}';

    protected $description = 'Safety-net poll: pull recent Meta form leads via Graph (covers webhook gaps)';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            $this->warn('No Meta page token — skip poll.');

            return self::SUCCESS;
        }

        $forms = MetaLeadForm::query()->where('is_active', true)->pluck('form_id')->filter()->values();
        if ($forms->isEmpty()) {
            $forms = collect(['1301528194957429']);
        }

        $hours = max(1, (int) $this->option('hours'));
        $since = now()->subHours($hours)->toDateString();
        $limit = max(1, (int) $this->option('limit'));

        $ok = 0;
        $fail = 0;
        $new = 0;

        foreach ($forms as $formId) {
            $this->line("Polling form {$formId} since {$since}…");
            $exit = Artisan::call('meta:import-leads', [
                '--form' => (string) $formId,
                '--limit' => $limit,
                '--since' => $since,
            ]);
            $output = Artisan::output();
            $this->line(trim($output));

            if (preg_match('/imported_or_duplicate=(\d+)\s+failed=(\d+)/', $output, $m)) {
                $ok += (int) $m[1];
                $fail += (int) $m[2];
            }
            if (preg_match_all('/status=processed\b/', $output, $mm)) {
                $new += count($mm[0] ?? []);
            }

            if ($exit !== 0 && $fail === 0) {
                // import command returns FAILURE when any fail; still continue other forms
                Log::warning('meta:poll-leads form import non-zero', ['form' => $formId, 'exit' => $exit]);
            }
        }

        // Light webhook delivery check (log only)
        if ($connection?->page_id) {
            $version = config('services.meta.api_version', 'v21.0');
            $crmAppId = (string) ($connection->app_id ?: '');
            $apps = Http::timeout(15)->get("https://graph.facebook.com/{$version}/{$connection->page_id}/subscribed_apps", [
                'access_token' => $token,
            ]);
            if ($apps->successful()) {
                $crmOk = false;
                foreach ($apps->json('data') ?? [] as $app) {
                    if ($crmAppId !== '' && (string) ($app['id'] ?? '') === $crmAppId
                        && in_array('leadgen', $app['subscribed_fields'] ?? [], true)) {
                        $crmOk = true;
                    }
                }
                if (! $crmOk) {
                    Log::warning('meta:poll-leads: CRM app missing leadgen subscription — webhook auto-delivery will not work', [
                        'crm_app_id' => $crmAppId,
                        'page_id' => $connection->page_id,
                    ]);
                    $this->warn('Webhook still broken: CRM app not subscribed to leadgen. Poller is covering the gap.');
                    $this->line('Fix: php artisan meta:subscribe-page && php artisan meta:check-logs');
                }
            }
        }

        $this->info("Poll done. new_or_dup≈{$ok} failed={$fail} newly_processed≈{$new}");

        return self::SUCCESS;
    }
}
