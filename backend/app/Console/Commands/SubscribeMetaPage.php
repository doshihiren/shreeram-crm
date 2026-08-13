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

        $this->info("POST /{$pageId}/subscribed_apps fields={$fields}");
        $response = Http::asForm()->timeout(30)->post(
            "https://graph.facebook.com/{$version}/{$pageId}/subscribed_apps",
            [
                'access_token' => $token,
                'subscribed_fields' => $fields,
            ]
        );

        $this->line('HTTP '.$response->status().' '.$response->body());

        if (! $response->successful()) {
            $this->error('Subscribe failed. Token must be a Page token with pages_manage_metadata.');
            $this->line('Also confirm the NEW Meta App is installed on the Page and webhook callback URL is set.');

            return self::FAILURE;
        }

        $check = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$pageId}/subscribed_apps", [
            'access_token' => $token,
        ]);
        $this->newLine();
        $this->info('Current subscribed_apps:');
        $this->line('HTTP '.$check->status().' '.$check->body());

        $this->info('Done. New real form submits should POST to your webhook now.');
        $this->line('Verify: php artisan meta:check-logs');

        return self::SUCCESS;
    }
}
