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

cp .env.example .env
# Merge DB values from /var/www/shreeram-crm/.env.local.db into .env
# Set:
#   APP_NAME=ShreeRamCRM
#   APP_URL=https://aweliontech.com/shreeram-crm
#   ASSET_URL=https://aweliontech.com/shreeram-crm
#   DB_CONNECTION=mysql
#   DB_HOST=127.0.0.1
#   DB_PORT=3306
#   DB_DATABASE=shreeram_crm
#   DB_USERNAME=shreeram_crm_user
#   DB_PASSWORD=...
#   SESSION_DRIVER=file
#   CACHE_STORE=file
#   QUEUE_CONNECTION=sync

php artisan key:generate
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

## 3) Flutter web build (on a machine with Flutter, or on VPS if installed)

```bash
cd /var/www/shreeram-crm/mobile
flutter pub get
flutter build web --base-href /shreeram-crm/ \
  --dart-define=API_BASE_URL=https://aweliontech.com/shreeram-crm/api/v1

mkdir -p /var/www/shreeram-crm/backend/public/app
rsync -a --delete build/web/ /var/www/shreeram-crm/backend/public/app/
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
