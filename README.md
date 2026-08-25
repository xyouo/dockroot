# DockRoot 容器

这是一个适用于 KernelSU、APatch 和 Magisk 的实验性 Root 模块，用于在已 Root 的 ARM64 Android 设备上直接运行 OCI/Docker 镜像，不依赖额外的 Debian/Ubuntu chroot 模块。

它不是完整 Docker Engine。DockRoot 会拉取 OCI/Docker 镜像、解包为 rootfs，再通过 ruri 启动。容器使用宿主网络，不支持 Docker bridge、`-p` 端口映射、Docker Compose 或 Docker API。

## 当前功能

- 仅支持 ARM64 Android。
- 从 DockRoot 上游下载运行环境并校验固定 SHA-256。
- 拉取、运行、停止和查看容器。
- 查看 ruri 原始运行日志。
- 配置容器开机自启。
- 每 5 分钟检查自启容器，连续 3 次失败后自动恢复，并限制故障循环。
- 提供 KernelSU WebUI，动态展示容器状态、打开面板和复制地址。
- 使用 Compose Lite 配置文件声明镜像、卷、环境变量、自定义启动命令和自启策略。
- 提供与具体应用无关的 Stack 初始化、复制和删除命令。
- 附带 OpenList、青龙示例配置；示例不参与核心命令分支。
- 输出架构、SELinux、文件系统和挂载环境诊断。
- 通过独立 mount namespace 为 DockRoot 提供 DNS，不修改 Android 全局网络配置。
- 卸载模块时保留容器数据，防止误删。

模块不会在 Release 中重新分发 DockRoot/ruri 二进制。首次安装运行环境时，手机会直接访问第三方上游下载；DockRoot 仓库目前没有明确许可证，请自行判断是否接受。

## 安装与首次测试

刷入模块并重启手机，然后在 Termux 等终端执行：

```sh
su -c 'drctl pull alpine:latest alpine'
su -c 'drctl run alpine /bin/ash'
```

`pull` 会在本机第一次使用时自动下载并校验运行环境。`doctor` 和 `install-runtime` 仅用于诊断或手动预安装，不是每次安装模块都必须执行。

重启后模块会把 `drctl` 放入 root 命令路径，本文命令均使用 `su -c 'drctl …'` 的简洁写法。

进入 Alpine 后可测试：

```sh
cat /etc/os-release
uname -m
exit
```

后台运行、查看状态和停止：

```sh
su -c 'drctl run -d alpine'
su -c 'drctl ps alpine'
su -c 'drctl stop alpine'
```

设置开机自启：

```sh
su -c 'drctl autostart add alpine'
su -c 'drctl autostart list'
```

## Compose Lite 固定配置

每个容器使用一个容易备份和编辑的配置文件：

```text
/data/adb/dockroot/stacks/<容器名>.conf
```

支持以下字段：

- `IMAGE=`：镜像名称，必填。
- `AUTOSTART=0|1`：是否随手机开机启动。
- `VOLUME=宿主绝对路径:容器绝对路径[:ro]`：可以重复填写。
- `ENV=KEY=VALUE`：可以重复填写。
- `HOSTNAME=`：可选容器主机名。
- `WORKDIR=`：可选容器工作目录，必须是绝对路径。
- `COMMAND=`：可选启动程序，必须是容器内绝对路径，只能填写一次。
- `ARG=`：传给 `COMMAND` 的单个参数，可以重复填写；即使参数包含空格或 `=` 也不会经过 shell 展开。
- `APPLY_COMMAND=`、`APPLY_ARG=`：可选的一次性应用命令。适用于没有 `/bin/true` 的 distroless 镜像。
- `REQUIRED_FILE=`：启动前必须存在且非空的宿主机文件。
- `CHECK_PORT=`：启动前检查冲突、启动后确认监听，可以重复填写。
- `HEALTH_URL=`：启动后的本机 HTTP 健康检查地址。
- `READY_URL=`：仅在 `status` 中显示外部连接是否就绪，不会因断网而终止仍在重连的进程。

DockRoot 只有 host 网络，因此不支持 Compose 的 `ports`、独立网络、`depends_on` 等字段。镜像监听的端口会直接占用手机端口。

常用命令：

```sh
su -c 'drctl stack list'
su -c 'drctl stack path'
su -c 'drctl stack init demo alpine:latest'
su -c 'drctl stack examples'
su -c 'drctl stack example openlist'
su -c 'drctl apply openlist'
su -c 'drctl up openlist'
su -c 'drctl down openlist'
su -c 'drctl restart openlist'
su -c 'drctl status openlist'
su -c 'drctl logs openlist 100'
```

`apply` 只拉取缺失镜像并更新固定配置，不会启动长期服务。`up` 会应用配置后后台启动。修改 `.conf` 后再次执行 `drctl up <容器名>` 即可生效。

### 通用 Stack 工作流

任何 ARM64 镜像都可以先生成一份最小配置，不需要模块内置预设：

```sh
su -c 'drctl stack init whoami traefik/whoami:latest'
```

生成 `/data/adb/dockroot/stacks/whoami.conf` 后，按镜像文档填写需要的 `VOLUME`、`ENV`、`COMMAND`、`ARG`、`CHECK_PORT` 和 `HEALTH_URL`，再执行：

```sh
su -c 'drctl up whoami'
```

也可以把自己准备好的 `.conf` 直接放入 `/data/adb/dockroot/stacks`。除旧版 OpenList、青龙配置的兼容修正外，模块不会根据容器名称加入隐藏参数或修改业务配置。

删除 Stack 配置：

```sh
su -c 'drctl down whoami'
su -c 'drctl stack remove whoami'
```

`stack remove` 只删除 `.conf` 并移出自启列表，镜像 rootfs 和业务卷会保留，避免误删数据。

### OpenList 标准完整版示例

复制模块附带的示例：

```sh
su -c 'drctl stack example openlist'
su -c 'drctl up openlist'
```

生成的 `/data/adb/dockroot/stacks/openlist.conf` 内容为：

```ini
IMAGE=openlistteam/openlist:latest
AUTOSTART=1
VOLUME=/data/adb/dockroot/volumes/openlist:/opt/openlist/data
ENV=UMASK=022
CHECK_PORT=5244
HEALTH_URL=http://127.0.0.1:5244/
```

这里使用 OpenList 官方标准完整版 `latest`，不是 `lite` 精简版。OpenList 使用 host 网络，默认面板地址为 `http://127.0.0.1:5244`。业务配置和数据库保存在 `/data/adb/dockroot/volumes/openlist`，重新拉取镜像不会删除它们。

DockRoot 当前版本在拉取时会丢失 `latest-aio` 等非 `latest` 标签，因此模块会拒绝静默拉错镜像。v0.2.0 创建的 OpenList 配置会在首次 `apply/up` 时自动迁移为实际已拉取的 `latest`。待上游修复标签处理后，再恢复 AIO 模板支持。

OpenList 4.1 之后可能以容器内 UID 1001 运行。模块会放宽具体卷目录的权限以允许该用户写入；其上级 `/data/adb/dockroot` 仍保持仅 root 可访问。

### 青龙面板示例

先复制青龙示例：

```sh
su -c 'drctl stack example qinglong'
```

生成的 `/data/adb/dockroot/stacks/qinglong.conf` 默认使用 HTTP 5700、gRPC 5501：

```ini
IMAGE=whyour/qinglong:latest
AUTOSTART=1
HOSTNAME=qinglong
VOLUME=/data/adb/dockroot/volumes/qinglong:/ql/data
ENV=QlPort=5700
ENV=QlGrpcPort=5501
ENV=QlBaseUrl=/
ENV=TZ=Asia/Shanghai
CHECK_PORT=5700
CHECK_PORT=5501
HEALTH_URL=http://127.0.0.1:5700/api/health
```

如需改为 HTTP 5900，请在启动前同时修改 `ENV=QlPort`、对应的 `CHECK_PORT` 和 `HEALTH_URL`，然后执行：

```sh
su -c 'drctl up qinglong'
```

青龙使用 host 网络。模块会按配置检查端口冲突、HTTP 健康状态和持久化卷。青龙的配置、任务、日志和依赖保存在 `/data/adb/dockroot/volumes/qinglong`，覆盖升级模块或重新拉取镜像不会删除。

旧版 `drctl stack create openlist`、`drctl stack create qinglong` 仍可使用，实际只是 `stack example` 的兼容别名；应用专用的端口参数已删除，端口统一在 `.conf` 中显式管理。

## 可靠启动与状态检查

`up`、`restart` 和开机自启共用同一套生命周期：

1. 先检查 `REQUIRED_FILE`，缺失时保留当前正常实例。
2. 停止旧实例并等待 PID 真正退出。
3. 应用声明式配置。
4. 检查所有 `CHECK_PORT` 是否被其他进程占用。
5. 启动容器。
6. 验证进程、每个持久化卷、端口和 `HEALTH_URL`。

`READY_URL` 只用于 `status` 展示，不参与启动成败判断，适合 cloudflared 这类需要等待外部网络并能自行重连的服务。其他步骤失败都会返回非零退出码并说明原因，不再把“命令已发出”当成“容器启动成功”。诊断示例：

```sh
su -c 'drctl status openlist'
su -c 'drctl status qinglong'
```

模块自身日志与容器 `ruri.log` 默认超过 1 MiB 后保留为 `.1` 并重新记录。阈值可在 `/data/adb/dockroot/config.env` 中通过 `MAX_LOG_SIZE_KB` 修改。

### 健康保活与故障自愈

模块只监控 `autostart.list` 中的容器。默认每 300 秒检查进程、持久化卷、`CHECK_PORT` 和 `HEALTH_URL`；连续 3 次失败才执行一次 `up`，自愈后 1800 秒内不会再次重启同一容器。正常容器不会被定时重启。

```ini
HEALTHCHECK_ENABLE=1
HEALTHCHECK_INTERVAL=300
HEALTHCHECK_FAILURES=3
HEALTHCHECK_COOLDOWN=1800
```

可在 `/data/adb/dockroot/config.env` 修改上述参数，也可执行 `su -c 'drctl healthcheck'` 手动检查一次。只在失败或自愈时记录 `/data/adb/dockroot/logs/healthcheck.log`。该功能可恢复崩溃或端口失效的容器，但 Android 深度休眠仍可能延迟检查本身，它不等于精确定时唤醒。

### KernelSU 容器入口

在 KernelSU 的模块详情中点击“打开”即可进入 DockRoot WebUI。页面会动态读取所有 Stack，显示容器健康状态，并为已配置 `HEALTH_URL` 的容器提供“打开”和“复制地址”。每个 Stack 都会显示带二次确认的“重启”按钮，操作完成后自动刷新状态。例如 `http://127.0.0.1:9057/api/health` 会生成 `http://127.0.0.1:9057` 入口。

## 模块更新

模块提供标准 `update.json`，支持 KernelSU/APatch/Magisk 管理器的常规更新检测。更新 ZIP 只包含模块本身；运行环境、镜像、stack 配置和业务卷继续保存在 `/data/adb/dockroot`，覆盖升级不会删除。

v0.7.1 为 WebUI 中的每个 Stack 增加带二次确认、过程反馈和完成后自动刷新的“重启”按钮。

v0.7.0 增加通用健康保活、失败阈值与自愈冷却，并增加 KernelSU 容器入口 WebUI。

v0.6.0 将 Stack 创建改为通用架构。已有 `/data/adb/dockroot/stacks/*.conf` 不会被示例覆盖并可继续工作；OpenList、青龙改为普通示例文件，Cloudflared 不再作为内置预设。以后新增容器通常只需创建或复制 `.conf`，不需要等待模块发布新版。

v0.5.0 将内部模块 ID 从历史名称 `dockroot_ksu` 迁移为 `dockroot`。从 v0.4.1 或更早版本刷入 v0.5.0 时，安装脚本会复用原有 `/data/adb/dockroot` 数据，并将旧模块标记为待移除。安装完成到重启前，管理器短暂显示新旧两个模块属于正常现象；重启一次后只会保留新的 `dockroot` 模块。

不要在迁移前手动移动或删除 `/data/adb/modules/dockroot_ksu`。镜像、容器、Stack、配置和业务卷从最早版本起就位于 `/data/adb/dockroot`，迁移不会复制大文件，也不会清空现有数据。如果旧模块原本已禁用，新模块会继承禁用状态。

## 数据与配置

- 配置：`/data/adb/dockroot/config.env`
- 镜像和容器：`/data/adb/dockroot/data`
- Compose Lite 配置：`/data/adb/dockroot/stacks`
- 持久化业务数据：`/data/adb/dockroot/volumes`
- 自启列表：`/data/adb/dockroot/autostart.list`
- 模块日志：`/data/adb/dockroot/logs/service.log`

不要把容器 rootfs 放到 `/sdcard`。Android 共享存储不能正确保存 Linux 权限和符号链接。建议使用 `/data`，或者已正确挂载的 Ext4 外置存储。

## 清理旧文件

先预览模块能够安全识别的残留：

```sh
su -c 'drctl cleanup'
```

确认列表后删除：

```sh
su -c 'drctl cleanup --yes'
```

该命令只删除两类内容：

- `/data/adb/dockroot/data` 中没有 `rootfs` 的失败拉取目录，例如之前失败产生的 `alpine2`。
- `/data/adb/dockroot/bin` 中遗留的 `.download.*` 下载残片。

清理前还会校验 DockRoot 受管标记，并拒绝 `/`、`/data`、`/system` 等系统级 `DATA_ROOT`，避免误配置扩大删除范围。

以下目录仍在使用，不应作为旧版本垃圾删除：

- `/data/adb/dockroot/bin`：DockRoot 和 ruri 运行环境。
- `/data/adb/dockroot/dns-etc`、`cacerts`：Android DNS 与 HTTPS 兼容环境。
- `/data/adb/dockroot/data/<容器名>`：已拉取的容器 rootfs。
- `/data/adb/dockroot/stacks`：固定配置。
- `/data/adb/dockroot/volumes`：容器业务数据。

## 重要限制

- 容器接近特权运行，隔离能力不能与标准 Docker 相比。
- 所有服务共享手机网络和端口，必须自行避免端口冲突。
- Android 的 Doze、厂商后台冻结和温控策略可能延后任务或终止后台服务。
- WebUI 需要支持模块 WebUI 的 KernelSU/APatch 管理器；Magisk 环境仍可使用全部命令行功能。
- 如果上游二进制更新导致 SHA-256 改变，模块会拒绝执行未知文件，需要先在仓库更新校验值。

## 上游项目

- DockRoot：https://github.com/kspeeder/dockroot
- ruri：https://github.com/RuriOSS/ruri
