<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class SubscribeMetaPage extends Command
{
    protected $signature = 'meta:subscribe-page
        {--fields=leadgen : Comma-separated subscribed_fields}';

    protected $description = 'Subscribe the Facebook Page to leadgen webhooks for the CRM app (required for live leads)';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        $pageId = (string) ($connection?->page_id ?: '');

        if (! $token || $pageId === '') {
            $this->error('Need page_id + page access token saved in CRM Meta settings.');

            return self::FAILURE;
        }

        $version = config('services.meta.api_version', 'v21.0');
        $fields = (string) $this->option('fields');

        $crmAppId = (string) ($connection->app_id ?: config('services.meta.app_id') ?: '');
        $this->line('CRM app_id in DB: '.($crmAppId !== '' ? $crmAppId : '(missing)'));
        $this->info("POST /{$pageId}/subscribed_apps fields={$fields}");
        $this->warn('Meta installs whichever App issued this Page token. Token must be from your NEW CRM app.');

        $response = Http::asForm()->timeout(30)->post(
            "https://graph.facebook.com/{$version}/{$pageId}/subscribed_apps",
            [
                'access_token' => $token,
                'subscribed_fields' => $fields,
            ]
        );

        $this->line('HTTP '.$response->status().' '.$response->body());

        if (! $response->successful()) {
            $this->error('Subscribe failed. Token must be a Page token with pages_manage_metadata from the NEW app.');
            $this->line('Also set Webhooks on the NEW app: callback + verify token + leadgen.');

            return self::FAILURE;
        }

        $check = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$pageId}/subscribed_apps", [
            'access_token' => $token,
        ]);
        $this->newLine();
        $this->info('Current subscribed_apps:');
        $this->line('HTTP '.$check->status().' '.$check->body());

        $crmOk = false;
        foreach ($check->json('data') ?? [] as $app) {
            $appId = (string) ($app['id'] ?? '');
            $fieldsArr = $app['subscribed_fields'] ?? [];
            $line = '  app='.$appId.' name='.($app['name'] ?? '').' fields='.implode(',', is_array($fieldsArr) ? $fieldsArr : []);
            if ($crmAppId !== '' && $appId === $crmAppId) {
                $crmOk = in_array('leadgen', $fieldsArr, true);
                $line .= ' <== CRM app';
            }
            $this->line($line);
        }

        if ($crmAppId !== '' && ! $crmOk) {
            $this->error("CRM app {$crmAppId} still not subscribed.");
            $this->warn('Your saved Page token is probably from another app (e.g. Shreeram Mobile App).');
            $this->warn('Generate Page token again FROM the new CRM app in Graph API Explorer, save it in CRM Meta, re-run this.');

            return self::FAILURE;
        }

        $this->info('Done. New real form submits should POST to your CRM webhook now.');
        $this->line('Verify: php artisan meta:check-logs');

        return self::SUCCESS;
    }
}
