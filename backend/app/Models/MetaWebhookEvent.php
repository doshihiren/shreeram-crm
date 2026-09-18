<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MetaWebhookEvent extends Model
{
    protected $fillable = [
        'event_id',
        'payload',
        'status',
        'error_message',
    ];

    protected function casts(): array
    {
        return ['payload' => 'array'];
    }
}
