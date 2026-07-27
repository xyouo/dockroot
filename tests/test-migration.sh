#!/usr/bin/env bash

set -euo pipefail

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

MIGRATOR=module/bin/migrate-module-id
ADB_DIR="$ROOT/adb"
NEW_MODPATH="$ADB_DIR/modules_update/dockroot"
STATE_DIR="$ADB_DIR/dockroot"

make_module() {
  module_dir=$1
  module_id=$2
  mkdir -p "$module_dir"
  printf 'id=%s\n' "$module_id" > "$module_dir/module.prop"
}

assert_file() {
  test -f "$1" || {
    echo "缺少文件：$1" >&2
    exit 1
  }
}

assert_missing() {
  test ! -e "$1" || {
    echo "不应存在：$1" >&2
    exit 1
  }
}

mkdir -p "$ADB_DIR/modules" "$ADB_DIR/modules_update"
make_module "$NEW_MODPATH" dockroot

result="$(sh "$MIGRATOR" "$NEW_MODPATH" "$ADB_DIR")"
test "$result" = fresh
assert_missing "$ADB_DIR/modules/dockroot_ksu"

mkdir -p \
  "$STATE_DIR/bin" \
  "$STATE_DIR/data/alpine/rootfs" \
  "$STATE_DIR/stacks" \
  "$STATE_DIR/volumes/openlist" \
  "$STATE_DIR/logs"
printf 'AUTO_START=1\n' > "$STATE_DIR/config.env"
printf 'openlist\n' > "$STATE_DIR/autostart.list"
printf 'runtime\n' > "$STATE_DIR/bin/DockRoot"
printf 'rootfs\n' > "$STATE_DIR/data/alpine/rootfs/sentinel"
printf 'stack\n' > "$STATE_DIR/stacks/openlist.conf"
printf 'volume\n' > "$STATE_DIR/volumes/openlist/sentinel"
state_before="$(find "$STATE_DIR" -type f -print0 | sort -z | xargs -0 sha256sum)"

LEGACY_ACTIVE="$ADB_DIR/modules/dockroot_ksu"
LEGACY_UPDATE="$ADB_DIR/modules_update/dockroot_ksu"
make_module "$LEGACY_ACTIVE" dockroot_ksu
printf 'keep-active\n' > "$LEGACY_ACTIVE/sentinel"

result="$(sh "$MIGRATOR" "$NEW_MODPATH" "$ADB_DIR")"
test "$result" = migrated
assert_file "$LEGACY_ACTIVE/remove"
assert_file "$LEGACY_ACTIVE/disable"
assert_file "$LEGACY_ACTIVE/.dockroot-migration-disable"
assert_file "$LEGACY_ACTIVE/sentinel"
assert_missing "$NEW_MODPATH/disable"
assert_missing "$NEW_MODPATH/remove"

result="$(sh "$MIGRATOR" "$NEW_MODPATH" "$ADB_DIR")"
test "$result" = migrated
assert_missing "$NEW_MODPATH/disable"

make_module "$LEGACY_UPDATE" dockroot_ksu
printf 'keep-update\n' > "$LEGACY_UPDATE/sentinel"
result="$(sh "$MIGRATOR" "$NEW_MODPATH" "$ADB_DIR")"
test "$result" = migrated
assert_file "$LEGACY_UPDATE/remove"
assert_file "$LEGACY_UPDATE/disable"
assert_file "$LEGACY_UPDATE/sentinel"

state_after="$(find "$STATE_DIR" -type f -print0 | sort -z | xargs -0 sha256sum)"
test "$state_before" = "$state_after"

rm -f \
  "$LEGACY_ACTIVE/.dockroot-migration-disable" \
  "$NEW_MODPATH/disable"
result="$(sh "$MIGRATOR" "$NEW_MODPATH" "$ADB_DIR")"
test "$result" = migrated-disabled
assert_file "$NEW_MODPATH/disable"
assert_missing "$NEW_MODPATH/remove"

BAD_ROOT="$ROOT/bad-adb"
BAD_NEW="$BAD_ROOT/modules_update/dockroot"
BAD_OLD="$BAD_ROOT/modules/dockroot_ksu"
make_module "$BAD_NEW" dockroot
make_module "$BAD_OLD" unrelated_module
if sh "$MIGRATOR" "$BAD_NEW" "$BAD_ROOT" >/dev/null 2>&1; then
  echo '身份不匹配的旧模块不应迁移' >&2
  exit 1
fi
assert_missing "$BAD_OLD/remove"
assert_missing "$BAD_OLD/disable"

test -f "$STATE_DIR/config.env"
test -f "$STATE_DIR/data/alpine/rootfs/sentinel"
test -f "$STATE_DIR/stacks/openlist.conf"
test -f "$STATE_DIR/volumes/openlist/sentinel"
