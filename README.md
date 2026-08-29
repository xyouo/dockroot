# DockRoot 容器

适用于 KernelSU、APatch 和 Magisk 的实验性 Root 模块，在已 Root 的 ARM64 Android 上直接运行 OCI/Docker 镜像，不依赖额外 chroot 模块。

不是完整 Docker Engine。DockRoot 拉取镜像后通过 ruri 解包运行，使用宿主网络，不支持 bridge、`-p` 端口映射、Docker Compose 或 Docker API。

## 安装

刷入模块并重启手机，然后测试：

```sh
su -c 'drctl pull alpine:latest alpine'
su -c 'drctl run alpine /bin/ash'
```

第一次 `pull` 会自动下载运行环境。`doctor`、`install-runtime` 仅用于诊断，不是每次安装必须执行。

后台运行、状态和停止：

```sh
su -c 'drctl run -d alpine'
su -c 'drctl ps alpine'
su -c 'drctl stop alpine'
```

开机自启：

```sh
su -c 'drctl autostart add alpine'
su -c 'drctl autostart list'
```

## Compose Lite 配置

每个容器对应一个固定配置文件：

```text
/data/adb/dockroot/stacks/<容器名>.conf
```

常用字段：

| 字段 | 说明 |
|---|---|
| `IMAGE=` | 镜像名，必填 |
| `AUTOSTART=0\|1` | 是否开机自启 |
| `VOLUME=宿主:容器[:ro]` | 可重复，持久化数据 |
| `ENV=KEY=VALUE` | 可重复，环境变量 |
| `COMMAND=` / `ARG=` | 自定义启动命令和参数 |
| `CHECK_PORT=` | 可重复，启动前后检查端口冲突/监听 |
| `HEALTH_URL=` | 启动后的 HTTP 健康检查 |
| `REQUIRED_FILE=` | 启动前必须存在的宿主机文件 |

常用命令：

```sh
su -c 'drctl stack list'
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

`apply` 只拉取缺失镜像并更新配置，不会启动服务。`up` 会应用配置并后台启动。修改 `.conf` 后再次执行 `drctl up <容器名>` 即可生效。

任何 ARM64 镜像都能用：

```sh
su -c 'drctl stack init whoami traefik/whoami:latest'
```

生成 `.conf` 后按镜像文档填写 `VOLUME`、`ENV`、`COMMAND`、`CHECK_PORT`、`HEALTH_URL`，再 `drctl up whoami`。

删除 Stack（只删配置，不删镜像和业务数据）：

```sh
su -c 'drctl down whoami'
su -c 'drctl stack remove whoami'
```

## 内置示例

```sh
su -c 'drctl stack example openlist'   # OpenList，端口 5244
su -c 'drctl stack example qinglong'   # 青龙，HTTP 5700 / gRPC 5501
```

改端口直接编辑 `.conf` 里的 `ENV`、`CHECK_PORT` 和 `HEALTH_URL`，再 `drctl up <容器名>`。

## 健康保活

模块监控 `autostart.list` 中的容器。默认每 300 秒检查一次，连续 3 次失败才自愈，自愈后 1800 秒内不会重复重启同一容器。

```ini
HEALTHCHECK_ENABLE=1
HEALTHCHECK_INTERVAL=300
HEALTHCHECK_FAILURES=3
HEALTHCHECK_COOLDOWN=1800
```

可在 `/data/adb/dockroot/config.env` 修改，也可执行 `su -c 'drctl healthcheck'` 手动检查。

### 定时唤醒

如果只在固定时刻需要任务执行，用定时短唤醒代替全天持锁：

```sh
su -c 'drctl wakelock scheduled'
su -c 'drctl wakelock status'
```

默认每天 `09:57`、`17:57` 唤醒 300 秒。可在 `config.env` 修改：

```ini
SCHEDULED_WAKE=1
WAKE_TIMES=09:57,17:57
WAKE_HOLD_SECONDS=300
WAKE_TIMEZONE=Asia/Shanghai
```

长期插电可开全天唤醒 `drctl wakelock on`，关闭用 `drctl wakelock off`。`on` 与 `scheduled` 互斥。

## 更新与升级

模块通过标准 `update.json` 支持 KernelSU/APatch/Magisk 更新检测。更新 ZIP 只包含模块本身，运行环境、镜像、配置和业务卷在 `/data/adb/dockroot`，覆盖升级不会删除。

更新单个容器镜像：

```sh
su -c 'drctl update <容器名>'
```

先完整下载新镜像，再短暂停机替换；失败会自动回滚到旧版本。

WebUI 在 KernelSU 模块详情页点击"打开"进入，动态展示容器状态、本机/局域网地址、重启按钮和开机自启开关。

## 数据位置

- 配置：`/data/adb/dockroot/config.env`
- 镜像和容器：`/data/adb/dockroot/data`
- Stack 配置：`/data/adb/dockroot/stacks`
- 业务数据：`/data/adb/dockroot/volumes`
- 自启列表：`/data/adb/dockroot/autostart.list`
- 日志：`/data/adb/dockroot/logs/service.log`

不要放 `/sdcard`，Android 共享存储无法正确保存 Linux 权限和符号链接。

清理失败拉取留下的残留：

```sh
su -c 'drctl cleanup'          # 预览
su -c 'drctl cleanup --yes'    # 确认后删除
```

## 限制

- 容器接近特权运行，隔离能力不如标准 Docker。
- 所有服务共享手机端口，需自行避免冲突。
- Android Doze、厂商冻结可能延后任务或终止后台服务。
- WebUI 需要 KernelSU/APatch；Magisk 环境可用全部命令行功能。
- 上游二进制更新后若 SHA-256 变化，模块会拒绝执行，需仓库先更新校验值。

## 上游

- DockRoot: https://github.com/kspeeder/dockroot
- ruri: https://github.com/RuriOSS/ruri
