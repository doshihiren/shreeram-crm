<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('lead_meta_attributions', function (Blueprint $table) {
            $table->string('platform', 16)->nullable()->after('leadgen_id');
            $table->boolean('is_organic')->nullable()->after('platform');
        });
    }

    public function down(): void
    {
        Schema::table('lead_meta_attributions', function (Blueprint $table) {
            $table->dropColumn(['platform', 'is_organic']);
        });
    }
};
