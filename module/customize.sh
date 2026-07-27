#!/system/bin/sh

ui_print "- 正在安装 DockRoot 容器模块"

abi="$(getprop ro.product.cpu.abi 2>/dev/null)"
case "$abi" in
  arm64-v8a|aarch64) ;;
  *)
    abort "! 当前仅支持 ARM64，检测到：${abi:-未知}"
    ;;
esac

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755

state_dir=/data/adb/dockroot
mkdir -p "$state_dir/bin" "$state_dir/data" "$state_dir/logs" "$state_dir/stacks" "$state_dir/volumes" ||
  abort "! 无法准备数据目录：$state_dir"
chmod 0700 "$state_dir" "$state_dir/bin" "$state_dir/data" "$state_dir/logs" "$state_dir/stacks" ||
  abort "! 无法设置数据目录权限"
chmod 0755 "$state_dir/volumes" ||
  abort "! 无法设置业务卷目录权限"

if [ ! -f "$state_dir/config.env" ]; then
  cp "$MODPATH/config.env" "$state_dir/config.env" ||
    abort "! 无法创建配置文件"
fi

if [ ! -f "$state_dir/autostart.list" ]; then
  : > "$state_dir/autostart.list" ||
    abort "! 无法创建自启列表"
fi

chmod 0600 "$state_dir/config.env" "$state_dir/autostart.list" ||
  abort "! 无法设置配置文件权限"

migration_result="$("$MODPATH/bin/migrate-module-id" "$MODPATH" 2>&1)"
migration_status=$?
if [ "$migration_status" -ne 0 ]; then
  abort "! 旧模块迁移失败：$migration_result"
fi

case "$migration_result" in
  migrated)
    ui_print "- 已接管 /data/adb/dockroot 中的原有数据"
    ui_print "- 已安排移除旧模块 dockroot_ksu，重启后完成迁移"
    ;;
  migrated-disabled)
    ui_print "- 已接管 /data/adb/dockroot 中的原有数据"
    ui_print "- 旧模块原本已禁用；新模块将保持禁用"
    ui_print "- 已安排移除旧模块 dockroot_ksu，重启后完成迁移"
    ;;
esac

ui_print "- 安装完成"
ui_print "- 重启后首次使用：su -c 'drctl install-runtime'"
ui_print "- 帮助：su -c 'drctl help'"
