<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class LeadStage extends Model
{
    protected $fillable = [
        'code', 'name', 'sort_order', 'is_lost', 'is_terminal', 'is_active', 'color',
    ];

    protected function casts(): array
    {
        return [
            'is_lost' => 'boolean',
            'is_terminal' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function leads(): HasMany
    {
        return $this->hasMany(Lead::class);
    }
}
