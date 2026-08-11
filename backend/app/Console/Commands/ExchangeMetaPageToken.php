<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class ExchangeMetaPageToken extends Command
{
    protected $signature = 'meta:exchange-page-token
        {--dry-run : Show pages but do not save token}';

    protected $description = 'Convert saved USER token into a PAGE token via /me/accounts (fixes form lead pull)';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        if (! $connection) {
            $this->error('No meta_connections row found.');

            return self::FAILURE;
        }

        $token = $connection->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            $this->error('No token saved. Paste a User token (with pages_show_list) in CRM Meta settings first.');

            return self::FAILURE;
        }

        $version = config('services.meta.api_version', 'v21.0');
        $pageId = (string) ($connection->page_id ?: '657023730834410');

        $me = Http::timeout(20)->get("https://graph.facebook.com/{$version}/me", [
            'access_token' => $token,
            'fields' => 'id,name',
        ]);
        $this->info('Current token /me: HTTP '.$me->status().' '.$me->body());

        if ($me->successful() && (string) $me->json('id') === $pageId) {
            $this->info('Already a Page token for '.$pageId.'. Nothing to exchange.');

            return self::SUCCESS;
        }

        $this->info('Fetching /me/accounts …');
        $accounts = Http::timeout(30)->get("https://graph.facebook.com/{$version}/me/accounts", [
            'access_token' => $token,
            'fields' => 'id,name,access_token,tasks',
            'limit' => 100,
        ]);

        if (! $accounts->successful()) {
            $this->error('HTTP '.$accounts->status().' '.$accounts->body());
            $this->warn('Your USER token needs pages_show_list (and page access). Re-generate User token in Graph API Explorer with:');
            $this->line('  pages_show_list, pages_read_engagement, pages_manage_metadata, pages_manage_ads, leads_retrieval, ads_management');
            $this->line('Then paste that User token in CRM Meta → Save, and re-run this command.');

            return self::FAILURE;
        }

        $pages = $accounts->json('data') ?? [];
        if ($pages === []) {
            $this->error('No Pages returned. Your Facebook user has no manageable Pages for this app, or permissions were not granted.');

            return self::FAILURE;
        }

        $this->table(
            ['id', 'name', 'tasks'],
            collect($pages)->map(fn ($p) => [
                $p['id'] ?? '',
                $p['name'] ?? '',
                implode(',', $p['tasks'] ?? []),
            ])->all()
        );

        $match = collect($pages)->first(fn ($p) => (string) ($p['id'] ?? '') === $pageId);
        if (! $match) {
            $this->error("Configured page_id {$pageId} not in /me/accounts.");
            $this->warn('Either fix page_id in CRM Meta settings, or assign yourself Advertise/Admin on Shreeram Developer.');

            return self::FAILURE;
        }

        $pageToken = (string) ($match['access_token'] ?? '');
        if ($pageToken === '') {
            $this->error('Page row has no access_token.');

            return self::FAILURE;
        }

        // Verify page token identity
        $pageMe = Http::timeout(20)->get("https://graph.facebook.com/{$version}/me", [
            'access_token' => $pageToken,
            'fields' => 'id,name',
        ]);
        $this->info('Page token /me: HTTP '.$pageMe->status().' '.$pageMe->body());

        if ($this->option('dry-run')) {
            $this->warn('Dry run — token NOT saved.');

            return self::SUCCESS;
        }

        $connection->page_access_token = $pageToken;
        if (! empty($match['name'])) {
            $connection->page_name = $match['name'];
        }
        $connection->page_id = $pageId;
        $connection->status = 'connected';
        $connection->connected_at = now();
        $connection->save();

        $this->info('Saved PAGE access token for '.$pageId.' ('.($match['name'] ?? '').').');
        $this->line('Next:');
        $this->line('  php artisan meta:diagnose --form=1301528194957429 --lead=1785748245894113');
        $this->line('  php artisan meta:import-leads --form=1301528194957429 --limit=100');

        return self::SUCCESS;
    }
}
