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
mkdir -p "$state_dir/bin" "$state_dir/data" "$state_dir/logs"
chmod 0700 "$state_dir" "$state_dir/bin" "$state_dir/data" "$state_dir/logs"

if [ ! -f "$state_dir/config.env" ]; then
  cp "$MODPATH/config.env" "$state_dir/config.env"
  chmod 0600 "$state_dir/config.env"
fi

if [ ! -f "$state_dir/autostart.list" ]; then
  : > "$state_dir/autostart.list"
  chmod 0600 "$state_dir/autostart.list"
fi

ui_print "- 安装完成"
ui_print "- 重启后首次使用：su -c 'drctl install-runtime'"
ui_print "- 帮助：su -c 'drctl help'"
