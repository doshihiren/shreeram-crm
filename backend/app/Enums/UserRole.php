<?php

namespace App\Enums;

enum UserRole: string
{
    case Owner = 'OWNER';
    case Admin = 'ADMIN';
    case SalesPerson = 'SALES_PERSON';

    public function label(): string
    {
        return match ($this) {
            self::Owner => 'Owner',
            self::Admin => 'Admin',
            self::SalesPerson => 'Sales Person',
        };
    }

    public function isStaffAdmin(): bool
    {
        return $this === self::Owner || $this === self::Admin;
    }

    /** @return list<string> */
    public function permissions(): array
    {
        return match ($this) {
            self::Owner => [
                'dashboard.view_all',
                'leads.view_all',
                'leads.manage',
                'leads.assign',
                'users.manage',
                'users.manage_roles',
                'stages.manage',
                'sources.manage',
                'meta.manage',
                'meta.view_attribution',
                'audit.view',
                'settings.manage',
            ],
            self::Admin => [
                'dashboard.view_all',
                'leads.view_all',
                'leads.manage',
                'leads.assign',
                'users.manage',
                'stages.manage',
                'sources.manage',
                'meta.manage',
                'meta.view_attribution',
                'audit.view_limited',
            ],
            self::SalesPerson => [
                'dashboard.view_own',
                'leads.view_own',
                'leads.update_own',
                'leads.remark',
                'follow_ups.manage_own',
                'site_visits.manage_own',
            ],
        };
    }
}
