# DockRoot 容器

在已 Root 的 ARM64 Android 上直接运行 OCI/Docker 镜像的模块（KernelSU / APatch / Magisk）。使用宿主网络，不支持 Docker bridge、`-p` 端口映射和 Docker Compose。

## 快速开始

刷入模块重启后：

```sh
su -c 'drctl pull alpine:latest alpine'
su -c 'drctl run alpine /bin/ash'
```

日常命令：

```sh
su -c 'drctl run -d alpine'          # 后台运行
su -c 'drctl ps alpine'              # 状态
su -c 'drctl stop alpine'            # 停止
su -c 'drctl autostart add alpine'   # 开机自启
su -c 'drctl logs alpine 100'        # 日志
```

## 固定配置

每个容器对应 `/data/adb/dockroot/stacks/<容器名>.conf`。常用字段：

- `IMAGE=`：镜像名，必填
- `AUTOSTART=0|1`：开机自启
- `VOLUME=宿主:容器[:ro]`：持久化数据，可重复
- `ENV=KEY=VALUE`：环境变量，可重复
- `COMMAND=` / `ARG=`：自定义启动命令
- `CHECK_PORT=`：检查端口冲突/监听，可重复
- `HEALTH_URL=`：HTTP 健康检查

```sh
su -c 'drctl stack init whoami traefik/whoami:latest'
# 编辑 /data/adb/dockroot/stacks/whoami.conf 后：
su -c 'drctl up whoami'
```

常用：

```sh
su -c 'drctl stack list'
su -c 'drctl stack example openlist'   # OpenList 示例，端口 5244
su -c 'drctl stack example qinglong'   # 青龙示例，HTTP 5700
su -c 'drctl up <容器名>'              # 应用配置并启动
su -c 'drctl restart <容器名>'
su -c 'drctl status <容器名>'
su -c 'drctl stack remove <容器名>'    # 只删配置，不删数据
```

## 更新

```sh
su -c 'drctl update <容器名>'   # 安全更新镜像，失败自动回滚
```

模块本身通过 KernelSU/APatch/Magisk 的 `update.json` 检测更新。数据都在 `/data/adb/dockroot`，升级不会删。

## 其他

- 健康保活：模块每 5 分钟检查自启容器，连续 3 次失败自动恢复，可在 `/data/adb/dockroot/config.env` 调整。
- 定时唤醒：`su -c 'drctl wakelock scheduled'` 定时短唤醒代替全天持锁；全天唤醒用 `drctl wakelock on`。
- 清理残留：`su -c 'drctl cleanup'` 预览，`--yes` 执行。
- 不要放 `/sdcard`，共享存储无法保存 Linux 权限和符号链接。

## 限制

- 容器接近特权运行，隔离不如标准 Docker。
- 所有服务共享手机端口。
- Android Doze / 厂商冻结可能延后任务或终止后台服务。

## 上游

- DockRoot: https://github.com/kspeeder/dockroot
- ruri: https://github.com/RuriOSS/ruri
