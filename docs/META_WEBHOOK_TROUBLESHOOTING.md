# Why Meta leads arrive in Lead Center but not in CRM (auto webhook)

## Short answer

**Manual fetch** and **dummy Test** do not prove live webhook delivery.

| Path | What it uses | Needs Page `subscribed_apps`? |
|------|----------------|-------------------------------|
| Meta Developer **Test** button | POSTs a sample payload to the App’s webhook URL | No |
| `php artisan meta:import-leads` | Graph API pull with Page token | No |
| **Live form submit** | Meta notifies only apps on the Page with `leadgen` | **Yes — CRM app must be that app** |

If CRM App has the webhook URL configured, Test works.  
If Page token can read leads, manual import works.  
If the Page’s `leadgen` subscription is on **another** Meta app, live leads never hit CRM.

## Confirm on VPS (1 minute)

```bash
cd /var/www/shreeram-crm/backend
php artisan meta:check-logs
```

Look at **section E) Page subscribed_apps**:

- `OK: CRM app is subscribed to leadgen` → delivery wiring is good; check signature / recent events.
- `leadgen is subscribed on a DIFFERENT app` → this is the usual bug.
- `Page is NOT subscribed to leadgen` → nothing is notified.

Also check recent events:

- Empty `meta_webhook_events` → Meta is not POSTing to CRM (wrong app / no subscription).
- Status `rejected_signature` → App Secret in CRM ≠ Meta App secret.

Or via API (Owner/Admin with `meta.manage`):

`GET /api/v1/meta/webhook-health`

## Fix (live auto webhook)

1. Open the **same** Meta App whose **App ID** is saved in CRM Meta settings.
2. **Webhooks** → Callback  
   `https://aweliontech.com/shreeram-crm/api/v1/meta/webhook`  
   Verify token = the one saved in CRM. Subscribe field **`leadgen`**.
3. Create a **Page access token for Shreeram Developer from that same App**  
   (Graph API Explorer → select that App → get Page token).
4. Save in CRM: App ID + App Secret + Page ID + Page token.
5. On VPS:
   ```bash
   php artisan meta:subscribe-page
   php artisan meta:check-logs
   ```
   Section E must show your CRM `app_id` with `leadgen`.
6. Submit one real test lead. A new `meta_webhook_events` row should appear within seconds.

## Catch missed leads now

```bash
php artisan meta:import-leads --form=1301528194957429 --since=2026-08-01 --limit=500
php artisan meta:import-leads --form=751775527257092 --since=2026-08-01 --limit=50
```

## Safety net (recommended)

Laravel schedule runs `meta:poll-leads` every 5 minutes (Graph pull, idempotent).

Enable cron on VPS:

```bash
crontab -e
# add:
* * * * * cd /var/www/shreeram-crm/backend && php artisan schedule:run >> /dev/null 2>&1
```

Webhook remains the primary path; poller covers gaps when Meta delivery is miswired.
