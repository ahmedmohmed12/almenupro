#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$FRONTEND_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/pubspec.yaml" ]; then
  PROJECT_ROOT="$REPO_ROOT"
elif [ -f "$FRONTEND_DIR/pubspec.yaml" ]; then
  PROJECT_ROOT="$FRONTEND_DIR"
else
  echo "Could not find pubspec.yaml (looked in $REPO_ROOT and $FRONTEND_DIR)" >&2
  exit 1
fi

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_HOME="${FLUTTER_HOME:-$PROJECT_ROOT/.flutter}"
# Production API. Do not inherit a stale preview API_BASE_URL.
API_BASE_URL="https://backend.u-menus.com/api"
DIST_DIR="$FRONTEND_DIR/dist"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Installing Flutter ($FLUTTER_VERSION)..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

cd "$PROJECT_ROOT"
flutter config --enable-web --no-analytics
flutter precache --web
flutter pub get
flutter build web \
  --release \
  --dart-define=API_BASE_URL="$API_BASE_URL"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
cp -R "$PROJECT_ROOT/build/web/." "$DIST_DIR/"

if [ -f "$FRONTEND_DIR/landing/index.html" ]; then
  cp "$FRONTEND_DIR/landing/index.html" "$DIST_DIR/landing.html"
  if [ -f "$DIST_DIR/index.html" ]; then
    mv "$DIST_DIR/index.html" "$DIST_DIR/app.html"
  fi
  cp "$FRONTEND_DIR/landing/index.html" "$DIST_DIR/index.html"
fi
if [ -f "$FRONTEND_DIR/landing/customers.html" ]; then
  cp "$FRONTEND_DIR/landing/customers.html" "$DIST_DIR/customers.html"
fi
if [ -f "$FRONTEND_DIR/landing/smart-seller.html" ]; then
  cp "$FRONTEND_DIR/landing/smart-seller.html" "$DIST_DIR/smart-seller.html"
fi
if [ -f "$FRONTEND_DIR/landing/create.html" ]; then
  cp "$FRONTEND_DIR/landing/create.html" "$DIST_DIR/create.html"
fi
if [ -f "$FRONTEND_DIR/landing/i18n.js" ]; then
  cp "$FRONTEND_DIR/landing/i18n.js" "$DIST_DIR/i18n.js"
fi
if [ -f "$PROJECT_ROOT/web/logo.png" ]; then
  cp "$PROJECT_ROOT/web/logo.png" "$DIST_DIR/logo.png"
elif [ -f "$FRONTEND_DIR/landing/logo.png" ]; then
  cp "$FRONTEND_DIR/landing/logo.png" "$DIST_DIR/logo.png"
fi

echo "Flutter web build complete: $DIST_DIR"
