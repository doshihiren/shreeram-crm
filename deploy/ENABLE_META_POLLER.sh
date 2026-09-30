#!/usr/bin/env bash
# Enable Laravel scheduler (meta:poll-leads safety net every 5 min).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/var/www/shreeram-crm}"
BACKEND="$REPO_ROOT/backend"
CRON_LINE="* * * * * cd $BACKEND && php artisan schedule:run >> /dev/null 2>&1"

if [[ ! -d "$BACKEND" ]]; then
  echo "ERROR: backend not found at $BACKEND"
  exit 1
fi

echo "Installing scheduler cron for $(whoami)…"
(crontab -l 2>/dev/null | grep -v 'artisan schedule:run' || true; echo "$CRON_LINE") | crontab -
echo "Current crontab:"
crontab -l | grep schedule:run || true

echo
echo "Pull latest + smoke poll once:"
cd "$REPO_ROOT"
git pull origin cursor/crm-implementation-523b || true
cd "$BACKEND"
php artisan meta:check-logs || true
php artisan meta:subscribe-page || true
php artisan meta:poll-leads --limit=40 --hours=72 || true

echo
echo "Done. Cron will call schedule:run every minute; meta:poll-leads runs every 5 minutes."
echo "Docs: docs/META_WEBHOOK_TROUBLESHOOTING.md"
