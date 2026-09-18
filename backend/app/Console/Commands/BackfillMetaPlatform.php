<?php

namespace App\Console\Commands;

use App\Models\LeadMetaAttribution;
use App\Models\MetaConnection;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;

class BackfillMetaPlatform extends Command
{
    protected $signature = 'meta:backfill-platform {--limit=200 : Max attributions to refresh}';

    protected $description = 'Fetch platform (fb/ig) + refresh form answers for existing Meta leads';

    public function handle(): int
    {
        $connection = MetaConnection::query()->latest('id')->first();
        $token = $connection?->page_access_token ?: config('services.meta.page_access_token');
        if (! $token) {
            $this->error('No page token saved.');

            return self::FAILURE;
        }

        $version = config('services.meta.api_version', 'v21.0');
        $rows = LeadMetaAttribution::query()
            ->whereNotNull('leadgen_id')
            ->where(function ($q) {
                $q->whereNull('platform')->orWhereNull('raw_field_data');
            })
            ->latest('id')
            ->limit((int) $this->option('limit'))
            ->get();

        $this->info('Refreshing '.$rows->count().' attribution row(s)…');
        $ok = 0;
        foreach ($rows as $row) {
            $leadgenId = (string) $row->leadgen_id;
            if ($leadgenId === '' || str_starts_with($leadgenId, 'sample-') || preg_match('/^4+$/', $leadgenId)) {
                continue;
            }
            $res = Http::timeout(20)->get("https://graph.facebook.com/{$version}/{$leadgenId}", [
                'access_token' => $token,
                'fields' => 'id,platform,is_organic,field_data,form_id,ad_id,adset_id,campaign_id',
            ]);
            if (! $res->successful()) {
                $this->line("  fail {$leadgenId} HTTP ".$res->status());
                continue;
            }
            $json = $res->json() ?? [];
            $platform = strtolower((string) ($json['platform'] ?? ''));
            $platform = match ($platform) {
                'facebook' => 'fb',
                'instagram' => 'ig',
                default => $platform !== '' ? $platform : null,
            };
            $row->update([
                'platform' => $platform,
                'is_organic' => array_key_exists('is_organic', $json) ? (bool) $json['is_organic'] : $row->is_organic,
                'raw_field_data' => $json['field_data'] ?? $row->raw_field_data,
                'form_id' => $json['form_id'] ?? $row->form_id,
                'ad_id' => $json['ad_id'] ?? $row->ad_id,
                'adset_id' => $json['adset_id'] ?? $row->adset_id,
                'campaign_id' => $json['campaign_id'] ?? $row->campaign_id,
            ]);
            $ok++;
            $this->line("  ok {$leadgenId} platform=".($platform ?? 'null'));
        }
        $this->info("Done. updated={$ok}");

        return self::SUCCESS;
    }
}
