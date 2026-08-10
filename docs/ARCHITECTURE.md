# ShreeRam CRM — Technical Architecture & Implementation Plan

**Project:** Real Estate Lead Management CRM (`shreeram-crm`)  
**Status:** Architecture only — awaiting approval before implementation  
**V1 scope:** Lead lifecycle management (no financial amounts)  
**Platforms:** Android, iOS, Web via Flutter + shared Laravel REST API + MySQL

---

## Table of Contents

1. [Recommended Architecture](#1-recommended-architecture)
2. [Project Folder Structure](#2-project-folder-structure)
3. [Flutter Architecture](#3-flutter-architecture)
4. [Laravel Architecture](#4-laravel-architecture)
5. [Database Tables](#5-database-tables)
6. [Database Relationships](#6-database-relationships)
7. [API Structure](#7-api-structure)
8. [Authentication Architecture](#8-authentication-architecture)
9. [Lead Lifecycle](#9-lead-lifecycle)
10. [Meta Integration Architecture](#10-meta-integration-architecture)
11. [Webhook Architecture](#11-webhook-architecture)
12. [Duplicate Lead Handling](#12-duplicate-lead-handling)
13. [Role / Permission Matrix](#13-role--permission-matrix)
14. [Dashboard Data Architecture](#14-dashboard-data-architecture)
15. [Deployment Architecture](#15-deployment-architecture)
16. [Git Workflow](#16-git-workflow)
17. [Demo VPS Isolation Strategy](#17-demo-vps-isolation-strategy)
18. [Security Considerations](#18-security-considerations)
19. [Resource Optimization Strategy](#19-resource-optimization-strategy)
20. [Development Phases](#20-development-phases)

---

## 1. Recommended Architecture

### Pattern: Modular Monolith + Shared API Clients

```
┌─────────────────────────────────────────────────────────┐
│                 Flutter Clients                         │
│         (Android / iOS / Web — one codebase)            │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTPS / JSON (Bearer tokens)
┌───────────────────────▼─────────────────────────────────┐
│              Laravel REST API (Modular Monolith)        │
│  Auth │ Leads │ Stages │ Sources │ Meta │ Dashboard     │
│  Users │ Activities │ Follow-ups │ Site Visits │ Audit  │
└───────────┬─────────────────────────────┬───────────────┘
            │                             │
            ▼                             ▼
       MySQL (app DB)              Meta Graph API
                                   + Webhooks (inbound)
```

### Why this shape

| Decision | Why |
|----------|-----|
| **Modular monolith (not microservices)** | One deployable API is enough for V1 lead volume; avoids network hops, ops overhead, and shared-VPS complexity. |
| **Flutter for all three platforms** | One UI codebase for Android, iOS, and Web; preferred stack; reduces duplicate feature work. |
| **Laravel REST API** | Mature auth, validation, Eloquent, queues, and webhook handling; preferred backend. |
| **MySQL** | Fits Laravel, VPS hosting, and relational lead/stage/audit queries well. |
| **Source-agnostic lead core** | Meta is V1 only; `lead_sources` + provider adapters keep Website/Google/etc. additive later. |
| **Configurable stages** | Stages live in DB (`lead_stages`), not enums hard-wired into business rules. |
| **No finance domain in V1** | Explicitly out of scope: no price, budget, deal amount, commission, revenue, payment, or financial reports. |

### Core design principles

1. **Lead is the aggregate root** — activities, follow-ups, site visits, and attribution hang off the lead.
2. **Configuration over hard-coding** — sources, stages, property types, configurations, purposes are admin-editable lookup data (seeded with V1 defaults).
3. **Server owns integrations** — Meta tokens never reach Flutter.
4. **Traceability over silent cleanup** — duplicates are linked and flagged, never auto-deleted.
5. **Least privilege by role** — OWNER / ADMIN / SALES_PERSON enforced in API policies, not only in UI.

---

## 2. Project Folder Structure

Monorepo under the assigned project directory only:

```
shreeram-crm/
├── README.md
├── .gitignore
├── .env.example                    # Documented env vars only (no secrets)
├── docs/
│   ├── ARCHITECTURE.md             # This document
│   ├── API.md                      # Endpoint reference (later)
│   ├── DEPLOYMENT.md               # Demo VPS isolation notes (later)
│   └── SECURITY.md                 # Threat model summary (later)
│
├── backend/                        # Laravel application
│   ├── app/
│   │   ├── Domain/                 # Optional domain grouping (Lead, Meta, Auth…)
│   │   ├── Http/
│   │   │   ├── Controllers/Api/
│   │   │   ├── Middleware/
│   │   │   ├── Requests/
│   │   │   └── Resources/
│   │   ├── Models/
│   │   ├── Policies/
│   │   ├── Services/
│   │   │   ├── Lead/
│   │   │   ├── Meta/
│   │   │   ├── Duplicate/
│   │   │   └── Dashboard/
│   │   └── Providers/
│   ├── bootstrap/
│   ├── config/
│   ├── database/
│   │   ├── migrations/
│   │   ├── seeders/
│   │   └── factories/
│   ├── routes/
│   │   ├── api.php
│   │   └── web.php                 # Minimal (health, webhook verify if needed)
│   ├── storage/
│   ├── tests/
│   ├── composer.json
│   └── .env.example
│
├── mobile/                         # Flutter application (Android/iOS/Web)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/
│   │   ├── core/                   # Theme, networking, DI, errors
│   │   ├── features/               # Feature-first modules
│   │   │   ├── auth/
│   │   │   ├── dashboard/
│   │   │   ├── leads/
│   │   │   ├── follow_ups/
│   │   │   ├── site_visits/
│   │   │   ├── team/
│   │   │   ├── meta_connection/    # Owner/Admin only UI
│   │   │   └── settings/
│   │   └── shared/
│   ├── test/
│   ├── web/
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── .env.example                # API base URL only — never Meta secrets
│
└── deploy/                         # Project-isolated deploy assets
    ├── nginx/shreeram-crm.conf.example
    ├── systemd/ or docker-compose.demo.yml.example
    └── README.md                   # Isolation rules for demo VPS
```

### Why this layout

| Decision | Why |
|----------|-----|
| **Monorepo (`backend/` + `mobile/`)** | Single GitHub source of truth; API contract and clients evolve together. |
| **Feature folders in Flutter** | Matches screens/roles (leads, follow-ups, dashboard) and keeps UI ownership clear. |
| **Service layer in Laravel** | Controllers stay thin; Meta/duplicate/dashboard logic is testable and reusable. |
| **`deploy/` examples only** | Documents isolation without touching live VPS configs until approved. |
| **`docs/` first** | Architecture approved before code; onboarding and review stay in-repo. |

---

## 3. Flutter Architecture

### Pattern: Feature-first + layered presentation

```
UI (Screens/Widgets)
        ↓
State (Riverpod or Bloc — pick one; recommend Riverpod)
        ↓
Repositories (API wrappers)
        ↓
HTTP Client (Dio) + Secure Token Storage
        ↓
Laravel REST API
```

### Recommended stack (minimal)

| Layer | Choice | Why |
|-------|--------|-----|
| State | **Riverpod** | Lightweight DI + reactive state; less boilerplate than many Bloc setups for CRUD CRM. |
| HTTP | **Dio** | Interceptors for auth headers, 401 refresh/logout, pagination helpers. |
| Routing | **go_router** | Deep links, role-based redirects, Web + mobile parity. |
| Storage | **flutter_secure_storage** (mobile) + secure/httpOnly cookie or memory strategy (web) | Tokens must not sit in plain SharedPreferences. |
| Models | Freezed/json_serializable *only if needed* | Prefer simple Dart models first; add codegen only when payload size justifies it. |

### Feature modules

| Feature | OWNER | ADMIN | SALES_PERSON |
|---------|-------|-------|--------------|
| Auth / profile | ✓ | ✓ | ✓ |
| Dashboard (stage counters) | Full | Full / filtered | My-leads scoped |
| Leads list & detail | All | All | Assigned + unassigned new (per policy) |
| Follow-ups / site visits | All | All | Own |
| Team / users | ✓ | ✓ | ✗ |
| Stages / sources settings | ✓ | ✓ | ✗ |
| Meta connection | ✓ | ✓ | ✗ |
| Audit / team activity | ✓ | Limited | ✗ |

### Platform notes

- **Android / iOS:** Call (`tel:`) and WhatsApp (`https://wa.me/`) via URL launchers from lead detail — no custom dialer SDK required for V1.
- **Web:** Same API; responsive layouts; avoid platform plugins that break web builds.
- **Role gating:** Hide admin routes in UI **and** enforce on API (UI hide is not security).

### Why Flutter this way

- One codebase satisfies the three-platform requirement.
- Feature-first modules map cleanly to CRM jobs (one job per screen/section).
- Minimal packages keep APK/IPA/Web bundles light on a shared demo VPS and slow networks.

---

## 4. Laravel Architecture

### Pattern: Modular monolith inside one Laravel app

Logical modules (folders / service namespaces), **not** separate deployables:

| Module | Responsibility |
|--------|----------------|
| **Auth** | Login, logout, token issue/revoke, password change |
| **Users** | OWNER/ADMIN user CRUD; salesperson assignment |
| **Leads** | CRUD, assignment, stage transitions, field updates |
| **Stages** | Configurable stage catalog + Lost flag |
| **Sources** | Lead source catalog (META, WEBSITE, GOOGLE, OTHER…) |
| **Activities** | Remarks, stage history, call/WhatsApp attempt logs |
| **FollowUps** | Schedule, complete, overdue queries |
| **SiteVisits** | Interest, preferred datetime, status |
| **Meta** | Connection config, webhook intake, Graph API sync |
| **Duplicates** | Detection, linking, review actions |
| **Dashboard** | Aggregated counters from DB |
| **Audit** | Security-relevant and business-relevant event log |

### Layering

```
Route → FormRequest (validation)
     → Controller
     → Policy (authorization)
     → Service (business rules)
     → Model / Query Builder
     → API Resource (response shaping)
```

### Why Laravel this way

| Decision | Why |
|----------|-----|
| **Modules as namespaces, one app** | Clear boundaries without microservice ops. |
| **Policies + FormRequests** | Centralize authz and validation; reduce controller bugs. |
| **API Resources** | Hide Meta technical fields from sales roles in response DTOs. |
| **Queues only when needed** | Webhook acknowledgement can enqueue processing; avoid idle workers for everything. |
| **No finance tables/modules** | Prevents accidental scope creep in V1. |

---

## 5. Database Tables

> Naming: snake_case plural. Soft deletes where business entities need recovery. **No amount/price/budget/commission columns anywhere.**

### 5.1 Identity & access

| Table | Purpose |
|-------|---------|
| `users` | Staff accounts: name, email, mobile, password hash, role, is_active, last_login_at |
| `personal_access_tokens` | Laravel Sanctum tokens (API auth) |
| `password_reset_tokens` | Standard Laravel resets (if enabled) |

### 5.2 Configuration / lookups

| Table | Purpose |
|-------|---------|
| `lead_sources` | Code (`META`, `WEBSITE`…), name, is_active, sort_order |
| `lead_stages` | Code, name, sort_order, is_lost, is_terminal, is_active, color (optional UI) |
| `property_types` | Apartment, Villa, Plot, Shop, Office, Other |
| `property_configurations` | 1–4 BHK, Other |
| `lead_purposes` | Residential, Investment, Commercial |
| `site_visit_statuses` | Planned, Done, Cancelled, No-show, etc. (configurable) |
| `follow_up_statuses` | Pending, Done, Skipped, etc. (configurable) |

**Why DB lookups:** Owner/Admin can add/rename stages and sources later without migrations for every label change.

### 5.3 Leads & attribution

| Table | Purpose |
|-------|---------|
| `leads` | Core lead record |
| `lead_meta_attributions` | Meta-specific attribution (page/form/campaign/ad set/ad) — 1:1 optional |
| `lead_field_values` *(optional V1.1)* | EAV for future custom fields; defer if V1 columns suffice |
| `lead_assignments` | Assignment history (who, when, by whom) |

**Proposed `leads` columns (conceptual):**

- Identity: `id`, `public_id` (optional opaque code), `name`, `mobile`, `email`
- Source: `lead_source_id`, `external_lead_id` (e.g. Meta leadgen id — unique per source)
- Stage: `lead_stage_id`, `lost_reason` (nullable)
- Interest: `property_type_id`, `property_configuration_id`, `preferred_location`, `purpose_id`
- Ownership: `assigned_to` (user_id nullable), `created_by` (nullable for webhook)
- Duplicate: `is_duplicate`, `duplicate_of_lead_id`, `duplicate_confidence`
- Site visit prefs (denormalized for list filters): `interested_in_site_visit`, `preferred_visit_date`, `preferred_visit_time`, `site_visit_status_id`
- Follow-up snapshot: `next_follow_up_at`, `follow_up_status_id`
- Timestamps: `created_at`, `updated_at`, `contacted_at`, `closed_at`, `deleted_at`

### 5.4 Activities & scheduling

| Table | Purpose |
|-------|---------|
| `lead_activities` | Polymorphic-style log: remark, stage_change, call, whatsapp, assignment, system |
| `follow_ups` | Scheduled follow-ups with status, due_at, completed_at, remarks |
| `site_visits` | Planned/done visits with status, scheduled_at, completed_at, remarks |

### 5.5 Meta integration (server-side only)

| Table | Purpose |
|-------|---------|
| `meta_connections` | App ID, encrypted page access token, page id/name, webhook verify token hash, status |
| `meta_lead_forms` | Form ID, form name, page link, is_active |
| `meta_webhook_events` | Raw payload store for replay/debug (retain with TTL policy) |
| `meta_lead_ingestions` | Per-leadgen processing status: received → validated → created/duplicate/failed |

### 5.6 Audit & settings

| Table | Purpose |
|-------|---------|
| `audit_logs` | actor_id, action, entity_type, entity_id, ip, user_agent, meta JSON |
| `app_settings` | Key/value for non-secret app config |

### Indexes (minimum)

- `leads(mobile)`, `leads(email)`, `leads(lead_stage_id)`, `leads(assigned_to)`, `leads(created_at)`
- `leads(lead_source_id, external_lead_id)` UNIQUE (where external id present)
- `follow_ups(due_at, status)`, `site_visits(scheduled_at, status)`
- `lead_activities(lead_id, created_at)`

### Explicitly excluded from V1 schema

Property price, budget, deal amount, commission, revenue, payment, amount, financial reporting tables/views.

---

## 6. Database Relationships

```
users 1───* leads (assigned_to)
users 1───* lead_assignments
users 1───* lead_activities
users 1───* follow_ups
users 1───* site_visits
users 1───* audit_logs

lead_sources 1───* leads
lead_stages 1───* leads
property_types 1───* leads
property_configurations 1───* leads
lead_purposes 1───* leads

leads 1───0..1 lead_meta_attributions
leads 1───* lead_activities
leads 1───* follow_ups
leads 1───* site_visits
leads 1───* lead_assignments
leads 0..1───* leads (duplicate_of_lead_id self-FK)

meta_connections 1───* meta_lead_forms
meta_lead_forms 1───* lead_meta_attributions (optional link)
meta_connections 1───* meta_webhook_events
meta_webhook_events 1───* meta_lead_ingestions (optional)
```

### Why these relationships

- **Self-FK for duplicates** keeps both records and a clear parent/child link.
- **Separate attribution table** keeps Meta noise off the core lead row and out of sales list payloads.
- **Activities as append-only history** supports auditability without rewriting lead rows for every remark.
- **Assignment history table** preserves “who had this lead when” for owner team activity views.

---

## 7. API Structure

Base: `/api/v1`

### Conventions

- JSON request/response
- Pagination: `?page=&per_page=` (max capped, e.g. 50)
- Filtering: query params (`stage_id`, `source_id`, `assigned_to`, `q`, date ranges)
- Errors: consistent `{ message, errors?, code? }`
- Version prefix allows future breaking changes without mobile force-upgrade chaos

### Endpoint groups

#### Auth
| Method | Path | Notes |
|--------|------|-------|
| POST | `/auth/login` | Issue Sanctum token |
| POST | `/auth/logout` | Revoke current token |
| GET | `/auth/me` | Current user + role + permissions summary |

#### Users (OWNER/ADMIN)
| Method | Path | Notes |
|--------|------|-------|
| GET/POST | `/users` | List/create |
| GET/PUT/PATCH | `/users/{id}` | Update; deactivate |
| PATCH | `/users/{id}/role` | Role change (OWNER-only recommended) |

#### Lookups / config
| Method | Path | Notes |
|--------|------|-------|
| GET | `/lead-sources` | Active sources |
| CRUD | `/lead-sources` | ADMIN/OWNER |
| GET | `/lead-stages` | Ordered stages |
| CRUD | `/lead-stages` | ADMIN/OWNER |
| GET | `/property-types`, `/property-configurations`, `/purposes` | Lookups |

#### Leads
| Method | Path | Notes |
|--------|------|-------|
| GET | `/leads` | Scoped by role |
| POST | `/leads` | Manual create (any allowed source) |
| GET | `/leads/{id}` | Detail; Meta fields role-filtered |
| PATCH | `/leads/{id}` | Update profile/interest fields |
| PATCH | `/leads/{id}/stage` | Stage transition + activity |
| PATCH | `/leads/{id}/assign` | Assign salesperson |
| POST | `/leads/{id}/remarks` | Add remark activity |
| GET | `/leads/{id}/activities` | Timeline |
| GET | `/leads/{id}/duplicates` | Linked duplicates |

#### Follow-ups & site visits
| Method | Path | Notes |
|--------|------|-------|
| GET/POST | `/follow-ups` | List/create; filters for today/overdue |
| PATCH | `/follow-ups/{id}` | Complete/reschedule |
| GET/POST | `/site-visits` | List/create |
| PATCH | `/site-visits/{id}` | Status updates |

#### Dashboard
| Method | Path | Notes |
|--------|------|-------|
| GET | `/dashboard/summary` | Stage counters + today/overdue — **DB-backed** |

#### Meta (OWNER/ADMIN, server-side secrets never returned in full)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/meta/connection` | Status, page name, connected forms (masked token) |
| POST | `/meta/connection` | Save app/page credentials (encrypted at rest) |
| POST | `/meta/connection/test` | Validate token/page access |
| GET | `/meta/forms` | List forms from Graph API or DB cache |
| POST | `/meta/forms/sync` | Pull forms for connected page |
| GET | `/meta/webhook/verify` | Meta subscription challenge |
| POST | `/meta/webhook` | Inbound leadgen events |

#### Audit (OWNER; ADMIN limited)
| Method | Path | Notes |
|--------|------|-------|
| GET | `/audit-logs` | Filterable activity |

### Why this API shape

- **Versioned REST** is simple for Flutter Dio clients across three platforms.
- **Separate dashboard endpoint** avoids N+1 client aggregation and keeps counters authoritative.
- **Role-filtered resources** ensure sales users never receive Meta tokens or unnecessary technical IDs.

---

## 8. Authentication Architecture

### Choice: Laravel Sanctum (API tokens)

```
Flutter login
  → POST /api/v1/auth/login (email + password)
  → Sanctum personal access token
  → Stored in secure storage
  → Authorization: Bearer <token> on each request
  → Logout revokes token
```

### Why Sanctum (not Passport/JWT custom)

| Option | Verdict |
|--------|---------|
| **Sanctum** | Best fit for first-party mobile/web SPA talking to own API; simple token revoke. |
| Passport/OAuth2 server | Heavier than needed for internal staff CRM. |
| Pure JWT without revoke list | Harder logout/compromise response. |

### Authorization

- Role column on `users` for V1: `OWNER`, `ADMIN`, `SALES_PERSON`
- Laravel Policies + Gate abilities (e.g. `leads.viewAll`, `meta.manage`)
- Optional `permissions` map derived from role in `/auth/me` for Flutter menu building
- Future: permission table if finer grants needed — **do not build full ACL engine in V1**

### Session / token hygiene

- Token abilities scoped if useful (`*` for staff is OK in V1)
- Idle/expiry policy via Sanctum expiration config
- Force logout on deactivate user
- HTTPS only in demo/prod

---

## 9. Lead Lifecycle

### Configurable stages (seeded defaults)

| Order | Stage | Notes |
|------:|-------|-------|
| 1 | New Lead | Default for inbound Meta / manual |
| 2 | Contacted | First outreach done |
| 3 | Interested | Positive intent |
| 4 | Site Visit Planned | Visit scheduled |
| 5 | Site Visit Done | Visit completed |
| 6 | Follow Up | Ongoing nurture |
| 7 | Negotiation | Commercial discussion (still **no amounts stored**) |
| 8 | Booked | Conversion success |
| 9 | Closed | Terminal success/archive as defined by admin |
| — | Lost | Separate status via `is_lost` stage (or flag) — not in happy-path order |

**Why not hard-code enums in services:** Stage transitions validate against `lead_stages.is_active` and optional allowed-transition rules table later; V1 can allow any active non-conflicting transition with audit log.

### Lifecycle flow

```
[Source Adapter: Meta/Manual/Future]
        ↓
Validate payload
        ↓
Duplicate check (mobile + external id)
        ↓
Create lead (stage = New Lead)  OR  link as duplicate / refresh attribution
        ↓
Assign (round-robin / manual / unassigned pool — decide in Phase 3)
        ↓
Sales actions: Contact → update stage, remarks, call/WhatsApp
        ↓
Schedule follow-up / site visit
        ↓
Progress stages…
        ↓
Booked / Closed  OR  Lost
```

### Activity on every meaningful change

Stage change, assignment, remark, follow-up schedule/complete, site visit status → `lead_activities` row.

### Why this lifecycle model

- Matches the business funnel without baking Meta-only assumptions into stage names.
- “Lost” as parallel terminal path avoids polluting ordered funnel stats.
- Negotiation without money fields still tracks sales progress for V1.

---

## 10. Meta Integration Architecture

### Principles

1. Meta is **one** `lead_sources` code (`META`), not the schema.
2. Credentials live **only** in `meta_connections` (encrypted) on the server.
3. Flutter Owner/Admin UI configures connection at a business level (App, Page, Form) — not a wall of optional IDs.
4. Campaign / Ad Set / Ad data is **attribution on the lead**, not required setup fields.

### Connection model (what humans configure)

| Concept | Stored | User-facing |
|---------|--------|-------------|
| Meta App | App ID + App Secret (encrypted) | “Connect Meta App” |
| Page | Page ID + Page access token (encrypted) | Select/connect Facebook Page |
| Lead Form | Form ID + name | Enable forms to accept leads |
| Webhook | Verify token (hashed), callback URL shown | Copy callback URL; one-click docs |

Campaign ID/Name, Ad Set ID/Name, Ad ID/Name → stored on `lead_meta_attributions` when Meta sends them.

### Ingestion pipeline

```
Meta Lead Ads Form submit
    → Meta Webhook (leadgen)
    → Laravel POST /api/v1/meta/webhook
    → Verify signature / page subscription
    → Persist raw event (meta_webhook_events)
    → Fetch lead details via Graph API (leadgen_id) using server token
    → Map fields → canonical lead DTO
    → Duplicate check
    → Create/link lead + attribution
    → Assign
    → Dashboard counts update naturally via queries
```

### Adapter interface (future-proof)

```text
LeadSourceIngestor
  ├─ MetaLeadIngestor
  ├─ WebsiteLeadIngestor   (future)
  └─ GoogleLeadIngestor    (future)
```

Each adapter: validate → normalize → hand off to `LeadIntakeService`.

### Why this Meta design

- Uses Meta’s supported webhook + Graph API pattern (no fake “paste every ID” form).
- Keeps tokens server-side.
- Attribution richness without forcing sales users to understand Ads Manager hierarchy.
- Source adapter pattern means Website/Google later do not rewrite lead core.

---

## 11. Webhook Architecture

### Endpoints

1. **GET** `/api/v1/meta/webhook` — subscription verification (`hub.mode`, `hub.verify_token`, `hub.challenge`)
2. **POST** `/api/v1/meta/webhook` — event delivery

### Processing strategy (lightweight)

```
POST received
  → Fast ACK 200 (after minimal verify + durable enqueue/store)
  → Async job: ProcessMetaWebhookJob
       → parse leadgen entries
       → idempotent by leadgen_id
       → Graph API fetch if field data not inline
       → LeadIntakeService
```

**Why ACK-then-process:** Meta retries on timeout; slow Graph calls inside the HTTP request risk duplicate deliveries and failed handshakes.

### Idempotency

- Unique key on `meta_lead_ingestions.leadgen_id` (or `leads.external_lead_id` + source META)
- Re-delivery → no second primary lead; update ingestion log; optionally refresh attribution

### Observability

- Store raw payload (TTL, e.g. 30 days) for support replay
- Status: `received | processed | duplicate | failed`
- Failed jobs: retry with backoff; alert via log (no heavy monitoring stack in V1)

### Security of webhooks

- Verify token match on GET
- Validate `X-Hub-Signature-256` on POST when App Secret configured
- Rate-limit webhook route separately
- Never expose webhook debug payloads to SALES_PERSON clients

---

## 12. Duplicate Lead Handling

### Detection signals (V1)

| Signal | Strength | Action |
|--------|----------|--------|
| Same `lead_source_id` + `external_lead_id` | Exact (Meta resubmit/retry) | Do not create new primary; mark ingestion duplicate |
| Normalized mobile match | Strong | Create or link as duplicate candidate; flag UI |
| Mobile + same name fuzzy | Medium | Flag for review |
| Email-only match | Weaker | Flag, do not auto-merge |

**Normalization:** strip spaces/dashes; store `mobile_normalized` (E.164-ish or digits-only national) for index lookups.

### Handling rules

1. **Never auto-delete.**
2. Prefer: create linked record with `is_duplicate=true` and `duplicate_of_lead_id` **or** attach activity “Repeated submission” on existing lead — product choice:
   - **Recommended default:** keep new row linked as duplicate for full Meta traceability; show banner on both records.
3. Owner/Admin can later “Dismiss duplicate” or “Merge remarks into primary” (merge can be Phase 2).
4. Dashboard “Total Leads” should define whether duplicates count — **recommend:** exclude `is_duplicate=true` from funnel totals; show separate “Duplicate submissions” counter for Owner.

### Why this approach

- Preserves Meta/legal traceability of each submission.
- Mobile is the strongest real-estate contact key in this market context.
- Avoids destructive merges that lose attribution history.

---

## 13. Role / Permission Matrix

| Capability | OWNER | ADMIN | SALES_PERSON |
|------------|:-----:|:-----:|:------------:|
| View full dashboard counters | ✓ | ✓ | Scoped (own) |
| View all leads | ✓ | ✓ | ✗ (own / allowed pool only) |
| Create manual lead | ✓ | ✓ | ✓ (optional; default ✓) |
| Update lead fields | ✓ | ✓ | Own leads |
| Change lead stage | ✓ | ✓ | Own leads |
| Add remarks | ✓ | ✓ | Own leads |
| Call / WhatsApp actions | ✓ | ✓ | Own leads |
| Schedule follow-up / site visit | ✓ | ✓ | Own leads |
| Assign / reassign leads | ✓ | ✓ | ✗ |
| Manage users | ✓ | ✓ | ✗ |
| Change roles / deactivate Admin | ✓ | ✗* | ✗ |
| Manage stages | ✓ | ✓ | ✗ |
| Manage lead sources | ✓ | ✓ | ✗ |
| Meta connection & webhook | ✓ | ✓ | ✗ |
| View Meta technical attribution | ✓ | ✓ | Limited/hidden |
| Team activity / audit | ✓ | Limited | ✗ |
| App settings | ✓ | Limited | ✗ |

\*Recommend only OWNER can delete/demote ADMIN.

### Enforcement

- API Policies are source of truth
- Flutter hides navigation items using `/auth/me` permissions
- Salesperson must not receive admin route payloads even if URL guessed

---

## 14. Dashboard Data Architecture

### Single summary endpoint

`GET /api/v1/dashboard/summary`

Returns **live aggregates** from MySQL (not cached hard-coded numbers):

**Stage counters** (respect role scope + exclude duplicates per rule):

- Total Leads  
- Per active stage (New, Contacted, Interested, Site Visit Planned/Done, Follow Up, Negotiation, Booked, Closed)  
- Lost  

**Operational counters:**

- Today’s New Leads (`created_at` = today)  
- Today’s Follow-ups (`due_at` = today, pending)  
- Today’s Site Visits (`scheduled_at` = today)  
- Overdue Follow-ups (`due_at` < now, pending)  

### Query strategy

- Prefer conditional aggregates in few queries (`GROUP BY lead_stage_id`) over per-stage round trips
- Indexes on `lead_stage_id`, `created_at`, `assigned_to`, follow-up `due_at`
- Short cache (e.g. 30–60s) **optional** later if profiling shows need — not required day one
- Salesperson: same shape, `WHERE assigned_to = auth_id`

### Why

Counters must reflect reality for owner decisions; hard-coded demo numbers are forbidden. Stage-based counters stay correct when admin renames/adds stages if the API returns `{ stage_id, stage_name, count }[]` plus named convenience fields for seeded defaults.

---

## 15. Deployment Architecture

### Target: Demo VPS (shared with other projects)

```
Internet
   ↓
Nginx (server_name = this app only)
   ↓
PHP-FPM pool OR container dedicated to shreeram-crm
   ↓
Laravel (backend/)
   ↓
MySQL database `shreeram_crm` (dedicated schema/user)
```

Flutter Web build served as static files from the same Nginx `server` block (`/`, `/api` → PHP).

Mobile apps point `API_BASE_URL` to this host.

### Process model (lightweight)

- PHP-FPM or single Docker Compose stack **namespaced** to this project
- Queue worker: one supervised worker **only if** webhook jobs enabled
- Scheduler: enable only for overdue reminders / webhook cleanup if needed — keep minimal

### Why

Fits modular monolith; avoids Kubernetes/microservices on a shared demo host.

---

## 16. Git Workflow

### Source of truth: GitHub (`doshihiren/shreeram-crm`)

| Branch | Purpose |
|--------|---------|
| `main` | Protected production-ready / demo deployable |
| `cursor/<feature>-523b` | Agent/feature branches |
| `feature/<name>` | Human feature work |
| `fix/<name>` | Hotfixes |

### Practices

- Meaningful commits (why + what)
- PR review before merge to `main`
- Never commit: `.env`, tokens, passwords, private keys, Meta secrets
- Always provide `.env.example` with variable names and descriptions
- Tag releases optionally (`v0.1.0-architecture`, `v1.0.0`)

### Suggested `.gitignore` roots

- `backend/.env`, `mobile/.env`, `**/uploads`, IDE files, `build/`, `dist/`, keystores

---

## 17. Demo VPS Isolation Strategy

**Hard rule:** Only operate inside the directory and resources assigned to this CRM.

### Isolation checklist

| Resource | Strategy |
|----------|----------|
| Files | `/var/www/shreeram-crm` (or assigned path) only |
| Nginx | Dedicated `server_name` + config file; do not edit other sites |
| SSL | Cert only for this domain/subdomain |
| MySQL | Dedicated database + user with privileges **only** on that DB |
| PHP/Docker | Project-local version via container or dedicated FPM pool — avoid global runtime upgrades |
| Queues/cron | Project-specific systemd unit / compose service names prefixed `shreeram-crm-` |
| Ports | Avoid colliding with existing published ports; use Nginx proxy |

### Forbidden without explicit approval

- Restarting unrelated containers/services  
- Dropping/altering other databases  
- Changing global Node/PHP/Nginx defaults  
- Removing shared packages  
- Destructive disk operations outside project path  

### Why

Shared demo VPS blast radius is high; project isolation is a safety requirement equal to product features.

---

## 18. Security Considerations

| Area | Approach |
|------|----------|
| Authentication | Sanctum tokens; hashed passwords (bcrypt/argon2) |
| Authorization | Role policies on every sensitive route |
| API auth | Bearer tokens; no Meta secrets in clients |
| Input validation | FormRequests; strict types; max lengths |
| SQL injection | Eloquent/Query Builder bindings only |
| XSS | API JSON + Flutter widgets (escape); CSP on web build |
| CSRF | Token auth APIs typically cookie-less; if cookie SPA mode used, enable Sanctum CSRF |
| Token storage | Secure storage on device; short-lived or revocable tokens |
| Meta secrets | Encrypted columns (`encrypted` cast); never in API resources to sales |
| Webhook | Signature + verify token; raw payload access restricted |
| PII | Least privilege; audit access to lead export (export later) |
| Audit logging | Login, assignment, stage change, Meta config changes |
| Transport | HTTPS only on demo/prod |
| Headers | Standard security headers on Nginx for this vhost |

### Threat notes

- Staff CRM still holds customer PII — treat demo like production data hygiene.
- Do not log full Meta tokens or raw phone lists to world-readable logs.

---

## 19. Resource Optimization Strategy

| Tactic | Application |
|--------|-------------|
| Pagination | All lead/activity list endpoints |
| Server-side filters | Stage, assignee, dates — not client-side full download |
| Indexed queries | See §5 |
| Lean API resources | List DTOs exclude Meta attribution blobs |
| Lazy loading in Flutter | Paginated lists; defer admin tabs |
| Few dependencies | No unnecessary Flutter/Laravel packages |
| Queues sparingly | Webhook processing only |
| Cron sparingly | Cleanup + overdue flags if required |
| No microservices | One API |
| Caching | Optional dashboard cache after metrics prove need |
| Assets | Compressed Flutter web build; no large stock media in-repo |
| N+1 prevention | Eager load stage/source/assignee on lead lists |

### Why

Demo VPS is shared and finite; CRM UX depends more on fast list/filter than on elaborate background systems.

---

## 20. Development Phases

> No calendar estimates — phases are sequenced by dependency. Implementation starts only after architecture approval.

### Phase 0 — Alignment (this document)
- Architecture review & approval
- Confirm assignment rules (unassigned pool vs round-robin)
- Confirm duplicate UX (linked row vs activity-only)
- Confirm demo domain/path on VPS (no changes yet)

### Phase 1 — Foundation
- Repo structure (`backend/`, `mobile/`, `docs/`, `.env.example`)
- Laravel app skeleton + Sanctum auth
- Flutter app skeleton + login + role routing shell
- Users + roles seed (OWNER/ADMIN/SALES_PERSON)
- CI-friendly tests for auth

### Phase 2 — Lead core domain
- Migrations for sources, stages, lookups, leads, activities
- Seed default stages/sources/property fields
- Lead CRUD + stage change + remarks APIs
- Flutter leads list/detail for salesperson
- Policies & pagination

### Phase 3 — Follow-ups, site visits, assignment
- Follow-up & site visit tables/APIs
- Assignment + history
- Call/WhatsApp launch actions in UI
- Overdue/today queries

### Phase 4 — Dashboard
- `/dashboard/summary` aggregates
- Owner/Admin dashboard UI; salesperson scoped dashboard
- Verify counters against DB fixtures (no hard-coded UI numbers)

### Phase 5 — Meta integration
- `meta_connections` encrypted storage
- Owner/Admin connection UI (App/Page/Form)
- Webhook verify + ingest + Graph fetch
- Duplicate detection & ingestion logs
- Attribution stored; sales UI hides technical fields

### Phase 6 — Admin configuration & audit
- Stage/source management UI
- User management
- Audit log views
- Hardening: rate limits, security headers docs

### Phase 7 — Demo deploy (isolated)
- Dedicated DB/user, Nginx vhost, SSL for this app only
- Deploy backend + Flutter web
- Point mobile builds at demo API
- Smoke test Meta webhook on demo (with test page/form)

### Phase 8 — Hardening & handoff
- Performance pass (indexes, explain slow queries)
- Documentation: API, env vars, isolation runbook
- Backup strategy for this DB only

---

## Open Decisions (need approval)

1. **Assignment default for new Meta leads:** unassigned pool vs automatic round-robin among active salespersons.  
2. **Duplicate UX:** always create linked duplicate row vs attach to existing primary only on exact Meta leadgen replay.  
3. **Flutter state library:** Riverpod recommended — confirm.  
4. **Demo URL / project path on VPS:** required before Phase 7; no VPS changes until then.  
5. **Lost modeling:** dedicated stage with `is_lost=true` (recommended) vs boolean `is_lost` plus stage.  

---

## Out of Scope (V1)

- Property price, budget, deal amount, commission, revenue, payment, financial reports  
- Microservices  
- Customer-facing public portal  
- Full marketing automation  
- Hard-coded Meta-only data model  
- Modifications to other VPS projects  

---

## Approval Gate

**No application code, package installs, database creation, or VPS changes will proceed until this architecture is approved** (with answers to open decisions where possible).

After approval, implementation begins at **Phase 1** on a dedicated feature branch following the Git workflow above.
