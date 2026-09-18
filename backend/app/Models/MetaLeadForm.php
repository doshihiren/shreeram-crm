<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MetaLeadForm extends Model
{
    protected $fillable = [
        'meta_connection_id',
        'form_id',
        'form_name',
        'is_active',
    ];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function connection(): BelongsTo
    {
        return $this->belongsTo(MetaConnection::class, 'meta_connection_id');
    }
}
