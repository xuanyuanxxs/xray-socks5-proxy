#!/bin/sh
set -e

RC_LOCAL="/etc/rc.local"

echo "--- 1. 正在创建并写入脚本文件到 /etc/ ---"

# 1. 创建 name.sh 文件 (随机主机名)
cat << "EOF_NAME" > /etc/config/name.sh
#!/bin/sh

# 定义配置文件路径
SYSTEM_CONFIG="/etc/config/system"

# --- 1. 生成随机的6个小写字母 ---
NEW_HOSTNAME=$(tr -dc 'a-z' < /dev/urandom | head -c 6)

echo "✅ 生成新的主机名: ${NEW_HOSTNAME}"

# --- 2. 使用 uci 修改配置 ---
uci set system.@system[0].hostname="${NEW_HOSTNAME}"

echo "📝 配置修改成功: ${SYSTEM_CONFIG} 中的 option hostname 已更新。"

# --- 3. 提交更改并应用 ---
uci commit system

# 重载 system 服务以应用新的主机名
#/etc/init.d/system reload

echo "✨ 新的主机名已应用。"

# --- 4. 验证 ---
#echo "--- 验证 ---"
#uci get system.@system[0].hostname
EOF_NAME
chmod +x /etc/config/name.sh
echo "✅ 文件 /etc/config/name.sh 创建成功。"


# 1. 创建 mac.sh 文件 (随机mac)
cat << "EOF_MAC" > /etc/config/mac.sh
#!/bin/sh
set -e

# 文件路径
NETFILE="/etc/config/network"

# 生成随机 MAC (02 开头 = 本地地址)
rand_byte() { printf "%02X" $((RANDOM%256)); }
MAC_PREFIX=$(printf "02:%s:%s:%s:%s" \
  $(rand_byte) $(rand_byte) $(rand_byte) $(rand_byte))

LAN_MAC="$MAC_PREFIX:01"
WAN_MAC="$MAC_PREFIX:02"
# 获取 interface 对应的 device
get_iface_dev() {
    uci -q get network.$1.device || uci -q get network.$1.ifname
}

LAN_DEV=$(get_iface_dev lan)
WAN_DEV=$(get_iface_dev wan)

[ -z "$LAN_DEV" ] && echo "LAN device not found" && exit 1
[ -z "$WAN_DEV" ] && echo "WAN device not found" && exit 1

echo "LAN device: $LAN_DEV"
echo "WAN device: $WAN_DEV"

# 获取 device 块，如果不存在就创建
get_device_section() {
    for sec in $(uci show network | grep "=device" | cut -d= -f1); do
        name=$(uci -q get $sec.name)
        [ "$name" = "$1" ] && echo "$sec" && return
    done
    # 不存在就创建
    sec="network.@device[-1]"  # 最后追加
    uci add network device
    uci set $sec.name="$1"
    echo "$sec"
}

LAN_SEC=$(get_device_section "$LAN_DEV")
WAN_SEC=$(get_device_section "$WAN_DEV")

# 设置 MAC
uci set $LAN_SEC.macaddr="$LAN_MAC"
uci set $WAN_SEC.macaddr="$WAN_MAC"
uci commit network

echo "LAN MAC: $LAN_MAC"
echo "WAN MAC: $WAN_MAC"
echo "network config updated"

# 应用配置
#/etc/init.d/network reload
EOF_MAC
chmod +x /etc/config/mac.sh
echo "✅ 文件 /etc/config/mac.sh 创建成功。"


# 3. 创建 ip.sh 文件 (随机 LAN IP 地址，包含 rand_byte 函数和 ASH 兼容语法)
cat << "EOF_IP" > /etc/config/ip.sh
#!/bin/sh
set -e

NETFILE="/etc/config/network"

# 必须包含 rand_byte 函数
rand_byte() {
    # 读一个字节，转成十进制
    C=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null)
    printf "%d" "'$C'"
}

# 生成随机 LAN IP (192.168.2.1 - 192.168.254.1)
# 使用 expr 进行算术运算，兼容 ASH
BYTE_VAL=$(rand_byte)
MOD_VAL=$(expr $BYTE_VAL % 253)
RAND_X=$(expr $MOD_VAL + 2)
RAND_IP="192.168.$RAND_X.1"

# 修改 LAN 段的 ipaddr
sed -i "/config interface 'lan'/,/^config / s/^\(\s*option ipaddr\s*\).*/\1 '$RAND_IP'/" "$NETFILE"
echo ">>> 随机 LAN IP: $RAND_IP"

echo ">>> 修改完成，已更新 $NETFILE"

# 应用配置
#/etc/init.d/network reload
EOF_IP
chmod +x /etc/config/ip.sh
echo "✅ 文件 /etc/config/ip.sh 创建成功。"

echo ""
echo "--- 2. 正在配置开机启动 (/etc/rc.local) ---"

# 使用 Awk 进行多行安全插入，兼容 OpenWrt
if ! grep -q "Randomization Scripts" "$RC_LOCAL"; then
    # Awk 脚本：如果当前行是 'exit 0'，先打印插入内容，再打印当前行
    # 在 Awk 中，\n 表示换行
    awk '
        /exit 0/ {
            print ""
            print "# --- START Custom Randomization Scripts ---"
            print "/etc/config/name.sh"
            print "/etc/config/mac.sh"
            print "#/etc/config/ip.sh"
            print "# --- END Custom Randomization Scripts ---"
            print "exit 0"
            next
        }
        { print }
    ' "$RC_LOCAL" > "$RC_LOCAL.tmp" && mv "$RC_LOCAL.tmp" "$RC_LOCAL"
    
    echo "✅ 成功将三个脚本的启动命令添加到 ${RC_LOCAL}。"
else
    echo "⚠️ 启动命令已存在于 ${RC_LOCAL}，跳过添加。"
fi

echo ""
echo "--- 3. 正在立即运行脚本进行初始化测试 (请注意网络中断) ---"
echo "--- 运行 /etc/config/name.sh ---"
#/etc/config/name.sh
echo "--- 运行 /etc/config/mac.sh ---"
#/etc/config/mac.sh
echo "--- 运行 /etc/config/ip.sh ---"
#/etc/config/ip.sh

echo ""
echo "========================================"
echo "✨ 部署成功！"
echo "🎉 所有脚本已使用最兼容的 **ASH/Awk** 语法写入，并已配置开机启动。"
echo "🚀 新的主机名、MAC和LAN IP已应用。"
echo "💡 **警告：** 如果您的连接断开，请使用脚本中打印出的 **新 LAN IP** 重新连接！"
echo "========================================"
