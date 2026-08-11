# Fix: Shreeram Developer page missing from your Facebook user

## What your diagnose proved
- Saved token is a **User** token (`Hiren Doshi`), not a Page token.
- `/me/accounts` lists AWE / Awelion / Panam pages — **not** `Shreeram Developer` (`657023730834410`).
- So Meta will not give you a Page token for Shreeram, and form bulk pull stays blocked.
- Individual lead fetch **does** work → you can import by lead ID or CSV right now.

## Fix permanently (required for auto webhook + form pull)

Someone who is **Business Admin** of the Business that owns **Shreeram Developer** must assign **Hiren Doshi**:

1. Open [business.facebook.com](https://business.facebook.com) with the **Shreeram business admin** login  
   (not only the Awelion business, if they are different)
2. **Business settings** (gear) → **Users** → **People**
3. Select **Hiren Doshi** (or invite his Facebook email)
4. **Assign assets** → **Pages** → enable **Shreeram Developer**
5. Permission: **Full control** (best) or at least **Advertise**
6. Also assign the **Ad account** that runs “Shreeram Leads Campaign – March 2026” if asked
7. Hiren accepts any invite on Facebook

Then Hiren regenerates token:

1. [Graph API Explorer](https://developers.facebook.com/tools/explorer/) → your App  
2. Get **User** token with:  
   `pages_show_list`, `pages_manage_ads`, `pages_manage_metadata`, `pages_read_engagement`, `leads_retrieval`  
3. On the Facebook popup, tick **Shreeram Developer**  
4. Paste User token into CRM Meta → Save  
5. On VPS:
```bash
php artisan meta:exchange-page-token
php artisan meta:diagnose
php artisan meta:import-leads --form=1301528194957429 --limit=100
```

`/me/accounts` must now include:
`657023730834410  Shreeram Developer`

## Import leads now (workaround — works today)

### Option A — by lead IDs
```bash
cd /var/www/shreeram-crm/backend
php artisan meta:import-leads \
  1007170865702767 \
  3629677677169983 \
  2132494047618571 \
  1785748245894113 \
  --form=1301528194957429
```

### Option B — Lead Center CSV/TSV export
1. Meta Lead Center → export leads for that form  
2. Copy file to VPS, e.g. `/tmp/shreeram-leads.csv`
```bash
cd /var/www/shreeram-crm
git pull origin cursor/crm-implementation-523b
cd backend
php artisan meta:import-leads --csv=/tmp/shreeram-leads.csv --form=1301528194957429
```
