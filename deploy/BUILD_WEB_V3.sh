#!/usr/bin/env bash
# Rebuild Flutter web (v3) with load-time optimizations and copy into deploy/web-dist-v3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mobile"

BUILD_ID="${BUILD_ID:-$(date +%Y%m%d-%H%M%S)}"
API_BASE_URL="${API_BASE_URL:-https://aweliontech.com/shreeram-crm/api/v1}"

echo "Building Flutter web BUILD_ID=$BUILD_ID"
flutter pub get
flutter build web --release \
  --base-href /shreeram-crm/v3/ \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  -O4 \
  --pwa-strategy=none \
  --web-resources-cdn \
  --no-source-maps

# Stamp cache-buster into bootstrap + HTML references
sed -i "s/BUILD_ID_PLACEHOLDER/${BUILD_ID}/g" build/web/flutter_bootstrap.js
sed -i "s|href=\"main.dart.js\"|href=\"main.dart.js?v=${BUILD_ID}\"|g" build/web/index.html
sed -i "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=${BUILD_ID}\"|g" build/web/index.html

# Ensure splash logo is present
cp -f web/splash-logo.jpg build/web/splash-logo.jpg 2>/dev/null || \
  cp -f assets/brand/logo-shreeram-developer.jpg build/web/splash-logo.jpg

# Prefer Google CDN CanvasKit — drop local ~20MB canvaskit from deploy artifact
rm -rf build/web/canvaskit

# Ship into repo deploy folder
rm -rf "$ROOT/deploy/web-dist-v3"
mkdir -p "$ROOT/deploy/web-dist-v3"
cp -a build/web/. "$ROOT/deploy/web-dist-v3/"

# Sanity
grep -q 'base href="/shreeram-crm/v3/"' "$ROOT/deploy/web-dist-v3/index.html"
grep -q "UI build 2026-08-14-DRAGALL" "$ROOT/deploy/web-dist-v3/main.dart.js"
grep -q "$BUILD_ID" "$ROOT/deploy/web-dist-v3/flutter_bootstrap.js"
grep -q "main.dart.js?v=${BUILD_ID}" "$ROOT/deploy/web-dist-v3/index.html"
test ! -d "$ROOT/deploy/web-dist-v3/canvaskit"

echo "OK -> deploy/web-dist-v3 (BUILD_ID=$BUILD_ID)"
ls -lah "$ROOT/deploy/web-dist-v3/main.dart.js" "$ROOT/deploy/web-dist-v3/flutter_bootstrap.js" "$ROOT/deploy/web-dist-v3/index.html"
du -sh "$ROOT/deploy/web-dist-v3"
