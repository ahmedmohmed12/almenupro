#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_HOME="$(pwd)/flutter"
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$FLUTTER_HOME"
export PATH="$PATH:$FLUTTER_HOME/bin"

flutter doctor
flutter pub get
flutter build web --release --output-dir build/web

echo "Flutter web build complete"

{
  "version": 2,
  "builds": [
    {
      "src": "frontend/**",
      "use": "@vercel/static-build"
    }
  ],
  "routes": [
    {
      "src": "/(.*)",
      "dest": "index.html"
    }
  ],
  "outputDirectory": "frontend/build/web"
}
