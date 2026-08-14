# ShreeRam CRM

Real Estate Lead Management CRM (Android / iOS / Web).

## Stack

- **Frontend:** Flutter (`mobile/`)
- **Backend:** Laravel REST API (`backend/`)
- **Database:** MySQL

## Demo URL

https://aweliontech.com/shreeram-crm

## Quick links

- Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Deployment (VPS isolation): [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)
- Env template: [`.env.example`](.env.example) and `backend/.env.example`

## Local backend

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
# configure DB, then:
php artisan migrate --seed
php artisan serve
```

API base: `http://127.0.0.1:8000/api/v1`

Seeded logins (change after first deploy):

- OWNER `owner@shreeram.local` / `ChangeMeOwner1!`
- ADMIN `admin@shreeram.local` / `ChangeMeAdmin1!`
- SALES `sales@shreeram.local` / `ChangeMeSales1!`

## Flutter

```bash
cd mobile
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Web build for demo path:

```bash
flutter build web --base-href /shreeram-crm/ \
  --dart-define=API_BASE_URL=https://aweliontech.com/shreeram-crm/api/v1
```

## Security

Never commit `.env`, Meta tokens, or `.env.local.db`.  
Meta credentials stay server-side only.
