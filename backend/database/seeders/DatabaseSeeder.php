<?php

namespace Database\Seeders;

use App\Enums\UserRole;
use App\Models\FollowUpStatus;
use App\Models\LeadPurpose;
use App\Models\LeadSource;
use App\Models\LeadStage;
use App\Models\PropertyConfiguration;
use App\Models\PropertyType;
use App\Models\SiteVisitStatus;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->seedLookups();
        $this->seedUsers();
    }

    private function seedLookups(): void
    {
        $sources = [
            ['code' => 'META', 'name' => 'Meta Lead Ads', 'sort_order' => 1],
            ['code' => 'WEBSITE', 'name' => 'Website', 'sort_order' => 2],
            ['code' => 'GOOGLE', 'name' => 'Google Ads', 'sort_order' => 3],
            ['code' => 'OTHER', 'name' => 'Other', 'sort_order' => 99],
        ];
        foreach ($sources as $row) {
            LeadSource::query()->updateOrCreate(['code' => $row['code']], $row + ['is_active' => true]);
        }

        $stages = [
            ['code' => 'NEW_LEAD', 'name' => 'New Lead', 'sort_order' => 1, 'color' => '#2391CB'],
            ['code' => 'CALL_DONE', 'name' => 'Call Done', 'sort_order' => 2, 'color' => '#7C5CFC'],
            ['code' => 'CALL_NOTE_RECEIVED', 'name' => 'Call Note received', 'sort_order' => 3, 'color' => '#EF7D3B'],
            ['code' => 'SITE_VISIT_BOOKED', 'name' => 'Site Visit Booked', 'sort_order' => 4, 'color' => '#B08020'],
            ['code' => 'SITE_VISIT_DONE', 'name' => 'Site Visit Done', 'sort_order' => 5, 'color' => '#0F9F8A'],
            ['code' => 'UNIT_BOOKED', 'name' => 'Unit Booked', 'sort_order' => 6, 'color' => '#0E7A2F', 'is_terminal' => true],
            ['code' => 'LOST', 'name' => 'Lost', 'sort_order' => 100, 'color' => '#D62D27', 'is_lost' => true, 'is_terminal' => true],
        ];
        foreach ($stages as $row) {
            LeadStage::query()->updateOrCreate(
                ['code' => $row['code']],
                $row + ['is_active' => true, 'is_lost' => $row['is_lost'] ?? false, 'is_terminal' => $row['is_terminal'] ?? false]
            );
        }
        // Keep legacy codes inactive if present from older installs.
        LeadStage::query()->whereNotIn('code', collect($stages)->pluck('code'))->update(['is_active' => false]);

        foreach ([
            ['code' => 'APARTMENT', 'name' => 'Apartment', 'sort_order' => 1],
            ['code' => 'VILLA', 'name' => 'Villa', 'sort_order' => 2],
            ['code' => 'PLOT', 'name' => 'Plot', 'sort_order' => 3],
            ['code' => 'SHOP', 'name' => 'Shop', 'sort_order' => 4],
            ['code' => 'OFFICE', 'name' => 'Office', 'sort_order' => 5],
            ['code' => 'OTHER', 'name' => 'Other', 'sort_order' => 99],
        ] as $row) {
            PropertyType::query()->updateOrCreate(['code' => $row['code']], $row + ['is_active' => true]);
        }

        foreach ([
            ['code' => '1BHK', 'name' => '1 BHK', 'sort_order' => 1],
            ['code' => '2BHK', 'name' => '2 BHK', 'sort_order' => 2],
            ['code' => '3BHK', 'name' => '3 BHK', 'sort_order' => 3],
            ['code' => '4BHK', 'name' => '4 BHK', 'sort_order' => 4],
            ['code' => 'OTHER', 'name' => 'Other', 'sort_order' => 99],
        ] as $row) {
            PropertyConfiguration::query()->updateOrCreate(['code' => $row['code']], $row + ['is_active' => true]);
        }

        foreach ([
            ['code' => 'RESIDENTIAL', 'name' => 'Residential', 'sort_order' => 1],
            ['code' => 'INVESTMENT', 'name' => 'Investment', 'sort_order' => 2],
            ['code' => 'COMMERCIAL', 'name' => 'Commercial', 'sort_order' => 3],
        ] as $row) {
            LeadPurpose::query()->updateOrCreate(['code' => $row['code']], $row + ['is_active' => true]);
        }

        foreach ([
            ['code' => 'PLANNED', 'name' => 'Planned', 'sort_order' => 1],
            ['code' => 'DONE', 'name' => 'Done', 'sort_order' => 2],
            ['code' => 'CANCELLED', 'name' => 'Cancelled', 'sort_order' => 3],
            ['code' => 'NO_SHOW', 'name' => 'No Show', 'sort_order' => 4],
        ] as $row) {
            SiteVisitStatus::query()->updateOrCreate(['code' => $row['code']], $row + ['is_active' => true]);
        }

        foreach ([
            ['code' => 'PENDING', 'name' => 'Pending', 'sort_order' => 1],
            ['code' => 'DONE', 'name' => 'Done', 'sort_order' => 2],
            ['code' => 'SKIPPED', 'name' => 'Skipped', 'sort_order' => 3],
        ] as $row) {
            FollowUpStatus::query()->updateOrCreate(['code' => $row['code']], $row + ['is_active' => true]);
        }
    }

    private function seedUsers(): void
    {
        User::query()->updateOrCreate(
            ['email' => 'owner@shreeram.local'],
            [
                'name' => 'Owner',
                'mobile' => '9000000001',
                'password' => Hash::make('ChangeMeOwner1!'),
                'role' => UserRole::Owner,
                'is_active' => true,
            ]
        );

        User::query()->updateOrCreate(
            ['email' => 'admin@shreeram.local'],
            [
                'name' => 'Admin',
                'mobile' => '9000000002',
                'password' => Hash::make('ChangeMeAdmin1!'),
                'role' => UserRole::Admin,
                'is_active' => true,
            ]
        );

        User::query()->updateOrCreate(
            ['email' => 'sales@shreeram.local'],
            [
                'name' => 'Sales Person',
                'mobile' => '9000000003',
                'password' => Hash::make('ChangeMeSales1!'),
                'role' => UserRole::SalesPerson,
                'is_active' => true,
            ]
        );
    }
}
