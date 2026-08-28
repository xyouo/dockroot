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
LOCK_DIR="$STATE_DIR/locks"
PROC_ROOT="$temp_dir/proc"
POWER_ROOT="$temp_dir/power"
RUNTIME_DIR="$STATE_DIR/bin"
VOLUME_DIR="$STATE_DIR/volumes"
MODDIR=module
AUTOSTART_FILE="$STATE_DIR/autostart.list"
mkdir -p "$STACK_DIR" "$RUNTIME_DIR" "$DATA_ROOT/openlist/rootfs" "$LOCK_DIR" "$PROC_ROOT/sys/kernel/random" "$POWER_ROOT"
touch "$POWER_ROOT/wake_lock" "$POWER_ROOT/wake_unlock"
printf 'test-boot-id\n' > "$PROC_ROOT/sys/kernel/random/boot_id"
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

# DockRoot ps 看不到时，仍应通过 /proc/<pid>/root 识别容器孤儿进程。
mkdir -p "$PROC_ROOT/4242" "$PROC_ROOT/5252" "$DATA_ROOT/other/rootfs"
ln -s "$DATA_ROOT/openlist/rootfs" "$PROC_ROOT/4242/root"
ln -s "$DATA_ROOT/other/rootfs" "$PROC_ROOT/5252/root"
test "$(container_rootfs_pids openlist)" = 4242
test "$(container_all_pids openlist)" = 4242
rm -rf "$PROC_ROOT/4242" "$PROC_ROOT/5252"

# 同一 Stack 已有生命周期操作时，第二个操作必须被拒绝。
mkdir -p "$LOCK_DIR/openlist.lock"
printf '123 test-boot-id\n' > "$LOCK_DIR/openlist.lock/owner"
stack_lock_owner_active() { return 0; }
if run_stack_locked true openlist >/dev/null 2>&1; then
  echo '活跃的容器操作锁不应被绕过' >&2
  exit 1
fi
stack_lock_owner_active() { return 1; }
run_stack_locked true openlist
test ! -e "$LOCK_DIR/openlist.lock"

acquire_wakelock
grep -Fx "$WAKELOCK_TAG" "$POWER_ROOT/wake_lock"
release_wakelock
grep -Fx "$WAKELOCK_TAG" "$POWER_ROOT/wake_unlock"

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

rm -f "$STACK_DIR/demo.conf"
init_stack demo alpine:latest
grep -Fx 'IMAGE=alpine:latest' "$STACK_DIR/demo.conf"
grep -Fx 'AUTOSTART=0' "$STACK_DIR/demo.conf"
grep -Fx 'HOSTNAME=demo' "$STACK_DIR/demo.conf"
grep -F "# VOLUME=$VOLUME_DIR/demo:/容器内路径" "$STACK_DIR/demo.conf"
if init_stack demo busybox:latest >/dev/null 2>&1; then
  echo '通用初始化不应覆盖现有配置' >&2
  exit 1
fi
if init_stack invalid 'bad image' >/dev/null 2>&1; then
  echo '镜像名称包含空白时应拒绝初始化' >&2
  exit 1
fi
if init_stack extra alpine:latest unexpected >/dev/null 2>&1; then
  echo '通用初始化不应静默忽略多余参数' >&2
  exit 1
fi

list_examples > "$temp_dir/examples"
grep -Fx 'openlist' "$temp_dir/examples"
grep -Fx 'qinglong' "$temp_dir/examples"
if grep -Fx 'cloudflared' "$temp_dir/examples"; then
  echo 'Cloudflared 不应继续作为模块示例' >&2
  exit 1
fi

rm -f "$STACK_DIR/qltest.conf"
copy_stack_example qinglong qltest
grep -Fx 'IMAGE=whyour/qinglong:latest' "$STACK_DIR/qltest.conf"
grep -Fx 'HOSTNAME=qltest' "$STACK_DIR/qltest.conf"
grep -Fx 'VOLUME=/data/adb/dockroot/volumes/qltest:/ql/data' "$STACK_DIR/qltest.conf"
grep -Fx 'ENV=QlPort=5700' "$STACK_DIR/qltest.conf"
grep -Fx 'ENV=QlGrpcPort=5501' "$STACK_DIR/qltest.conf"
if grep -F '__STACK_NAME__' "$STACK_DIR/qltest.conf"; then
  echo '复制示例后不应保留配置名占位符' >&2
  exit 1
fi

rm -f "$STACK_DIR/qinglong.conf"
create_stack qinglong
test -f "$STACK_DIR/qinglong.conf"
if create_stack qinglong 5900 >/dev/null 2>&1; then
  echo '兼容命令不应继续接收应用专用端口参数' >&2
  exit 1
fi
if copy_stack_example cloudflared cloudflared >/dev/null 2>&1; then
  echo '已删除的 Cloudflared 示例不应还能创建' >&2
  exit 1
fi
if copy_stack_example qinglong one extra >/dev/null 2>&1; then
  echo '示例复制不应静默忽略多余参数' >&2
  exit 1
fi

cat > "$STACK_DIR/secretapp.conf" <<EOF
IMAGE=example/secretapp:latest
AUTOSTART=0
REQUIRED_FILE=$STATE_DIR/volumes/secretapp/token
EOF
mkdir -p "$DATA_ROOT/secretapp/rootfs" "$STATE_DIR/volumes/secretapp"
printf '%s\n' 'test-secret' | set_stack_secret secretapp >/dev/null
test "$(stat -c '%a' "$STATE_DIR/volumes/secretapp/token")" = 644
if grep -F 'test-secret' "$STACK_DIR/secretapp.conf"; then
  echo '秘密内容不应写入 Stack 配置' >&2
  exit 1
fi
: > "$calls"
apply_stack secretapp
grep -F 'run_dockroot <run> <--renew>' "$calls"
grep -F '<secretapp> <--> </bin/true>' "$calls"
if grep -F 'test-secret' "$calls"; then
  echo '秘密内容不应出现在 DockRoot 命令参数中' >&2
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

cat > "$STACK_DIR/readyapp.conf" <<'EOF'
IMAGE=example/readyapp:latest
COMMAND=/usr/local/bin/readyd
ARG=serve
READY_URL=http://127.0.0.1:49313/ready
EOF
mkdir -p "$DATA_ROOT/readyapp/rootfs"
running=0
: > "$calls"
health_url_ok() { return 1; }
start_stack readyapp
grep -F 'run_dockroot <run> <-d> <readyapp> <--> </usr/local/bin/readyd> <serve>' "$calls"

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

rm -f "$STATE_DIR/volumes/secretapp/token"
running=1
if start_stack secretapp >/dev/null 2>&1; then
  echo '缺少秘密文件时不应启动容器' >&2
  exit 1
fi
if [ "$running" != 1 ]; then
  echo '缺少秘密文件时不应停止原有容器进程' >&2
  exit 1
fi

cat > "$STACK_DIR/remove-me.conf" <<'EOF'
IMAGE=example/remove-me:latest
AUTOSTART=1
EOF
mkdir -p "$DATA_ROOT/remove-me/rootfs" "$STATE_DIR/volumes/remove-me"
touch "$STATE_DIR/volumes/remove-me/keep"
printf '%s\n' remove-me >> "$AUTOSTART_FILE"
running=0
autostart_remove() { sed -i "/^$1$/d" "$AUTOSTART_FILE"; }
remove_stack remove-me
test ! -e "$STACK_DIR/remove-me.conf"
test -d "$DATA_ROOT/remove-me/rootfs"
test -f "$STATE_DIR/volumes/remove-me/keep"
if grep -Fx remove-me "$AUTOSTART_FILE"; then
  echo '删除 Stack 时应同步移出自启列表' >&2
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

# 保活：连续失败达阈值才自愈，健康后清零计数。
HEALTH_STATE_DIR="$STATE_DIR/health"
HEALTHCHECK_FAILURES=3
HEALTHCHECK_COOLDOWN=1800
mkdir -p "$HEALTH_STATE_DIR"
stack_healthy=0
restart_count=0
stack_health_ok() { [ "$stack_healthy" = 1 ]; }
up_stack() { restart_count=$((restart_count + 1)); stack_healthy=1; }
now_epoch() { echo 2000; }

healthcheck_stack openlist >/dev/null || true
healthcheck_stack openlist >/dev/null || true
test "$restart_count" = 0
healthcheck_stack openlist >/dev/null
test "$restart_count" = 1
test "$(cat "$HEALTH_STATE_DIR/openlist.failures")" = 0

stack_healthy=1
printf '2\n' > "$HEALTH_STATE_DIR/openlist.failures"
healthcheck_stack openlist >/dev/null
test "$(cat "$HEALTH_STATE_DIR/openlist.failures")" = 0

# WebUI 数据必须从 Stack 动态生成，不写死应用名称。
cat > "$STACK_DIR/dashboard.conf" <<'EOF'
IMAGE=example/dashboard:latest
AUTOSTART=1
HEALTH_URL=http://127.0.0.1:8123/api/health
EOF
stack_health_ok() {
  # 模拟真实健康检查使用同名全局变量，确保不会覆盖面板入口。
  url="$(stack_values "$1" HEALTH_URL | head -n 1)"
  [ "$1" = dashboard ]
}
device_lan_ipv4() { printf '192.168.43.1\n'; }
web_status > "$temp_dir/web-status"
grep -F $'dashboard\thealthy\thttp://127.0.0.1:8123\thttp://192.168.43.1:8123' "$temp_dir/web-status"
grep -F $'openlist\tunhealthy\thttp://127.0.0.1:5244\thttp://192.168.43.1:5244' "$temp_dir/web-status"
