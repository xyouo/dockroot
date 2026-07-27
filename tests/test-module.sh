#!/usr/bin/env bash

set -euo pipefail

required=(
  module/module.prop
  module/customize.sh
  module/service.sh
  module/bin/drctl
  module/bin/dockroot-exec
  module/bin/migrate-module-id
  module/examples/cloudflared.conf
  module/examples/openlist.conf
  module/examples/qinglong.conf
  module/system/bin/drctl
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
grep -q '^description=.*OCI/Docker.*OpenList.*青龙.*Cloudflare Tunnel' module/module.prop
grep -q 'DOCKROOT_SHA256=' module/bin/drctl
grep -q 'RURI_SHA256=' module/bin/drctl
grep -q '只支持 host 网络' module/bin/drctl
grep -q '^IMAGE=openlistteam/openlist:latest$' module/examples/openlist.conf
grep -q '^CHECK_PORT=5244$' module/examples/openlist.conf
grep -q '^ENV=QlGrpcPort=__QL_GRPC_PORT__$' module/examples/qinglong.conf
grep -q '^IMAGE=cloudflare/cloudflared:latest$' module/examples/cloudflared.conf
grep -q '^COMMAND=/usr/local/bin/cloudflared$' module/examples/cloudflared.conf
grep -q '^ARG=--token-file$' module/examples/cloudflared.conf
grep -q '^updateJson=https://raw.githubusercontent.com/xyouo/dockroot/main/update.json$' module/module.prop
grep -q '"version": "v0.5.0"' update.json
grep -q '^exec /data/adb/modules/dockroot/bin/drctl ' module/system/bin/drctl

bash -n module/customize.sh
bash -n module/service.sh
bash -n module/bin/drctl
bash -n module/bin/dockroot-exec
bash -n module/bin/migrate-module-id
bash -n module/system/bin/drctl
bash -n scripts/package.sh
bash tests/test-migration.sh
bash tests/test-drctl.sh
bash tests/test-stacks.sh
