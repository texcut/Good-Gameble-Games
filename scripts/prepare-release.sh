#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/release_source.py
bash scripts/build-app.sh release
python3 scripts/package_release.py
