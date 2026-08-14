#!/usr/bin/env bash
# Patch live Nginx: stop no-store on /v3/ so Cloudflare can cache JS.
# Backs up the site file; rolls back automatically if nginx -t fails.
set -euo pipefail

NGINX_FILE="${NGINX_FILE:-/etc/nginx/sites-enabled/aweliontech}"

if [[ ! -f "$NGINX_FILE" ]]; then
  echo "ERROR: Nginx file not found: $NGINX_FILE"
  echo "Set NGINX_FILE=/path/to/site.conf and re-run."
  exit 1
fi

sudo mkdir -p /etc/nginx/backups
BACKUP="/etc/nginx/backups/aweliontech.bak.perf.$(date +%F-%H%M%S)"
sudo cp -a "$NGINX_FILE" "$BACKUP"
echo "Backup: $BACKUP"

TMP="$(mktemp)"
sudo cp -a "$NGINX_FILE" "$TMP"
sudo chown "$(id -u):$(id -g)" "$TMP"

python3 - "$TMP" <<'PY'
from pathlib import Path
import re, sys

path = Path(sys.argv[1])
text = path.read_text()

# 1) Inside /shreeram-crm/v3/ locations, replace no-store with short public cache
def fix_v3_block(m: re.Match) -> str:
    block = m.group(0)
    block2 = re.sub(
        r'add_header\s+Cache-Control\s+"no-store[^"]*"\s+always;',
        'add_header Cache-Control "public, max-age=60, must-revalidate" always;',
        block,
    )
    block2 = re.sub(
        r'add_header\s+Cache-Control\s+"no-cache[^"]*"\s+always;',
        'add_header Cache-Control "public, max-age=60, must-revalidate" always;',
        block2,
    )
    # Ensure gzip is on for the v3 location
    if "gzip on" not in block2:
        block2 = block2.replace(
            "index index.html;",
            "index index.html;\n    gzip on;\n    gzip_comp_level 6;\n    gzip_types application/javascript application/json text/css text/plain;",
            1,
        )
    return block2

text2, n = re.subn(
    r"location\s+\^~\s+/shreeram-crm/v3/\s*\{[\s\S]*?\n\}",
    fix_v3_block,
    text,
    count=1,
)
if n == 0:
    # try without ^~
    text2, n = re.subn(
        r"location\s+/shreeram-crm/v3/\s*\{[\s\S]*?\n\}",
        fix_v3_block,
        text,
        count=1,
    )

# 2) Insert dedicated long-cache location for main.dart.js if missing
needle = "location ^~ /shreeram-crm/v3/main.dart.js"
if needle not in text2 and "location ^~ /shreeram-crm/v3/" in text2:
    insert = '''
# ShreeRam perf: long-cache the big JS bundle (query-busted)
location ^~ /shreeram-crm/v3/main.dart.js {
    alias /var/www/shreeram-crm/backend/public/app-v3/main.dart.js;
    default_type application/javascript;
    gzip on;
    gzip_comp_level 6;
    gzip_types application/javascript text/javascript;
    add_header Cache-Control "public, max-age=2592000, immutable" always;
    access_log off;
}

location ^~ /shreeram-crm/v3/assets/ {
    alias /var/www/shreeram-crm/backend/public/app-v3/assets/;
    add_header Cache-Control "public, max-age=2592000, immutable" always;
    access_log off;
}

'''
    text2 = text2.replace(
        "location ^~ /shreeram-crm/v3/",
        insert + "location ^~ /shreeram-crm/v3/",
        1,
    )
    n += 1

if n == 0:
    print("ERROR: could not find /shreeram-crm/v3/ location to patch")
    sys.exit(2)

path.write_text(text2)
print(f"Patched OK (edits={n})")
PY

sudo cp -a "$TMP" "$NGINX_FILE"
rm -f "$TMP"

echo "---- nginx -t ----"
if ! sudo nginx -t; then
  echo "nginx -t FAILED — restoring backup"
  sudo cp -a "$BACKUP" "$NGINX_FILE"
  sudo nginx -t
  exit 1
fi
sudo systemctl reload nginx
echo "Nginx reloaded."

echo "---- Verify ----"
curl -sI "https://aweliontech.com/shreeram-crm/v3/main.dart.js" | tr -d '\r' | grep -iE 'HTTP/|cache-control|content-encoding|cf-cache' || true
curl -sI "https://aweliontech.com/shreeram-crm/v3/" | tr -d '\r' | grep -iE 'HTTP/|cache-control|cf-cache' || true
