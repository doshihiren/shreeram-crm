<?php

namespace Tests\Feature;

use App\Enums\UserRole;
use App\Models\LeadSource;
use App\Models\LeadStage;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AuthAndDashboardTest extends TestCase
{
    use RefreshDatabase;

    public function test_login_returns_token_and_role_permissions(): void
    {
        $this->seed(DatabaseSeeder::class);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'owner@shreeram.local',
            'password' => 'ChangeMeOwner1!',
        ]);

        $response->assertOk()
            ->assertJsonPath('user.role', UserRole::Owner->value)
            ->assertJsonStructure(['token', 'user' => ['permissions']]);
    }

    public function test_dashboard_summary_is_database_backed(): void
    {
        $this->seed(DatabaseSeeder::class);
        $owner = User::query()->where('email', 'owner@shreeram.local')->firstOrFail();
        Sanctum::actingAs($owner);

        $response = $this->getJson('/api/v1/dashboard/summary');
        $response->assertOk()
            ->assertJsonPath('data.total_leads', 0)
            ->assertJsonStructure([
                'data' => [
                    'total_leads',
                    'stages',
                    'today_new_leads',
                    'today_follow_ups',
                    'today_site_visits',
                    'overdue_follow_ups',
                ],
            ]);

        $this->assertNotEmpty($response->json('data.stages'));
    }

    public function test_sales_cannot_manage_meta_connection(): void
    {
        $this->seed(DatabaseSeeder::class);
        $sales = User::query()->where('email', 'sales@shreeram.local')->firstOrFail();
        Sanctum::actingAs($sales);

        $this->getJson('/api/v1/meta/connection')->assertForbidden();
    }

    public function test_lead_create_and_duplicate_mobile_linking(): void
    {
        $this->seed(DatabaseSeeder::class);
        $owner = User::query()->where('email', 'owner@shreeram.local')->firstOrFail();
        Sanctum::actingAs($owner);

        $sourceId = LeadSource::query()->where('code', 'OTHER')->value('id');

        $first = $this->postJson('/api/v1/leads', [
            'name' => 'Ravi',
            'mobile' => '98765-43210',
            'lead_source_id' => $sourceId,
        ]);
        $first->assertCreated()->assertJsonPath('duplicate', false);

        $second = $this->postJson('/api/v1/leads', [
            'name' => 'Ravi Kumar',
            'mobile' => '9876543210',
            'lead_source_id' => $sourceId,
        ]);
        $second->assertCreated()
            ->assertJsonPath('duplicate', true)
            ->assertJsonPath('data.is_duplicate', true);
    }

    public function test_meta_webhook_verify(): void
    {
        config(['services.meta.webhook_verify_token' => 'test-verify-token']);

        $response = $this->get('/api/v1/meta/webhook?hub.mode=subscribe&hub.verify_token=test-verify-token&hub.challenge=12345');
        $response->assertOk();
        $this->assertSame('12345', $response->getContent());
    }
}
