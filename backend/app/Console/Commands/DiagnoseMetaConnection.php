<?php

namespace App\Console\Commands;

use App\Models\MetaConnection;
use App\Models\MetaLeadForm;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class DiagnoseMetaConnection extends Command
{
    protected $signature = 'meta:diagnose
        {--lead= : Optional real leadgen ID to test Graph fetch}
        {--form=1301528194957429 : Form ID to test}';

    protected $description = 'Diagnose Meta Page token / form permissions for lead import';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        if (! $connection) {
            $this->error('No meta_connections row. Save Meta settings in the CRM UI first.');

            return self::FAILURE;
        }

        $token = $connection->page_access_token ?: config('services.meta.page_access_token');
        $version = config('services.meta.api_version', 'v21.0');
        $pageId = (string) ($connection->page_id ?: '');
        $formId = (string) $this->option('form');

        $this->table(['Field', 'Value'], [
            ['connection_id', (string) $connection->id],
            ['page_id', $pageId !== '' ? $pageId : '(missing)'],
            ['page_name', (string) ($connection->page_name ?: '')],
            ['status', (string) $connection->status],
            ['has_page_token', $token ? 'yes' : 'NO'],
            ['token_prefix', $token ? substr($token, 0, 12).'…' : ''],
            ['registered_forms', MetaLeadForm::query()->pluck('form_id')->implode(', ') ?: '(none)'],
        ]);

        if (! $token) {
            $this->error('Save a token in CRM Meta settings, then re-run.');

            return self::FAILURE;
        }

        $this->newLine();
        $this->info('1) Token identity (/me)');
        $me = Http::timeout(20)->get("https://graph.facebook.com/{$version}/me", [
            'access_token' => $token,
            'fields' => 'id,name',
        ]);
        $this->line('HTTP '.$me->status().' '.$me->body());

        $meId = (string) ($me->json('id') ?? '');
        $isPageToken = $pageId !== '' && $meId === $pageId;
        if ($me->successful() && ! $isPageToken) {
            $this->error('THIS IS A USER TOKEN ('.($me->json('name') ?? $meId).'), NOT A PAGE TOKEN.');
            $this->warn('Form bulk pull needs a Page token. Run:');
            $this->line('  php artisan meta:exchange-page-token');
            $this->line('If that fails, regenerate User token with pages_show_list + pages_manage_ads + leads_retrieval, save it in CRM, then exchange again.');
        } elseif ($isPageToken) {
            $this->info('OK: token identity is the Page.');
        }

        if ($pageId !== '') {
            $this->newLine();
            $this->info("2) Page leadgen forms (/{$pageId}/leadgen_forms)");
            $forms = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$pageId}/leadgen_forms", [
                'access_token' => $token,
                'fields' => 'id,name,status,leads_count',
                'limit' => 50,
            ]);
            $this->line('HTTP '.$forms->status());
            if ($forms->successful()) {
                foreach ($forms->json('data') ?? [] as $f) {
                    $mark = ((string) ($f['id'] ?? '')) === $formId ? ' <== configured form' : '';
                    $this->line(sprintf(
                        '  form=%s name=%s status=%s leads=%s%s',
                        $f['id'] ?? '',
                        $f['name'] ?? '',
                        $f['status'] ?? '',
                        $f['leads_count'] ?? '?',
                        $mark
                    ));
                }
            } else {
                $this->line($forms->body());
            }
        }

        $this->newLine();
        $this->info("3) Direct form leads (/{$formId}/leads)");
        $leads = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$formId}/leads", [
            'access_token' => $token,
            'limit' => 1,
            'fields' => 'id,created_time',
        ]);
        $this->line('HTTP '.$leads->status().' '.$leads->body());

        $leadId = $this->option('lead') ?: '1785748245894113';
        $this->newLine();
        $this->info("4) Single lead fetch (/{$leadId})");
        $one = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$leadId}", [
            'access_token' => $token,
            'fields' => 'id,created_time,field_data',
        ]);
        $this->line('HTTP '.$one->status().' '.substr($one->body(), 0, 500));

        $this->newLine();
        if (! $isPageToken) {
            $this->warn('Next step: php artisan meta:exchange-page-token');

            return self::FAILURE;
        }

        if (! $leads->successful()) {
            $this->warn('Page token still cannot list form leads. Add pages_manage_ads + leads_retrieval, re-exchange, retry.');

            return self::FAILURE;
        }

        $this->info('Token looks good. Run: php artisan meta:import-leads --form='.$formId.' --limit=100');

        return self::SUCCESS;
    }
}
