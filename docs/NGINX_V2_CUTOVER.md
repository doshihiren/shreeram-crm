# One-time Nginx patch for ShreeRam v2 UI

## Why
Old Flutter service worker under `/shreeram-crm/` is still trapping some browsers on the first UI build.
New UI is published under `/shreeram-crm/v2/` (new scope = no old cache).

## After `bash deploy/FORCE_REFRESH_UI.sh`

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

Replace the existing ShreeRam **UI** locations (keep the API block) with the contents of:

`deploy/nginx/shreeram-crm.path.example.conf`

Critical parts:
- API stays at `/shreeram-crm/api/`
- `/shreeram-crm` and `/shreeram-crm/` redirect to `/shreeram-crm/v2/`
- `/shreeram-crm/v2/` aliases to `/var/www/shreeram-crm/backend/public/app-v2/`

### 3. Reload
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 4. Verify
```bash
curl -sI https://aweliontech.com/shreeram-crm/ | head -5
# expect 302 to /shreeram-crm/v2/

curl -s https://aweliontech.com/shreeram-crm/v2/ | grep -o 'base href="[^"]*"'
# expect base href="/shreeram-crm/v2/"

curl -s https://aweliontech.com/shreeram-crm/v2/main.dart.js | grep -o "UI build 2026-08-10-C" | head -1
```

### 5. Browser
Incognito → https://aweliontech.com/shreeram-crm/v2/
