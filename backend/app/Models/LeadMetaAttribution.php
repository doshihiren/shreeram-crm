<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LeadMetaAttribution extends Model
{
    protected $fillable = [
        'lead_id',
        'page_id',
        'page_name',
        'form_id',
        'form_name',
        'campaign_id',
        'campaign_name',
        'adset_id',
        'adset_name',
        'ad_id',
        'ad_name',
        'leadgen_id',
        'raw_field_data',
    ];

    protected function casts(): array
    {
        return [
            'raw_field_data' => 'array',
        ];
    }

    public function lead(): BelongsTo
    {
        return $this->belongsTo(Lead::class);
    }
}
