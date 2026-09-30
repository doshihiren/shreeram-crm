<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SiteVisitStatus extends Model
{
    protected $fillable = ['code', 'name', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }
}
