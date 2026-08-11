#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_HOME="$(pwd)/flutter"
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$FLUTTER_HOME"
export PATH="$PATH:$FLUTTER_HOME/bin"

flutter doctor
flutter pub get
flutter build web --release

echo "Flutter web build complete"
