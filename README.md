# DockRoot 容器

这是一个适用于 KernelSU、APatch 和 Magisk 的实验性 Root 模块，用于在已 Root 的 ARM64 Android 设备上直接运行 OCI/Docker 镜像，不依赖额外的 Debian/Ubuntu chroot 模块。

它不是完整 Docker Engine。DockRoot 会拉取 OCI/Docker 镜像、解包为 rootfs，再通过 ruri 启动。容器使用宿主网络，不支持 Docker bridge、`-p` 端口映射、Docker Compose 或 Docker API。

## 当前功能

- 仅支持 ARM64 Android。
- 从 DockRoot 上游下载运行环境并校验固定 SHA-256。
- 拉取、运行、停止和查看容器。
- 查看 ruri 原始运行日志。
- 配置容器开机自启。
- 使用 Compose Lite 配置文件声明镜像、卷、环境变量、自定义启动命令和自启策略。
- 提供 OpenList、青龙与 Cloudflare Tunnel 内置模板。
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
su -c 'drctl apply openlist'
su -c 'drctl up openlist'
su -c 'drctl down openlist'
su -c 'drctl restart openlist'
su -c 'drctl status openlist'
su -c 'drctl logs openlist 100'
```

`apply` 只拉取缺失镜像并更新固定配置，不会启动长期服务。`up` 会应用配置后后台启动。修改 `.conf` 后再次执行 `drctl up <容器名>` 即可生效。

### OpenList 标准完整版示例

创建内置模板：

```sh
su -c 'drctl stack create openlist'
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

创建青龙配置时可以直接指定端口，例如使用 5900：

```sh
su -c 'drctl stack create qinglong 5900'
su -c 'drctl up qinglong'
```

生成的 `/data/adb/dockroot/stacks/qinglong.conf` 主要内容为：

```ini
IMAGE=whyour/qinglong:latest
AUTOSTART=1
HOSTNAME=qinglong
VOLUME=/data/adb/dockroot/volumes/qinglong:/ql/data
ENV=QlPort=5900
ENV=QlGrpcPort=5501
ENV=QlBaseUrl=/
ENV=TZ=Asia/Shanghai
CHECK_PORT=5900
CHECK_PORT=5501
HEALTH_URL=http://127.0.0.1:5900/api/health
```

青龙使用 host 网络，因此面板地址是 `http://127.0.0.1:5900`，gRPC 使用 5501。模块会在启动前检查两个端口冲突，并在启动后验证 HTTP、gRPC 和持久化卷。青龙的配置、任务、日志和依赖保存在 `/data/adb/dockroot/volumes/qinglong`，覆盖升级模块或重新拉取镜像不会删除。

如果创建模板时省略端口，将使用青龙默认的 5700：

```sh
su -c 'drctl stack create qinglong'
```

也可以同时指定 HTTP 和 gRPC 端口：

```sh
su -c 'drctl stack create qinglong 5900 5501'
```

### Cloudflare Tunnel 示例

官方 `cloudflare/cloudflared:latest` 镜像支持 ARM64。DockRoot 使用 host 网络，因此 cloudflared 可以直接访问手机上的服务，例如青龙模板默认的 `http://127.0.0.1:5700`（改过端口时以实际配置为准）和 OpenList `http://127.0.0.1:5244`；它不会占用这两个业务端口。

推荐在 Cloudflare 控制台创建 remotely-managed Tunnel，并在控制台配置 Public Hostname。创建完成后，只复制安装命令末尾以 `eyJ...` 开头的 Tunnel token。不要把 token 写入仓库、Issue、Release 或聊天记录。

在手机创建模板并隐藏输入 token：

```sh
su -c 'drctl stack create cloudflared'
su -c 'drctl stack secret cloudflared'
```

第二条命令的输入不会显示。token 会单独保存到 `/data/adb/dockroot/volumes/cloudflared/token`，不会写入 Stack 配置或进程参数；该目录以只读方式挂载进容器。

然后启动并检查：

```sh
su -c 'drctl up cloudflared'
su -c 'drctl status cloudflared'
su -c 'drctl logs cloudflared 100'
```

默认使用仅监听本机的 `49312` 作为 metrics/就绪检查端口。若它被占用，可在创建模板时换一个端口：

```sh
su -c 'drctl stack create cloudflared 49313'
```

Tunnel 本身不需要开放入站端口，但设备网络需要允许 cloudflared 出站访问 Cloudflare 的 `7844/UDP`（QUIC）和 `7844/TCP`（HTTP/2 回退）。`status` 中的 `ready[...]=connected` 表示已连接 Cloudflare；断网时会显示 `disconnected`，但模块不会杀掉进程，cloudflared 会继续自动重连。相关说明见 [Cloudflare Tunnel 运行参数](https://developers.cloudflare.com/tunnel/advanced/run-parameters/) 与 [防火墙要求](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-with-firewall/)。

如果把青龙暴露到公网，建议同时配置 Cloudflare Access，避免只依赖面板自身登录。

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
su -c 'drctl status cloudflared'
```

模块自身日志与容器 `ruri.log` 默认超过 1 MiB 后保留为 `.1` 并重新记录。阈值可在 `/data/adb/dockroot/config.env` 中通过 `MAX_LOG_SIZE_KB` 修改。

## 模块更新

模块提供标准 `update.json`，支持 KernelSU/APatch/Magisk 管理器的常规更新检测。更新 ZIP 只包含模块本身；运行环境、镜像、stack 配置和业务卷继续保存在 `/data/adb/dockroot`，覆盖升级不会删除。

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
- 首版不提供 WebUI，先验证设备兼容性和运行稳定性。
- 如果上游二进制更新导致 SHA-256 改变，模块会拒绝执行未知文件，需要先在仓库更新校验值。

## 上游项目

- DockRoot：https://github.com/kspeeder/dockroot
- ruri：https://github.com/RuriOSS/ruri
