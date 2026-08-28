#!/usr/bin/env bash

set -euo pipefail

required=(
  module/module.prop
  module/customize.sh
  module/service.sh
  module/bin/drctl
  module/bin/wakealarm
  module/bin/dockroot-exec
  module/bin/migrate-module-id
  module/examples/openlist.conf
  module/examples/qinglong.conf
  module/system/bin/drctl
  module/webroot/index.html
  module/webroot/app.js
  module/webroot/kernelsu.js
  module/webroot/style.css
  scripts/package.sh
  README.md
  LICENSE
  update.json
)

for file in "${required[@]}"; do
  test -s "$file" || { echo "缺少文件：$file" >&2; exit 1; }
done

grep -q '^id=dockroot$' module/module.prop
grep -q '^name=DockRoot 容器$' module/module.prop
grep -q '^description=.*OCI/Docker.*Compose Lite.*健康自愈.*WebUI' module/module.prop
grep -q 'DOCKROOT_SHA256=' module/bin/drctl
grep -q 'RURI_SHA256=' module/bin/drctl
grep -q '只支持 host 网络' module/bin/drctl
grep -q '^IMAGE=openlistteam/openlist:latest$' module/examples/openlist.conf
grep -q '^CHECK_PORT=5244$' module/examples/openlist.conf
grep -q '^HOSTNAME=__STACK_NAME__$' module/examples/qinglong.conf
grep -q '^ENV=QlPort=5700$' module/examples/qinglong.conf
grep -q '^ENV=QlGrpcPort=5501$' module/examples/qinglong.conf
test ! -e module/examples/cloudflared.conf
grep -q '^updateJson=https://raw.githubusercontent.com/xyouo/dockroot/main/update.json$' module/module.prop
grep -q '"version": "v0.8.0"' update.json
grep -q '^exec /data/adb/modules/dockroot/bin/drctl ' module/system/bin/drctl
grep -q '"./kernelsu.js"' module/webroot/app.js
grep -q 'web-status' module/webroot/app.js
grep -q '局域网地址' module/webroot/app.js
grep -q 'device_lan_ipv4' module/bin/drctl
grep -q 'data-restart' module/webroot/app.js
grep -q 'window.confirm' module/webroot/app.js
grep -q 'drctl restart' module/webroot/app.js
grep -q 'if (restarted) await refresh' module/webroot/app.js
grep -q 'data-wake="scheduled"' module/webroot/index.html
grep -q 'drctl wakelock' module/webroot/app.js
grep -q 'refreshWake' module/webroot/app.js
grep -q 'drctl.*service' module/service.sh
grep -q 'wakelock on|scheduled|off|status' module/bin/drctl
grep -q '2>/dev/null || wakelock_is_active' module/bin/drctl
grep -q '^KEEP_AWAKE=0$' module/config.env
grep -q '^SCHEDULED_WAKE=0$' module/config.env
grep -q '^WAKE_TIMES=09:57,17:57$' module/config.env
grep -q '^WAKE_HOLD_SECONDS=300$' module/config.env
test -x module/bin/wakealarm

bash -n module/customize.sh
bash -n module/service.sh
bash -n module/bin/drctl
bash -n module/bin/dockroot-exec
bash -n module/bin/migrate-module-id
bash -n module/system/bin/drctl
bash -n scripts/package.sh
bash -n scripts/build-wakealarm.sh
bash tests/test-migration.sh
bash tests/test-drctl.sh
bash tests/test-stacks.sh
