#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
build_root="_build/js/release/build"
for entry in cmd/main/main.js cmd/web/web.js; do
  test -s "$build_root/$entry" || { echo "Missing release build: $entry" >&2; exit 1; }
done
mkdir -p _site/target/js/release/build/cmd/main _site/target/js/release/build/cmd/web
cp index.html sw.js _site/
cp -R web _site/
cp "$build_root/cmd/main/main.js" _site/target/js/release/build/cmd/main/
cp "$build_root/cmd/web/web.js" _site/target/js/release/build/cmd/web/
