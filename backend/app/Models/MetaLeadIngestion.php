<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MetaLeadIngestion extends Model
{
    protected $fillable = [
        'leadgen_id',
        'meta_webhook_event_id',
        'lead_id',
        'status',
        'message',
        'payload',
    ];

    protected function casts(): array
    {
        return ['payload' => 'array'];
    }

    public function lead(): BelongsTo
    {
        return $this->belongsTo(Lead::class);
    }

    public function webhookEvent(): BelongsTo
    {
        return $this->belongsTo(MetaWebhookEvent::class, 'meta_webhook_event_id');
    }
}
