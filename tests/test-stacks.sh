#!/usr/bin/env bash
# 测试会动态覆盖已 source 脚本中的适配函数。
# shellcheck disable=SC1091,SC2034,SC2317

set -euo pipefail

export DRCTL_SOURCE_ONLY=1
# shellcheck source=../module/bin/drctl
source module/bin/drctl

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
STATE_DIR="$temp_dir/state"
STACK_DIR="$STATE_DIR/stacks"
DATA_ROOT="$STATE_DIR/data"
RUNTIME_DIR="$STATE_DIR/bin"
VOLUME_DIR="$STATE_DIR/volumes"
MODDIR=module
AUTOSTART_FILE="$STATE_DIR/autostart.list"
mkdir -p "$STACK_DIR" "$RUNTIME_DIR" "$DATA_ROOT/openlist/rootfs"
: > "$AUTOSTART_FILE"
ensure_state() { mkdir -p "$STACK_DIR" "$DATA_ROOT"; }
load_config() { :; }

cat > "$STACK_DIR/openlist.conf" <<EOF
IMAGE=openlistteam/openlist:latest
AUTOSTART=1
VOLUME=$STATE_DIR/volumes/openlist:/opt/openlist/data
ENV=UMASK=022
CHECK_PORT=5244
HEALTH_URL=http://127.0.0.1:5244/
EOF

calls="$temp_dir/calls"
run_dockroot() { { printf 'run_dockroot'; printf ' <%s>' "$@"; printf '\n'; } >> "$calls"; }
pull_image() { printf 'pull_image <%s> <%s>\n' "$1" "$2" >> "$calls"; }
autostart_add() { printf '%s\n' "$1" >> "$AUTOSTART_FILE"; }
autostart_remove() { :; }
require_runtime() { :; }

apply_stack openlist
grep -F 'run_dockroot <run> <--renew> <-v>' "$calls"
grep -F "<$STATE_DIR/volumes/openlist:/opt/openlist/data>" "$calls"
grep -F '<-e> <UMASK=022>' "$calls"
grep -F '<openlist> <--> </bin/true>' "$calls"
if grep -F '<-c>' "$calls"; then
  echo 'apply 不应向 DockRoot 传入会被误解析的 -c' >&2
  exit 1
fi
grep -Fx 'openlist' "$AUTOSTART_FILE"
test -d "$STATE_DIR/volumes/openlist"

rm -rf "$DATA_ROOT/openlist/rootfs"
apply_stack openlist
grep -F 'pull_image <openlistteam/openlist:latest> <openlist>' "$calls"

mkdir -p "$DATA_ROOT/incomplete"
cleanup_state > "$temp_dir/preview"
test -d "$DATA_ROOT/incomplete"
grep -F "$DATA_ROOT/incomplete" "$temp_dir/preview"
cleanup_state --yes >/dev/null
test ! -e "$DATA_ROOT/incomplete"

DATA_ROOT=/
if cleanup_state --yes >/dev/null 2>&1; then
  echo '危险 DATA_ROOT 不应允许清理' >&2
  exit 1
fi
DATA_ROOT="$STATE_DIR/data"

rm -f "$STACK_DIR/qinglong.conf"
create_stack qinglong 5900
grep -Fx 'IMAGE=whyour/qinglong:latest' "$STACK_DIR/qinglong.conf"
grep -Fx 'VOLUME=/data/adb/dockroot/volumes/qinglong:/ql/data' "$STACK_DIR/qinglong.conf"
grep -Fx 'ENV=QlPort=5900' "$STACK_DIR/qinglong.conf"
grep -Fx 'AUTOSTART=1' "$STACK_DIR/qinglong.conf"
grep -Fx 'ENV=QlGrpcPort=5501' "$STACK_DIR/qinglong.conf"
grep -Fx 'CHECK_PORT=5900' "$STACK_DIR/qinglong.conf"
grep -Fx 'CHECK_PORT=5501' "$STACK_DIR/qinglong.conf"
grep -Fx 'HEALTH_URL=http://127.0.0.1:5900/api/health' "$STACK_DIR/qinglong.conf"

sed -i 's/ENV=QlPort=5900/ENV=QlPort=5901/' "$STACK_DIR/qinglong.conf"
migrate_stack qinglong
grep -Fx 'CHECK_PORT=5901' "$STACK_DIR/qinglong.conf"
grep -Fx 'HEALTH_URL=http://127.0.0.1:5901/api/health' "$STACK_DIR/qinglong.conf"
if grep -Fx 'CHECK_PORT=5900' "$STACK_DIR/qinglong.conf"; then
  echo '青龙端口变化后不应保留旧检查端口' >&2
  exit 1
fi

rm -f "$STACK_DIR/cloudflared.conf"
create_stack cloudflared
grep -Fx 'IMAGE=cloudflare/cloudflared:latest' "$STACK_DIR/cloudflared.conf"
grep -Fx 'AUTOSTART=1' "$STACK_DIR/cloudflared.conf"
grep -Fx 'VOLUME=/data/adb/dockroot/volumes/cloudflared:/etc/cloudflared:ro' "$STACK_DIR/cloudflared.conf"
grep -Fx 'REQUIRED_FILE=/data/adb/dockroot/volumes/cloudflared/token' "$STACK_DIR/cloudflared.conf"
grep -Fx 'APPLY_COMMAND=/usr/local/bin/cloudflared' "$STACK_DIR/cloudflared.conf"
grep -Fx 'APPLY_ARG=version' "$STACK_DIR/cloudflared.conf"
grep -Fx 'COMMAND=/usr/local/bin/cloudflared' "$STACK_DIR/cloudflared.conf"
grep -Fx 'ARG=tunnel' "$STACK_DIR/cloudflared.conf"
grep -Fx 'ARG=--token-file' "$STACK_DIR/cloudflared.conf"
grep -Fx 'ARG=/etc/cloudflared/token' "$STACK_DIR/cloudflared.conf"
grep -Fx 'CHECK_PORT=49312' "$STACK_DIR/cloudflared.conf"
grep -Fx 'READY_URL=http://127.0.0.1:49312/ready' "$STACK_DIR/cloudflared.conf"

rm -f "$STACK_DIR/cloudflared.conf"
create_stack cloudflared 49313
grep -Fx 'CHECK_PORT=49313' "$STACK_DIR/cloudflared.conf"
grep -Fx 'ARG=127.0.0.1:49313' "$STACK_DIR/cloudflared.conf"
grep -Fx 'READY_URL=http://127.0.0.1:49313/ready' "$STACK_DIR/cloudflared.conf"

# 自定义命令必须逐参数传递，并以 -- 隔开 DockRoot 参数。
sed -i "s|/data/adb/dockroot|$STATE_DIR|g" "$STACK_DIR/cloudflared.conf"
mkdir -p "$DATA_ROOT/cloudflared/rootfs" "$STATE_DIR/volumes/cloudflared"
printf '%s\n' 'test-token' | set_stack_secret cloudflared >/dev/null
test "$(stat -c '%a' "$STATE_DIR/volumes/cloudflared/token")" = 644
if grep -F 'test-token' "$STACK_DIR/cloudflared.conf"; then
  echo 'Tunnel token 不应写入 Stack 配置' >&2
  exit 1
fi
: > "$calls"
apply_stack cloudflared
grep -F 'run_dockroot <run> <--renew>' "$calls"
grep -F '<cloudflared> <--> </usr/local/bin/cloudflared> <version>' "$calls"
if grep -F 'test-token' "$calls"; then
  echo 'Tunnel token 不应出现在 DockRoot 命令参数中' >&2
  exit 1
fi

cat > "$STACK_DIR/invalid.conf" <<'EOF'
IMAGE=example/invalid:latest
ARG=--flag
EOF
mkdir -p "$DATA_ROOT/invalid/rootfs"
if apply_stack invalid >/dev/null 2>&1; then
  echo 'ARG 缺少 COMMAND 时应拒绝配置' >&2
  exit 1
fi

cat > "$STACK_DIR/invalid.conf" <<'EOF'
IMAGE=example/invalid:latest
COMMAND=relative-command
EOF
if apply_stack invalid >/dev/null 2>&1; then
  echo '相对 COMMAND 应被拒绝' >&2
  exit 1
fi

cat > "$STACK_DIR/invalid.conf" <<'EOF'
IMAGE=example/invalid:latest
COMMAND=/bin/first
COMMAND=/bin/second
EOF
if apply_stack invalid >/dev/null 2>&1; then
  echo '重复 COMMAND 应被拒绝' >&2
  exit 1
fi

cat > "$STACK_DIR/invalid.conf" <<'EOF'
IMAGE=example/invalid:latest
COMMAND=/bin/tool
ARG=
EOF
if apply_stack invalid >/dev/null 2>&1; then
  echo '空 ARG 应被拒绝' >&2
  exit 1
fi

# 生命周期：必须等待旧进程退出，并验证端口、卷和 HTTP 健康后才成功。
running=1
run_failed=0
run_dockroot() {
  { printf 'run_dockroot'; printf ' <%s>' "$@"; printf '\n'; } >> "$calls"
  case "${1:-} ${2:-}" in
    'stop openlist') running=0 ;;
    'run -d') [ "$run_failed" = 0 ] || return 1; running=1 ;;
  esac
  return 0
}
container_pids() { if [ "$running" = 1 ]; then echo 1234; fi; }
port_is_listening() { [ "$running" = 1 ]; }
port_listener() { if [ "$running" = 1 ]; then echo listener; fi; }
volume_is_mounted() { [ "$running" = 1 ]; }
health_url_ok() { [ "$running" = 1 ]; }
sleep() { :; }

start_stack openlist

running=0
: > "$calls"
health_url_ok() { return 1; }
start_stack cloudflared
grep -F 'run_dockroot <run> <-d> <cloudflared> <--> </usr/local/bin/cloudflared> <tunnel> <--no-autoupdate> <--loglevel> <info> <--metrics> <127.0.0.1:49313> <run> <--token-file> </etc/cloudflared/token>' "$calls"

cat > "$STACK_DIR/args.conf" <<'EOF'
IMAGE=example/args:latest
COMMAND=/bin/tool
ARG=--label=value with space
EOF
mkdir -p "$DATA_ROOT/args/rootfs"
running=0
: > "$calls"
start_stack args
grep -F 'run_dockroot <run> <-d> <args> <--> </bin/tool> <--label=value with space>' "$calls"

rm -f "$STATE_DIR/volumes/cloudflared/token"
running=1
if start_stack cloudflared >/dev/null 2>&1; then
  echo '缺少 Tunnel token 时不应启动 cloudflared' >&2
  exit 1
fi
if [ "$running" != 1 ]; then
  echo '缺少 Tunnel token 时不应停止原有 cloudflared 进程' >&2
  exit 1
fi

run_failed=1
if start_stack openlist >/dev/null 2>&1; then
  echo '底层启动失败时 start_stack 不应返回成功' >&2
  exit 1
fi

running=1
run_failed=0
container_pids() { echo 1234; }
if stop_stack openlist >/dev/null 2>&1; then
  echo '旧进程不退出时 stop_stack 不应返回成功' >&2
  exit 1
fi
