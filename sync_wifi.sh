#!/bin/sh
# sync_wifi.sh —— 把网关（162）上保存的 WiFi 档案同步到其它设备
#
# 用法:
#   sh sync_wifi.sh              # 同步到默认设备列表，离线的自动跳过
#   sh sync_wifi.sh max1 n04     # 只同步指定设备
#   sh sync_wifi.sh --from max1  # 换一台源机（默认 rn4x = 162 网关）
#
# 原理: 从源机用 nmcli -s 读出每个无线档案的 SSID / PSK / 优先级，
#       再在目标机按同样 SSID 建或改档案（幂等，可反复跑）。
# 安全: 只 add / modify 档案，**不 up**，不会切断目标机当前连接；
#       autoconnect 开着，下次掉线时自动按优先级挑网络。
# 后端: 目标机需要 NetworkManager(nmcli)。Android/wpa 后端的机器改用 n2wifi add。

SRC="rn4x"
[ "$1" = "--from" ] && { SRC="$2"; shift 2; }
if [ $# -gt 0 ]; then HOSTS="$*"; else HOSTS="note2-01 note2-03 note2-04 note2-05 note2-00 max2 max1"; fi

# ---------- 1. 从源机取档案清单（SSID|PSK|key-mgmt|优先级） ----------
PROFILES=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$SRC" 'sh -s' <<'SRC_EOF'
nmcli -t -f NAME,TYPE connection show | awk -F: '$2 ~ /wireless/ {print $1}' | while read -r n; do
  ssid=$(nmcli -g 802-11-wireless.ssid connection show "$n" 2>/dev/null)
  psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$n" 2>/dev/null)
  km=$(nmcli -s -g 802-11-wireless-security.key-mgmt connection show "$n" 2>/dev/null)
  pr=$(nmcli -g connection.autoconnect-priority connection show "$n" 2>/dev/null)
  [ -z "$km" ] && km=wpa-psk
  echo "$ssid|$psk|$km|${pr:-0}"
done
SRC_EOF
) || { echo "读取源机 $SRC 失败"; exit 1; }

[ -z "$PROFILES" ] && { echo "$SRC 上没有找到无线档案"; exit 1; }
echo "源机 $SRC 保存的网络:"
printf '%s\n' "$PROFILES" | awk -F'|' '{printf "  - %-16s psk=%s  prio=%s\n", $1, ($2==""?"(无/开放)":$2), $4}'
echo

# ---------- 2. 逐台下发 ----------
for h in $HOSTS; do
  printf '== %s: ' "$h"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" true 2>/dev/null; then
    echo "离线，跳过"
    continue
  fi
  echo
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$h" "sh -s" <<REMOTE 2>&1 | sed 's/^/     /'
set -u
if ! command -v nmcli >/dev/null 2>&1; then
  echo "没有 nmcli，跳过（Android/wpa 后端请用 n2wifi add）"; exit 0
fi
while IFS='|' read -r ssid psk km prio; do
  [ -z "\${ssid:-}" ] && continue
  if nmcli -t -f NAME connection show | grep -Fxq "\$ssid"; then
    nmcli connection modify "\$ssid" \\
      802-11-wireless-security.key-mgmt "\$km" \\
      802-11-wireless-security.psk "\$psk" \\
      connection.autoconnect yes \\
      connection.autoconnect-priority "\$prio" >/dev/null && echo "[modify] \$ssid prio=\$prio"
  else
    nmcli connection add type wifi con-name "\$ssid" ssid "\$ssid" \\
      802-11-wireless-security.key-mgmt "\$km" \\
      802-11-wireless-security.psk "\$psk" \\
      connection.autoconnect yes \\
      connection.autoconnect-priority "\$prio" >/dev/null && echo "[add]    \$ssid prio=\$prio"
  fi
done <<PROFILE_LIST
$PROFILES
PROFILE_LIST
echo "-- 现有无线档案:"
nmcli -t -f NAME,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY connection show \
  | awk -F: '\$2 ~ /wireless/ {printf "   %-16s autoconnect=%s prio=%s\n", \$1, \$3, \$4}'
REMOTE
done
