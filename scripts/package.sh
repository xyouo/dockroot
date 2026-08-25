#!/usr/bin/env bash

set -euo pipefail

version="${VERSION:-0.7.0}"
version_code="${VERSION_CODE:-700}"
module_dir=build/module
output="dist/dockroot-v${version}.zip"

rm -rf "$module_dir"
mkdir -p "$module_dir" dist
cp -a module/. "$module_dir/"
cp README.md LICENSE "$module_dir/"

sed -i \
  -e "s|^version=.*|version=v${version}|" \
  -e "s|^versionCode=.*|versionCode=${version_code}|" \
  "$module_dir/module.prop"

(
  cd "$module_dir"
  zip -9r "../../$output" .
)

echo "$output"
