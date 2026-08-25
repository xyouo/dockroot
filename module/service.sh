#!/system/bin/sh

MODDIR=${0%/*}
"$MODDIR/bin/drctl" service >/dev/null 2>&1 &
