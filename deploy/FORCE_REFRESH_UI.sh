#!/usr/bin/env bash
# Deploy cache-bust UI at /shreeram-crm/v3/ (new path = no old Flutter SW / CDN cache)

set -euo pipefail
cd /var/www/shreeram-crm

git fetch origin
git checkout cursor/crm-implementation-523b
git pull origin cursor/crm-implementation-523b

echo "COMMIT=$(git rev-parse --short HEAD)"
test -f deploy/web-dist-v3/index.html
grep -n 'base href="/shreeram-crm/v3/"' deploy/web-dist-v3/index.html
grep -n "UI build 2026-08-11-V3" deploy/web-dist-v3/main.dart.js | head -1
grep -n "Pipeline board" deploy/web-dist-v3/main.dart.js | head -1

rm -rf backend/public/app-v3
mkdir -p backend/public/app-v3
cp -a deploy/web-dist-v3/. backend/public/app-v3/

grep -n 'base href="/shreeram-crm/v3/"' backend/public/app-v3/index.html
grep -n "UI build 2026-08-11-V3" backend/public/app-v3/main.dart.js | head -1
ls -la backend/public/app-v3/index.html backend/public/app-v3/main.dart.js

cd backend
php artisan config:clear
php artisan route:clear
php artisan config:cache

cat <<'EOF'

FILES READY at backend/public/app-v3

NEXT (required once): update Nginx using
  deploy/nginx/shreeram-crm.path.example.conf
  docs/NGINX_V3_CUTOVER.md

1) Backup first:
   sudo mkdir -p /etc/nginx/backups
   sudo cp -a /etc/nginx/sites-enabled/aweliontech \
     /etc/nginx/backups/aweliontech.bak.$(date +%F-%H%M%S)

2) Edit:
   sudo nano /etc/nginx/sites-enabled/aweliontech
   - Keep API location /shreeram-crm/api/
   - Serve /shreeram-crm/v3/ from app-v3
   - Redirect /shreeram-crm/ and /shreeram-crm/v2/ -> /shreeram-crm/v3/

3) Test + reload:
   sudo nginx -t && sudo systemctl reload nginx

4) Open ONLY this URL (Incognito / hard refresh):
   https://aweliontech.com/shreeram-crm/v3/

Login: owner@shreeram.local / ChangeMeOwner1!
Expect: UI build 2026-08-11-V3 + "Pipeline board" + logo
EOF
