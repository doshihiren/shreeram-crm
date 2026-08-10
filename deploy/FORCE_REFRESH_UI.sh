# Force-refresh UI on Contabo (run exactly)

cd /var/www/shreeram-crm
git fetch origin
git checkout cursor/crm-implementation-523b
git pull origin cursor/crm-implementation-523b

# Prove new code is on disk
git log -1 --oneline
test -f mobile/lib/features/meta/meta_connection_screen.dart && echo META_SOURCE_OK
grep -n "UI build 2026-08-10-C" deploy/web-dist/main.dart.js | head -1

# Replace served UI completely
rm -rf backend/public/app
mkdir -p backend/public/app
cp -a deploy/web-dist/. backend/public/app/

# Prove served files are new
grep -n "UI build 2026-08-10-C" backend/public/app/main.dart.js | head -1
grep -n "Meta Lead Ads" backend/public/app/main.dart.js | head -1
ls -la backend/public/app/index.html backend/public/app/main.dart.js

# Clear Laravel caches (API)
cd backend
php artisan config:clear
php artisan route:clear
php artisan config:cache

echo "DONE. Open https://aweliontech.com/shreeram-crm/?v=20260810c"
echo "Then hard refresh: Ctrl+Shift+R (or clear site data for aweliontech.com)"
echo "Login as OWNER: owner@shreeram.local"
echo "You should see pill: UI build 2026-08-10-C"
echo "Left/side menu should include Meta"
