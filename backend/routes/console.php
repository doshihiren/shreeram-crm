<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Safety net when Meta page leadgen is subscribed to the wrong app:
// pull recent form leads every 5 minutes (idempotent — duplicates are skipped).
Schedule::command('meta:poll-leads --limit=40 --hours=48')
    ->everyFiveMinutes()
    ->withoutOverlapping(10)
    ->appendOutputTo(storage_path('logs/meta-poll.log'));
