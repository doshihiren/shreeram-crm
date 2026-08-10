#!/usr/bin/env bash
# Deploy cache-bust UI at /shreeram-crm/v2/ (bypasses old Flutter service worker)

set -euo pipefail
cd /var/www/shreeram-crm

git fetch origin
git checkout cursor/crm-implementation-523b
git pull origin cursor/crm-implementation-523b

echo "COMMIT=$(git rev-parse --short HEAD)"
test -f mobile/lib/features/meta/meta_connection_screen.dart && echo META_SOURCE_OK
grep -n 'base href="/shreeram-crm/v2/"' deploy/web-dist-v2/index.html
grep -n "UI build 2026-08-10-C" deploy/web-dist-v2/main.dart.js | head -1
grep -n "Command center" deploy/web-dist-v2/main.dart.js | head -1

rm -rf backend/public/app-v2
mkdir -p backend/public/app-v2
cp -a deploy/web-dist-v2/. backend/public/app-v2/

grep -n 'base href="/shreeram-crm/v2/"' backend/public/app-v2/index.html
grep -n "UI build 2026-08-10-C" backend/public/app-v2/main.dart.js | head -1
ls -la backend/public/app-v2/index.html backend/public/app-v2/main.dart.js

cd backend
php artisan config:clear
php artisan route:clear
php artisan config:cache

cat <<'EOF'

FILES READY at backend/public/app-v2

NEXT (required once): update Nginx locations using
  deploy/nginx/shreeram-crm.path.example.conf

1) Backup first:
   sudo mkdir -p /etc/nginx/backups
   sudo cp -a /etc/nginx/sites-enabled/aweliontech \
     /etc/nginx/backups/aweliontech.bak.$(date +%F-%H%M%S)

2) Edit:
   sudo nano /etc/nginx/sites-enabled/aweliontech
   - Keep API location /shreeram-crm/api/
   - Change UI to serve /shreeram-crm/v2/ from app-v2
   - Redirect /shreeram-crm/ -> /shreeram-crm/v2/

3) Test + reload:
   sudo nginx -t && sudo systemctl reload nginx

4) Open ONLY this URL (Incognito):
   https://aweliontech.com/shreeram-crm/v2/

Login: owner@shreeram.local / ChangeMeOwner1!
Expect: UI build 2026-08-10-C + Meta menu
EOF
