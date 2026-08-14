# One-command Nginx cutover: v2 → v3

## Why
Old Flutter / CDN cache sticks on `/v2/`. **v3** is a new path (`app-v3`).

## Run these 2 commands on the VPS

```bash
cd /var/www/shreeram-crm
git pull origin cursor/crm-implementation-523b
bash deploy/FORCE_REFRESH_UI.sh
sudo bash deploy/CUTOVER_NGINX_V3.sh
```

That script will:
1. Backup `/etc/nginx/sites-enabled/aweliontech`
2. Replace `v2` / `app-v2` → `v3` / `app-v3`
3. Keep `/shreeram-crm/v2/` as a redirect to `/v3/`
4. `nginx -t` + reload
5. Print verify curls

## Open
**Incognito** → https://aweliontech.com/shreeram-crm/v3/

Expect:
- Login: `UI build 2026-08-11-V3`
- Leads: **Pipeline board** + gold **V3** badge + logo

## Rollback
The script prints the backup path. Example:

```bash
sudo cp -a /etc/nginx/backups/aweliontech.bak.YYYY-MM-DD-HHMMSS \
  /etc/nginx/sites-enabled/aweliontech
sudo nginx -t && sudo systemctl reload nginx
```
