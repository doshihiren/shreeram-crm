<?php

namespace App\Console\Commands;

use App\Models\Lead;
use App\Models\LeadStage;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SyncLeadPipeline extends Command
{
    protected $signature = 'stages:sync-pipeline {--force : Run without confirmation}';

    protected $description = 'Sync lead stages to sales pipeline: New Lead → … → Unit Booked / Lost';

    public function handle(): int
    {
        if (! $this->option('force') && ! $this->confirm('Remap lead stages to the new pipeline?', true)) {
            return self::SUCCESS;
        }

        $pipeline = [
            ['code' => 'NEW_LEAD', 'name' => 'New Lead', 'sort_order' => 1, 'color' => '#2391CB'],
            ['code' => 'CALL_NOT_RECEIVED', 'name' => 'Call Not Received', 'sort_order' => 2, 'color' => '#9AA5B1'],
            ['code' => 'CALL_DONE', 'name' => 'Call Done', 'sort_order' => 3, 'color' => '#7C5CFC'],
            ['code' => 'CALL_NOTE_RECEIVED', 'name' => 'Call Note received', 'sort_order' => 4, 'color' => '#EF7D3B'],
            ['code' => 'SITE_VISIT_BOOKED', 'name' => 'Site Visit Booked', 'sort_order' => 5, 'color' => '#B08020'],
            ['code' => 'SITE_VISIT_DONE', 'name' => 'Site Visit Done', 'sort_order' => 6, 'color' => '#0F9F8A'],
            ['code' => 'UNIT_BOOKED', 'name' => 'Unit Booked', 'sort_order' => 7, 'color' => '#0E7A2F', 'is_terminal' => true],
            ['code' => 'LOST', 'name' => 'Lost', 'sort_order' => 100, 'color' => '#D62D27', 'is_lost' => true, 'is_terminal' => true],
        ];

        DB::transaction(function () use ($pipeline) {
            foreach ($pipeline as $row) {
                LeadStage::query()->updateOrCreate(
                    ['code' => $row['code']],
                    [
                        'name' => $row['name'],
                        'sort_order' => $row['sort_order'],
                        'color' => $row['color'] ?? null,
                        'is_active' => true,
                        'is_lost' => $row['is_lost'] ?? false,
                        'is_terminal' => $row['is_terminal'] ?? false,
                    ]
                );
            }

            $map = [
                'CONTACTED' => 'CALL_DONE',
                'INTERESTED' => 'CALL_NOTE_RECEIVED',
                'SITE_VISIT_PLANNED' => 'SITE_VISIT_BOOKED',
                'FOLLOW_UP' => 'CALL_NOTE_RECEIVED',
                'NEGOTIATION' => 'SITE_VISIT_BOOKED',
                'BOOKED' => 'UNIT_BOOKED',
                'CLOSED' => 'UNIT_BOOKED',
            ];

            foreach ($map as $from => $to) {
                $fromId = LeadStage::query()->where('code', $from)->value('id');
                $toId = LeadStage::query()->where('code', $to)->value('id');
                if (! $fromId || ! $toId) {
                    continue;
                }
                $n = Lead::withTrashed()->where('lead_stage_id', $fromId)->update(['lead_stage_id' => $toId]);
                $this->line("Remapped {$from} → {$to}: {$n} leads");
            }

            $keep = collect($pipeline)->pluck('code')->all();
            LeadStage::query()->whereNotIn('code', $keep)->update(['is_active' => false]);
        });

        $this->info('Pipeline synced. Active stages:');
        foreach (LeadStage::query()->where('is_active', true)->orderBy('sort_order')->get() as $s) {
            $this->line("  {$s->sort_order}. {$s->code} — {$s->name}");
        }

        return self::SUCCESS;
    }
}
