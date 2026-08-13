#!/usr/bin/env bash
set -euo pipefail

# Vercel frontend builds may run this from the repo root.
# The canonical script lives next to frontend/vercel.json.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../frontend/scripts/build.sh"
