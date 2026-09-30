# Fix: Shreeram Developer page missing from token dropdown

## What we know
- Your token is **Hiren Doshi** (User token).
- `/me/accounts` shows AWE / Awelion / Panam pages — **not** Shreeram Developer.
- So Graph API Explorer will never show that Page in the dropdown for this login/app grant.
- Individual lead fetch **works** → import by lead ID / CSV works today.

## Other ideas when the Page never appears in the dropdown

### Idea A — Wrong Business (most common)
Shreeram Page is often under a **client Business**, while Hiren’s token lists **agency** Pages (Awelion/AWE).

1. business.facebook.com → top-left **switch Business**
2. Open every Business until you find **Pages → Shreeram Developer**
3. In that Business: **Users → People → add Hiren → Assign Page (Full control)**
4. Accept invite on Facebook
5. Re-generate Graph token and look for the Page again

### Idea B — Confirm the real Page ID
On the Page: **About → Page transparency / Page ID**  
Compare to CRM value `657023730834410`.

Or on VPS:
```bash
php artisan meta:inspect-lead 1785748245894113
```
This prints form/ad info and lists every Page your token can see (with paging).

### Idea C — Business Manager **System User** (best when dropdown never shows)
Use this when you “manage” the Page in Ads/Lead Center but personal user still can’t get it in Explorer.

1. Open the Business that **owns** Shreeram Developer  
2. **Business settings → Users → System users → Add**  
   - Name: `ShreeRam CRM`  
   - Role: **Admin** (or Employee + assets)
3. Click the System User → **Add assets**
   - Page: **Shreeram Developer** (Full control)
   - Ad account used for the Lead campaign (Manage ads)
4. **Generate new token**
   - App: your CRM Meta App (`807012981799222`)
   - Permissions: `pages_show_list`, `pages_manage_ads`, `pages_manage_metadata`, `pages_read_engagement`, `leads_retrieval`, `ads_management`
5. Copy token → CRM **Meta → Page access token → Save**
6. VPS:
```bash
php artisan meta:diagnose --form=1301528194957429 --lead=1785748245894113
php artisan meta:import-leads --form=1301528194957429 --limit=100
```
`/me` should show Page name **or** System User that can call page/form APIs successfully.

### Idea D — App is not allowed on that Page
Page Admin must allow the app:
1. Page → Settings → **Connected apps** / Business integrations  
2. Or Graph (with a working Page admin token):
```text
POST /{page-id}/subscribed_apps?subscribed_fields=leadgen
```

### Idea E — Stop waiting on dropdown; import now
```bash
php artisan meta:import-leads \
  1007170865702767 \
  3629677677169983 \
  2132494047618571 \
  1785748245894113 \
  --form=1301528194957429
```
Or Lead Center export → upload to VPS →  
`php artisan meta:import-leads --csv=/tmp/shreeram-leads.csv --form=1301528194957429`
