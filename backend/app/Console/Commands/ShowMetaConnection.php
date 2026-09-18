<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class ShowMetaConnection extends Command
{
    protected $signature = 'meta:show-connection
        {--reveal : Show full secrets (token/app secret) — use only on your private VPS}';

    protected $description = 'Print saved Meta connection values (app/page/token) to verify old vs new app';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        if (! $connection) {
            $this->error('No meta_connections row found.');

            return self::FAILURE;
        }

        $reveal = (bool) $this->option('reveal');
        $token = (string) ($connection->page_access_token ?: '');
        $secret = (string) ($connection->app_secret ?: '');
        $version = config('services.meta.api_version', 'v21.0');

        $this->info('=== meta_connections (latest) ===');
        $this->table(['Field', 'Value'], [
            ['id', (string) $connection->id],
            ['app_id', (string) ($connection->app_id ?: '(empty)')],
            ['page_id', (string) ($connection->page_id ?: '(empty)')],
            ['page_name', (string) ($connection->page_name ?: '(empty)')],
            ['status', (string) ($connection->status ?: '')],
            ['connected_at', (string) ($connection->connected_at ?: '')],
            ['updated_at', (string) ($connection->updated_at ?: '')],
            ['has_app_secret', $secret !== '' ? 'yes' : 'NO'],
            ['has_page_token', $token !== '' ? 'yes' : 'NO'],
            ['has_verify_token_hash', filled($connection->webhook_verify_token_hash) ? 'yes' : 'NO'],
            ['app_secret_preview', $this->preview($secret, $reveal)],
            ['page_token_preview', $this->preview($token, $reveal)],
            ['page_token_length', (string) strlen($token)],
            ['webhook_callback_url', rtrim((string) config('app.url'), '/').'/api/v1/meta/webhook'],
            ['env META_APP_ID', (string) (config('services.meta.app_id') ?: '(empty)')],
            ['env META_API_VERSION', (string) $version],
        ]);

        $forms = MetaLeadForm::query()
            ->where('meta_connection_id', $connection->id)
            ->orderBy('id')
            ->get(['id', 'form_id', 'form_name', 'is_active']);

        $this->newLine();
        $this->info('=== registered forms ===');
        if ($forms->isEmpty()) {
            $this->warn('(none)');
        } else {
            $this->table(
                ['id', 'form_id', 'form_name', 'active'],
                $forms->map(fn ($f) => [
                    $f->id,
                    $f->form_id,
                    $f->form_name,
                    $f->is_active ? 'yes' : 'no',
                ])->all()
            );
        }

        if ($token !== '') {
            $this->newLine();
            $this->info('=== live token check (/me) ===');
            $me = Http::timeout(15)->get("https://graph.facebook.com/{$version}/me", [
                'access_token' => $token,
                'fields' => 'id,name',
            ]);
            $this->line('HTTP '.$me->status().' '.$me->body());

            $this->newLine();
            $this->info('=== apps currently subscribed on this Page ===');
            if ($connection->page_id) {
                $apps = Http::timeout(15)->get(
                    "https://graph.facebook.com/{$version}/{$connection->page_id}/subscribed_apps",
                    ['access_token' => $token]
                );
                $this->line('HTTP '.$apps->status());
                foreach ($apps->json('data') ?? [] as $app) {
                    $appId = (string) ($app['id'] ?? '');
                    $mark = ($connection->app_id && $appId === (string) $connection->app_id)
                        ? ' <== matches CRM app_id'
                        : ' <== NOT CRM app_id';
                    $this->line(sprintf(
                        '  app_id=%s  name=%s  fields=%s%s',
                        $appId,
                        $app['name'] ?? '',
                        implode(',', $app['subscribed_fields'] ?? []),
                        $mark
                    ));
                }
            }
        }

        $this->newLine();
        $this->warn('How to read this:');
        $this->line('- app_id + subscribed_apps leadgen must be the SAME app (your CRM Meta app).');
        $this->line('- /me must be the Page (Shreeram Developer), not a person name.');
        $this->line('- Full secrets: php artisan meta:show-connection --reveal');

        return self::SUCCESS;
    }

    private function preview(string $value, bool $reveal): string
    {
        if ($value === '') {
            return '(empty)';
        }
        if ($reveal) {
            return $value;
        }
        if (strlen($value) <= 16) {
            return substr($value, 0, 4).'…';
        }

        return substr($value, 0, 12).'…'.substr($value, -6);
    }
}
