<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SiteVisit extends Model
{
    protected $fillable = [
        'lead_id',
        'assigned_to',
        'created_by',
        'site_visit_status_id',
        'scheduled_at',
        'completed_at',
        'remarks',
    ];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'completed_at' => 'datetime',
        ];
    }

    public function lead(): BelongsTo
    {
        return $this->belongsTo(Lead::class);
    }

    public function status(): BelongsTo
    {
        return $this->belongsTo(SiteVisitStatus::class, 'site_visit_status_id');
    }

    public function assignee(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_to');
    }
}
