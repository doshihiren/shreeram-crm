<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('leads', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->string('name');
            $table->string('mobile', 32)->index();
            $table->string('mobile_normalized', 32)->index();
            $table->string('email')->nullable()->index();

            $table->foreignId('lead_source_id')->constrained('lead_sources');
            $table->string('external_lead_id')->nullable();
            $table->foreignId('lead_stage_id')->constrained('lead_stages');
            $table->string('lost_reason')->nullable();

            $table->foreignId('property_type_id')->nullable()->constrained('property_types')->nullOnDelete();
            $table->foreignId('property_configuration_id')->nullable()->constrained('property_configurations')->nullOnDelete();
            $table->string('preferred_location')->nullable();
            $table->foreignId('purpose_id')->nullable()->constrained('lead_purposes')->nullOnDelete();

            $table->foreignId('assigned_to')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();

            $table->boolean('is_duplicate')->default(false)->index();
            $table->foreignId('duplicate_of_lead_id')->nullable()->constrained('leads')->nullOnDelete();
            $table->string('duplicate_confidence', 32)->nullable();

            $table->boolean('interested_in_site_visit')->default(false);
            $table->date('preferred_visit_date')->nullable();
            $table->time('preferred_visit_time')->nullable();
            $table->foreignId('site_visit_status_id')->nullable()->constrained('site_visit_statuses')->nullOnDelete();

            $table->timestamp('next_follow_up_at')->nullable()->index();
            $table->foreignId('follow_up_status_id')->nullable()->constrained('follow_up_statuses')->nullOnDelete();

            $table->timestamp('contacted_at')->nullable();
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['lead_source_id', 'external_lead_id']);
            $table->index(['lead_stage_id', 'created_at']);
            $table->index(['assigned_to', 'lead_stage_id']);
        });

        Schema::create('lead_meta_attributions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lead_id')->unique()->constrained('leads')->cascadeOnDelete();
            $table->string('page_id')->nullable();
            $table->string('page_name')->nullable();
            $table->string('form_id')->nullable();
            $table->string('form_name')->nullable();
            $table->string('campaign_id')->nullable();
            $table->string('campaign_name')->nullable();
            $table->string('adset_id')->nullable();
            $table->string('adset_name')->nullable();
            $table->string('ad_id')->nullable();
            $table->string('ad_name')->nullable();
            $table->string('leadgen_id')->nullable()->index();
            $table->json('raw_field_data')->nullable();
            $table->timestamps();
        });

        Schema::create('lead_assignments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lead_id')->constrained('leads')->cascadeOnDelete();
            $table->foreignId('assigned_to')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('assigned_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reason')->nullable();
            $table->timestamps();
            $table->index(['lead_id', 'created_at']);
        });

        Schema::create('lead_activities', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lead_id')->constrained('leads')->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('type', 64)->index();
            $table->text('body')->nullable();
            $table->json('meta')->nullable();
            $table->timestamps();
            $table->index(['lead_id', 'created_at']);
        });

        Schema::create('follow_ups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lead_id')->constrained('leads')->cascadeOnDelete();
            $table->foreignId('assigned_to')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('follow_up_status_id')->constrained('follow_up_statuses');
            $table->timestamp('due_at')->index();
            $table->timestamp('completed_at')->nullable();
            $table->text('remarks')->nullable();
            $table->timestamps();
            $table->index(['due_at', 'follow_up_status_id']);
        });

        Schema::create('site_visits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('lead_id')->constrained('leads')->cascadeOnDelete();
            $table->foreignId('assigned_to')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('site_visit_status_id')->constrained('site_visit_statuses');
            $table->timestamp('scheduled_at')->nullable()->index();
            $table->timestamp('completed_at')->nullable();
            $table->text('remarks')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('site_visits');
        Schema::dropIfExists('follow_ups');
        Schema::dropIfExists('lead_activities');
        Schema::dropIfExists('lead_assignments');
        Schema::dropIfExists('lead_meta_attributions');
        Schema::dropIfExists('leads');
    }
};
