<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

class Lead extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'public_id',
        'name',
        'mobile',
        'mobile_normalized',
        'email',
        'lead_source_id',
        'external_lead_id',
        'lead_stage_id',
        'lost_reason',
        'property_type_id',
        'property_configuration_id',
        'preferred_location',
        'purpose_id',
        'assigned_to',
        'created_by',
        'is_duplicate',
        'duplicate_of_lead_id',
        'duplicate_confidence',
        'interested_in_site_visit',
        'preferred_visit_date',
        'preferred_visit_time',
        'site_visit_status_id',
        'next_follow_up_at',
        'follow_up_status_id',
        'contacted_at',
        'closed_at',
    ];

    protected function casts(): array
    {
        return [
            'is_duplicate' => 'boolean',
            'interested_in_site_visit' => 'boolean',
            'preferred_visit_date' => 'date',
            'next_follow_up_at' => 'datetime',
            'contacted_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Lead $lead): void {
            if (empty($lead->public_id)) {
                $lead->public_id = (string) Str::uuid();
            }
            if (empty($lead->mobile_normalized) && ! empty($lead->mobile)) {
                $lead->mobile_normalized = self::normalizeMobile($lead->mobile);
            }
        });
    }

    public static function normalizeMobile(string $mobile): string
    {
        return preg_replace('/\D+/', '', $mobile) ?? '';
    }

    public function source(): BelongsTo
    {
        return $this->belongsTo(LeadSource::class, 'lead_source_id');
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(LeadStage::class, 'lead_stage_id');
    }

    public function propertyType(): BelongsTo
    {
        return $this->belongsTo(PropertyType::class);
    }

    public function propertyConfiguration(): BelongsTo
    {
        return $this->belongsTo(PropertyConfiguration::class);
    }

    public function purpose(): BelongsTo
    {
        return $this->belongsTo(LeadPurpose::class, 'purpose_id');
    }

    public function assignee(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_to');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function duplicateOf(): BelongsTo
    {
        return $this->belongsTo(Lead::class, 'duplicate_of_lead_id');
    }

    public function duplicates(): HasMany
    {
        return $this->hasMany(Lead::class, 'duplicate_of_lead_id');
    }

    public function metaAttribution(): HasOne
    {
        return $this->hasOne(LeadMetaAttribution::class);
    }

    public function activities(): HasMany
    {
        return $this->hasMany(LeadActivity::class);
    }

    public function assignments(): HasMany
    {
        return $this->hasMany(LeadAssignment::class);
    }

    public function followUps(): HasMany
    {
        return $this->hasMany(FollowUp::class);
    }

    public function siteVisits(): HasMany
    {
        return $this->hasMany(SiteVisit::class);
    }

    public function followUpStatus(): BelongsTo
    {
        return $this->belongsTo(FollowUpStatus::class);
    }

    public function siteVisitStatus(): BelongsTo
    {
        return $this->belongsTo(SiteVisitStatus::class);
    }
}
