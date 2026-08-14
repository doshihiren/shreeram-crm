<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class InspectMetaLead extends Command
{
    protected $signature = 'meta:inspect-lead
        {leadgen_id : Meta lead id (without l: prefix)}
        {--save-page : If Graph returns a page_id, save it on meta_connections}';

    protected $description = 'Inspect a real Meta lead to discover page_id/form_id/ad ids (works with current User token)';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            $this->error('No token saved in CRM Meta settings.');

            return self::FAILURE;
        }

        $leadId = preg_replace('/^l:/i', '', trim((string) $this->argument('leadgen_id')));
        $version = config('services.meta.api_version', 'v21.0');

        $this->info("Fetching lead {$leadId} …");
        $lead = Http::timeout(30)->get("https://graph.facebook.com/{$version}/{$leadId}", [
            'access_token' => $token,
            'fields' => 'id,created_time,ad_id,adset_id,campaign_id,form_id,field_data,is_organic',
        ]);
        $this->line('Lead HTTP '.$lead->status());
        $this->line($lead->body());

        if (! $lead->successful()) {
            return self::FAILURE;
        }

        $formId = (string) ($lead->json('form_id') ?? '');
        $adId = (string) ($lead->json('ad_id') ?? '');
        $discoveredPageId = null;

        if ($formId !== '') {
            $this->newLine();
            $this->info("Fetching form {$formId} …");
            $form = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$formId}", [
                'access_token' => $token,
                'fields' => 'id,name,status,page_id,leads_count',
            ]);
            $this->line('Form HTTP '.$form->status().' '.$form->body());
            if ($form->successful()) {
                $discoveredPageId = (string) ($form->json('page_id') ?? '') ?: null;
            }
        }

        if ($adId !== '') {
            $this->newLine();
            $this->info("Fetching ad {$adId} …");
            $ad = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$adId}", [
                'access_token' => $token,
                'fields' => 'id,name,status,account_id,campaign_id,adset_id',
            ]);
            $this->line('Ad HTTP '.$ad->status().' '.$ad->body());
        }

        $this->newLine();
        $this->info('Listing ALL pages from /me/accounts (with paging) …');
        $pages = $this->allAccounts($token, $version);
        foreach ($pages as $p) {
            $name = (string) ($p['name'] ?? '');
            $mark = stripos($name, 'shree') !== false || stripos($name, 'ram') !== false ? ' <== possible match' : '';
            $this->line('  '.($p['id'] ?? '').'  '.$name.$mark);
        }
        $this->info('Total pages visible to this token: '.count($pages));

        $configured = (string) ($connection?->page_id ?? '');
        $this->newLine();
        $this->table(['Key', 'Value'], [
            ['configured_page_id', $configured !== '' ? $configured : '(none)'],
            ['form_page_id', $discoveredPageId ?: '(unknown — no permission)'],
            ['form_id', $formId !== '' ? $formId : '(none)'],
            ['ad_id', $adId !== '' ? $adId : '(none)'],
            ['shreeram_in_accounts', collect($pages)->contains(fn ($p) => (string) ($p['id'] ?? '') === $configured) ? 'YES' : 'NO'],
        ]);

        if ($discoveredPageId && $this->option('save-page') && $connection) {
            $connection->page_id = $discoveredPageId;
            $connection->save();
            $this->info("Saved page_id={$discoveredPageId} on meta_connections.");
        }

        $this->newLine();
        $this->warn('If Shreeram is still missing from /me/accounts, use a Business Manager System User token (see docs/META_PAGE_ACCESS.md).');
        $this->line('Meanwhile import works by lead id:');
        $this->line("  php artisan meta:import-leads {$leadId} --form=".($formId !== '' ? $formId : '1301528194957429'));

        return self::SUCCESS;
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function allAccounts(string $token, string $version): array
    {
        $url = "https://graph.facebook.com/{$version}/me/accounts";
        $params = [
            'access_token' => $token,
            'fields' => 'id,name,access_token,tasks',
            'limit' => 100,
        ];
        $out = [];
        for ($i = 0; $i < 20; $i++) {
            $res = Http::timeout(30)->get($url, $params);
            if (! $res->successful()) {
                $this->error('accounts HTTP '.$res->status().' '.$res->body());
                break;
            }
            foreach ($res->json('data') ?? [] as $row) {
                $out[] = $row;
            }
            $next = $res->json('paging.next');
            if (! is_string($next) || $next === '') {
                break;
            }
            $url = $next;
            $params = [];
        }

        return $out;
    }
}
