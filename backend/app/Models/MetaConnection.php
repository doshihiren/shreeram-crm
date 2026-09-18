<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class MetaConnection extends Model
{
    protected $fillable = [
        'app_id',
        'app_secret',
        'page_id',
        'page_name',
        'page_access_token',
        'webhook_verify_token_hash',
        'status',
        'connected_at',
        'updated_by',
    ];

    protected function casts(): array
    {
        return [
            'app_secret' => 'encrypted',
            'page_access_token' => 'encrypted',
            'connected_at' => 'datetime',
        ];
    }

    protected $hidden = [
        'app_secret',
        'page_access_token',
        'webhook_verify_token_hash',
    ];

    public function forms(): HasMany
    {
        return $this->hasMany(MetaLeadForm::class);
    }

    public function updater(): BelongsTo
    {
        return $this->belongsTo(User::class, 'updated_by');
    }
}
