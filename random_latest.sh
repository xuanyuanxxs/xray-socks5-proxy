#!/bin/sh
set -e

RC_LOCAL="/etc/rc.local"
BASE_DIR="/etc/config"

echo "--- 1. 正在创建并写入脚本文件到 ${BASE_DIR} ---"

# ===============================
# 1. name.sh —— 随机主机名
# ===============================
cat << "EOF_NAME" > ${BASE_DIR}/name.sh
#!/bin/sh

SYSTEM_CONFIG="/etc/config/system"

NEW_HOSTNAME=$(tr -dc 'a-z' < /dev/urandom | head -c 6)
echo "✅ 生成新的主机名: ${NEW_HOSTNAME}"

uci set system.@system[0].hostname="${NEW_HOSTNAME}"
uci commit system
#/etc/init.d/system reload

echo "✨ 新的主机名已应用"
#uci get system.@system[0].hostname
EOF_NAME

chmod +x ${BASE_DIR}/name.sh
echo "✅ 文件 ${BASE_DIR}/name.sh 创建成功"


# ===============================
# 2. mac.sh —— 随机 MAC
# ===============================
cat << "EOF_MAC" > ${BASE_DIR}/mac.sh
#!/bin/sh
set -e

NETFILE="/etc/config/network"

rand_byte() {
    C=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null)
    printf "%d" "'\$C'"
}

RAND_MAC=$(printf "02:%02X:%02X:%02X:%02X:%02X" \
  \$(rand_byte) \$(rand_byte) \$(rand_byte) \$(rand_byte) \$(rand_byte))

sed -i "s/^\(\s*option macaddr\s*\).*/\1 '\$RAND_MAC'/" "\$NETFILE"

echo ">>> 随机 MAC: \$RAND_MAC"
#/etc/init.d/network reload
EOF_MAC

chmod +x ${BASE_DIR}/mac.sh
echo "✅ 文件 ${BASE_DIR}/mac.sh 创建成功"


# ===============================
# 3. ip.sh —— 随机 LAN IP
# ===============================
cat << "EOF_IP" > ${BASE_DIR}/ip.sh
#!/bin/sh
set -e

NETFILE="/etc/config/network"

rand_byte() {
    C=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null)
    printf "%d" "'\$C'"
}

BYTE_VAL=\$(rand_byte)
MOD_VAL=\$(expr \$BYTE_VAL % 253)
RAND_X=\$(expr \$MOD_VAL + 2)
RAND_IP="192.168.\$RAND_X.1"

sed -i "/config interface 'lan'/,/^config / s/^\(\s*option ipaddr\s*\).*/\1 '\$RAND_IP'/" "\$NETFILE"

echo ">>> 随机 LAN IP: \$RAND_IP"
#/etc/init.d/network reload
EOF_IP

chmod +x ${BASE_DIR}/ip.sh
echo "✅ 文件 ${BASE_DIR}/ip.sh 创建成功"


echo ""
echo "--- 2. 配置开机启动 (/etc/rc.local) ---"

if ! grep -q "Custom Randomization Scripts" "$RC_LOCAL"; then
    awk '
        /exit 0/ {
            print ""
            print "# --- START Custom Randomization Scripts ---"
            print "'${BASE_DIR}'/name.sh"
            print "'${BASE_DIR}'/mac.sh"
            print "#'${BASE_DIR}'/ip.sh"
            print "# --- END Custom Randomization Scripts ---"
            print "exit 0"
            next
        }
        { print }
    ' "$RC_LOCAL" > "$RC_LOCAL.tmp" && mv "$RC_LOCAL.tmp" "$RC_LOCAL"

    echo "✅ 已写入 rc.local"
else
    echo "⚠️ rc.local 中已存在启动配置，跳过"
fi


echo ""
echo "========================================"
echo "✨ 部署完成（脚本位于 ${BASE_DIR}，可被 OpenWrt 正常备份）"
echo "⚠️ MAC / IP 修改可能导致连接中断"
echo "========================================"
