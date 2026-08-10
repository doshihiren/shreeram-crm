<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('meta_connections', function (Blueprint $table) {
            $table->id();
            $table->string('app_id')->nullable();
            $table->text('app_secret')->nullable(); // encrypted cast
            $table->string('page_id')->nullable()->index();
            $table->string('page_name')->nullable();
            $table->text('page_access_token')->nullable(); // encrypted cast
            $table->string('webhook_verify_token_hash')->nullable();
            $table->string('status', 32)->default('disconnected');
            $table->timestamp('connected_at')->nullable();
            $table->foreignId('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
        });

        Schema::create('meta_lead_forms', function (Blueprint $table) {
            $table->id();
            $table->foreignId('meta_connection_id')->constrained('meta_connections')->cascadeOnDelete();
            $table->string('form_id')->index();
            $table->string('form_name')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->unique(['meta_connection_id', 'form_id']);
        });

        Schema::create('meta_webhook_events', function (Blueprint $table) {
            $table->id();
            $table->string('event_id')->nullable()->index();
            $table->json('payload');
            $table->string('status', 32)->default('received')->index();
            $table->text('error_message')->nullable();
            $table->timestamps();
        });

        Schema::create('meta_lead_ingestions', function (Blueprint $table) {
            $table->id();
            $table->string('leadgen_id')->unique();
            $table->foreignId('meta_webhook_event_id')->nullable()->constrained('meta_webhook_events')->nullOnDelete();
            $table->foreignId('lead_id')->nullable()->constrained('leads')->nullOnDelete();
            $table->string('status', 32)->default('received')->index();
            $table->text('message')->nullable();
            $table->json('payload')->nullable();
            $table->timestamps();
        });

        Schema::create('audit_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('actor_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action', 64)->index();
            $table->string('entity_type', 64)->nullable()->index();
            $table->unsignedBigInteger('entity_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->json('meta')->nullable();
            $table->timestamps();
            $table->index(['created_at']);
        });

        Schema::create('app_settings', function (Blueprint $table) {
            $table->id();
            $table->string('key')->unique();
            $table->text('value')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('app_settings');
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('meta_lead_ingestions');
        Schema::dropIfExists('meta_webhook_events');
        Schema::dropIfExists('meta_lead_forms');
        Schema::dropIfExists('meta_connections');
    }
};
