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
grep -n "UI build 2026-08-13-V3" deploy/web-dist-v3/main.dart.js | head -1
grep -n "Pipeline board\|Sales command center\|All statuses" deploy/web-dist-v3/main.dart.js | head -1

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

NEXT (one command — no manual nano):
  sudo bash deploy/CUTOVER_NGINX_V3.sh

Then open Incognito:
  https://aweliontech.com/shreeram-crm/v3/

Login: owner@shreeram.local / ChangeMeOwner1!
Expect: UI build 2026-08-11-V3 + "Pipeline board" + logo
EOF
