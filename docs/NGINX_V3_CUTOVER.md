# One-time Nginx patch for ShreeRam v3 UI

## Why
Browsers / Cloudflare may still serve the old Flutter UI from `/shreeram-crm/` or `/v2/`.
**v3** is a new URL path + new asset folder (`app-v3`), so cache cannot reuse the old app.

## After pull + refresh script

```bash
cd /var/www/shreeram-crm
git pull origin cursor/crm-implementation-523b
bash deploy/FORCE_REFRESH_UI.sh
```

### 1. Backup (outside sites-enabled)
```bash
sudo mkdir -p /etc/nginx/backups
sudo cp -a /etc/nginx/sites-enabled/aweliontech \
  /etc/nginx/backups/aweliontech.bak.$(date +%F-%H%M%S)
```

### 2. Edit HTTPS server block
```bash
sudo nano /etc/nginx/sites-enabled/aweliontech
```

Replace the existing ShreeRam **UI** locations (keep the API block) with:

`deploy/nginx/shreeram-crm.path.example.conf`

Critical parts:
- API stays at `/shreeram-crm/api/`
- `/shreeram-crm` and `/shreeram-crm/` redirect to `/shreeram-crm/v3/`
- `/shreeram-crm/v2/` redirects to `/shreeram-crm/v3/`
- `/shreeram-crm/v3/` aliases to `/var/www/shreeram-crm/backend/public/app-v3/`

### 3. Reload
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 4. Verify
```bash
curl -sI https://aweliontech.com/shreeram-crm/ | head -5
# expect 302 to /shreeram-crm/v3/

curl -sI https://aweliontech.com/shreeram-crm/v2/ | head -5
# expect 302 to /shreeram-crm/v3/

curl -s https://aweliontech.com/shreeram-crm/v3/ | grep -o 'base href="[^"]*"'
# expect base href="/shreeram-crm/v3/"

curl -s https://aweliontech.com/shreeram-crm/v3/main.dart.js | grep -o "UI build 2026-08-11-V3" | head -1
curl -s https://aweliontech.com/shreeram-crm/v3/main.dart.js | grep -o "Pipeline board" | head -1
```

### 5. Browser
**Incognito** → https://aweliontech.com/shreeram-crm/v3/

You should see:
- Login pill: `UI build 2026-08-11-V3`
- Logo on login + sidebar
- Leads page titled **Pipeline board** with a gold **V3** badge
