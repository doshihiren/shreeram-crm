#!/usr/bin/env bash
# One-command Nginx cutover: ShreeRam UI v2 -> v3
# Run on the VPS as a user with sudo.

set -euo pipefail

NGINX_FILE="${NGINX_FILE:-/etc/nginx/sites-enabled/aweliontech}"
REPO_ROOT="${REPO_ROOT:-/var/www/shreeram-crm}"
MARKER_BUILD="UI build 2026-08-11-V3"

if [[ ! -f "$NGINX_FILE" ]]; then
  echo "ERROR: Nginx file not found: $NGINX_FILE"
  exit 1
fi

if [[ ! -f "$REPO_ROOT/backend/public/app-v3/index.html" ]]; then
  echo "ERROR: app-v3 not deployed yet."
  echo "Run first:  cd $REPO_ROOT && bash deploy/FORCE_REFRESH_UI.sh"
  exit 1
fi

sudo mkdir -p /etc/nginx/backups
BACKUP="/etc/nginx/backups/aweliontech.bak.$(date +%F-%H%M%S)"
sudo cp -a "$NGINX_FILE" "$BACKUP"
echo "Backup: $BACKUP"

TMP="$(mktemp)"
sudo cp -a "$NGINX_FILE" "$TMP"
sudo chown "$(id -u):$(id -g)" "$TMP"

# Point UI serving + redirects from v2 -> v3
sed -i \
  -e 's|/shreeram-crm/v2/|/shreeram-crm/v3/|g' \
  -e 's|app-v2/|app-v3/|g' \
  -e 's|public/app-v2|public/app-v3|g' \
  "$TMP"

# Ensure /v2/ still redirects to /v3/ (bookmarks / cached links)
if ! grep -q 'location \^~ /shreeram-crm/v2/' "$TMP"; then
  python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
block = """
# Old v2 URL -> v3
location ^~ /shreeram-crm/v2/ {
    return 302 /shreeram-crm/v3/;
}
"""
needle = "location ^~ /shreeram-crm/v3/"
if needle in text and "location ^~ /shreeram-crm/v2/" not in text:
    text = text.replace(needle, block + needle, 1)
    path.write_text(text)
    print("Inserted /v2/ -> /v3/ redirect")
else:
    print("v2 redirect already present or v3 location missing (skip insert)")
PY
fi

# Sanity: must serve v3 UI, must not alias app-v2 anymore
if ! grep -q 'location \^~ /shreeram-crm/v3/' "$TMP"; then
  echo "ERROR: /shreeram-crm/v3/ location missing after patch. Restoring backup."
  sudo cp -a "$BACKUP" "$NGINX_FILE"
  rm -f "$TMP"
  exit 1
fi
if grep -q 'alias .*/app-v2/' "$TMP"; then
  echo "ERROR: still aliases app-v2 after patch. Restoring backup."
  sudo cp -a "$BACKUP" "$NGINX_FILE"
  rm -f "$TMP"
  exit 1
fi

sudo cp -a "$TMP" "$NGINX_FILE"
rm -f "$TMP"

echo "---- Nginx ShreeRam snippets ----"
sudo grep -n 'shreeram-crm' "$NGINX_FILE" | head -40 || true

echo "---- nginx -t ----"
sudo nginx -t
sudo systemctl reload nginx
echo "Nginx reloaded."

echo "---- Verify ----"
curl -sI https://aweliontech.com/shreeram-crm/ | tr -d '\r' | grep -iE 'HTTP/|Location' || true
curl -sI https://aweliontech.com/shreeram-crm/v2/ | tr -d '\r' | grep -iE 'HTTP/|Location' || true
curl -s https://aweliontech.com/shreeram-crm/v3/ | grep -o 'base href="[^"]*"' || true
curl -s https://aweliontech.com/shreeram-crm/v3/main.dart.js | grep -o "$MARKER_BUILD" | head -1 || true

cat <<EOF

DONE.
Open Incognito: https://aweliontech.com/shreeram-crm/v3/
Expect: $MARKER_BUILD + Pipeline board + logo

Rollback if needed:
  sudo cp -a $BACKUP $NGINX_FILE
  sudo nginx -t && sudo systemctl reload nginx
EOF
