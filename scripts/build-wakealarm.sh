#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mkdir -p build/go-cache module/bin
GOOS=android GOARCH=arm64 CGO_ENABLED=0 GOCACHE="$repo_root/build/go-cache" \
  go build -trimpath -ldflags='-s -w' -o module/bin/wakealarm ./tools/wakealarm
chmod 0755 module/bin/wakealarm
