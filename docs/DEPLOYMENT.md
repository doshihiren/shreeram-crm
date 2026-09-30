# Demo deploy — aweliontech.com/shreeram-crm

**Isolation rules:** only use `/var/www/shreeram-crm` and database `shreeram_crm`.  
Do not modify other projects, databases, containers, or unrelated Nginx sites beyond adding the dedicated `location` blocks for this path.

## Prerequisites (already done on VPS)

- Code checkout: `/var/www/shreeram-crm`
- MySQL DB/user: `shreeram_crm` / `shreeram_crm_user`
- Local secrets file (not in Git): `/var/www/shreeram-crm/.env.local.db`

## 1) Pull latest code

```bash
cd /var/www/shreeram-crm
git fetch origin
git checkout main   # or the approved feature branch
git pull
```

## 2) Backend setup

```bash
cd /var/www/shreeram-crm/backend
composer install --no-dev --optimize-autoloader

cp -n .env.example .env

# IMPORTANT: DB_PASSWORD must be set (error "using password: NO" means it is empty).
# Load from the local secrets file created earlier:
set -a
source /var/www/shreeram-crm/.env.local.db
set +a

# Write/merge into .env (edit with nano if you prefer)
grep -q '^DB_CONNECTION=' .env && sed -i 's/^DB_CONNECTION=.*/DB_CONNECTION=mysql/' .env || echo 'DB_CONNECTION=mysql' >> .env
sed -i "s/^DB_HOST=.*/DB_HOST=127.0.0.1/" .env || true
sed -i "s/^# DB_HOST=.*/DB_HOST=127.0.0.1/" .env || true
sed -i "s/^DB_PORT=.*/DB_PORT=3306/" .env || true
sed -i "s/^# DB_PORT=.*/DB_PORT=3306/" .env || true
sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env
sed -i "s/^# DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env
sed -i "s/^# DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env
# Ensure password line exists and is set
grep -q '^DB_PASSWORD=' .env || echo 'DB_PASSWORD=' >> .env
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env

# Demo URL
sed -i 's|^APP_URL=.*|APP_URL=https://aweliontech.com/shreeram-crm|' .env
grep -q '^ASSET_URL=' .env || echo 'ASSET_URL=https://aweliontech.com/shreeram-crm' >> .env
sed -i 's|^ASSET_URL=.*|ASSET_URL=https://aweliontech.com/shreeram-crm|' .env
sed -i 's/^SESSION_DRIVER=.*/SESSION_DRIVER=file/' .env
sed -i 's/^CACHE_STORE=.*/CACHE_STORE=file/' .env
sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=sync/' .env
sed -i 's/^APP_ENV=.*/APP_ENV=production/' .env
sed -i 's/^APP_DEBUG=.*/APP_DEBUG=false/' .env

# Verify password is present (should print YES)
php -r "require 'vendor/autoload.php'; \$d=file('.env'); foreach(\$d as \$l){ if(str_starts_with(trim(\$l),'DB_PASSWORD=')){ echo (strlen(trim(substr(trim(\$l),12)))?'YES':'NO'), PHP_EOL; } }"

php artisan key:generate --force
php artisan migrate --force
php artisan db:seed --force
php artisan config:cache
php artisan route:cache

sudo chown -R www-data:www-data storage bootstrap/cache
sudo chmod -R ug+rwx storage bootstrap/cache
```

Default seeded users (change immediately after first login):

| Role | Email | Password |
|------|-------|----------|
| OWNER | owner@shreeram.local | ChangeMeOwner1! |
| ADMIN | admin@shreeram.local | ChangeMeAdmin1! |
| SALES | sales@shreeram.local | ChangeMeSales1! |

## 3) Flutter web (no Flutter install needed on VPS)

Prebuilt web assets ship in `deploy/web-dist/` (API pointed at this demo path).

```bash
mkdir -p /var/www/shreeram-crm/backend/public/app
rm -rf /var/www/shreeram-crm/backend/public/app/*
cp -a /var/www/shreeram-crm/deploy/web-dist/. /var/www/shreeram-crm/backend/public/app/
```

Optional (only if you want to rebuild on a Flutter machine):

```bash
cd /var/www/shreeram-crm/mobile
flutter pub get
flutter build web --base-href /shreeram-crm/ \
  --dart-define=API_BASE_URL=https://aweliontech.com/shreeram-crm/api/v1
cp -a build/web/. /var/www/shreeram-crm/backend/public/app/
```

## 4) Nginx path routing (careful)

Use the example at `deploy/nginx/shreeram-crm.path.example.conf`.

1. Identify the **existing** `aweliontech.com` server block (do not create a conflicting duplicate).
2. Add only the `location` blocks for `/shreeram-crm`.
3. Adjust the PHP-FPM socket path to match this server (`ls /run/php/`).
4. Test and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

If `aweliontech.com` is currently handled by another app (Node/etc.) that catches all routes, the new `location ^~ /shreeram-crm` blocks must be added **in that same server** with higher priority (`^~`) so `/shreeram-crm` is not forwarded to the other app.

## 5) Smoke test

```bash
curl -s https://aweliontech.com/shreeram-crm/api/v1/lead-stages
# expect 401 unauthenticated JSON (route exists)

curl -s -X POST https://aweliontech.com/shreeram-crm/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"email":"owner@shreeram.local","password":"ChangeMeOwner1!"}'
```

Open: https://aweliontech.com/shreeram-crm/

## Meta webhook URL

`https://aweliontech.com/shreeram-crm/api/v1/meta/webhook`

Configure verify token via Owner/Admin API `POST /api/v1/meta/connection` (token stays server-side).

## Rollback

Remove only the `/shreeram-crm` location blocks and/or stop using this directory. Do not delete other project paths or databases.
