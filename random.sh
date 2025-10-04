#!/bin/sh
set -e

# --- 1. 定义脚本内容和文件名 ---

# name.sh - 随机生成主机名并应用
NAME_SCRIPT_CONTENT='
#!/bin/sh

# 定义配置文件路径
SYSTEM_CONFIG="/etc/config/system"

# --- 1. 生成随机的6个小写字母 ---
# /dev/urandom 生成随机字节
# tr -dc '\''a-z'\'' 过滤出小写字母
# head -c 6 截取前6个字符
NEW_HOSTNAME=$(tr -dc '\''a-z'\'' < /dev/urandom | head -c 6)

echo "✅ 生成新的主机名: ${NEW_HOSTNAME}"

# --- 2. 使用 uci 修改配置 ---
# uci set [section].[option]=[value] 用于设置配置项
# system.@system[0].hostname 代表: system 配置块的第一个 (索引 0) 的 hostname 选项
uci set system.@system[0].hostname="${NEW_HOSTNAME}"

echo "📝 配置修改成功: ${SYSTEM_CONFIG} 中的 option hostname 已更新。"

# --- 3. 提交更改并应用 ---
# uci commit 提交配置到文件
uci commit system

# 重载 system 服务以应用新的主机名
/etc/init.d/system reload

echo "✨ 新的主机名已应用。"
echo "请注意：部分系统名称可能需要重启网络或设备后才能在局域网中完全生效。"

# --- 4. 验证 (使用 uci get 替代 hostname 命令) ---
echo "--- 验证 ---"
uci get system.@system[0].hostname

'

# mac.sh - 随机生成 MAC 地址并应用
MAC_SCRIPT_CONTENT='
#!/bin/sh
set -e

NETFILE="/etc/config/network"

# 从 /dev/urandom 读一个字节 (0-255)
rand_byte() {
    # 读一个字节，转成十进制
    C=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null)
    printf '%d' "'\''$C'\''"
}

# 生成随机 MAC (02 开头 = 本地管理)
RAND_MAC=$(printf "02:%02X:%02X:%02X:%02X:%02X" \
  $(rand_byte) $(rand_byte) $(rand_byte) $(rand_byte) $(rand_byte))

# 修改所有的 macaddr
sed -i "s/^\(\s*option macaddr\s*\).*/\1 '\''$RAND_MAC'\''/" "$NETFILE"
echo ">>> 随机 MAC: $RAND_MAC"

echo ">>> 修改完成，已更新 $NETFILE"

# 应用配置
/etc/init.d/network reload

'

# ip.sh - 随机生成 LAN IP 地址并应用
IP_SCRIPT_CONTENT='
#!/bin/sh
set -e

NETFILE="/etc/config/network"

# 从 /dev/urandom 读一个字节 (0-255) - 确保 rand_byte 存在
rand_byte() {
    # 读一个字节，转成十进制
    C=$(dd if=/dev/urandom bs=1 count=1 2>/dev/null)
    printf '%d' "'\''$C'\''"
}

# 生成随机 LAN IP (192.168.2.1 - 192.168.254.1)
# 排除 0 和 1 (0 和 255 留给特殊地址，这里简单地限制在 2-254)
RAND_X=$(( $(rand_byte) % 253 + 2 ))
RAND_IP="192.168.$RAND_X.1"

# 修改 LAN 段的 ipaddr
sed -i "/config interface '\''lan'\'',/^config / s/^\(\s*option ipaddr\s*\).*/\1 '\''$RAND_IP'\''/" "$NETFILE"
echo ">>> 随机 LAN IP: $RAND_IP"

echo ">>> 修改完成，已更新 $NETFILE"

# 应用配置
/etc/init.d/network reload

'

SCRIPT_FILES=("name.sh" "mac.sh" "ip.sh")
SCRIPT_CONTENTS=("$NAME_SCRIPT_CONTENT" "$MAC_SCRIPT_CONTENT" "$IP_SCRIPT_CONTENT")
RC_LOCAL="/etc/rc.local"

# --- 2. 创建并写入脚本文件 ---
echo "--- 1. 正在创建并写入脚本文件到 /etc/ ---"

for i in "${!SCRIPT_FILES[@]}"; do
    FILE_NAME=${SCRIPT_FILES[$i]}
    CONTENT=${SCRIPT_CONTENTS[$i]}
    FILE_PATH="/etc/$FILE_NAME"

    # 使用 echo 和 here string (<<<) 写入内容，确保内容的精确度
    echo "$CONTENT" > "$FILE_PATH"
    chmod +x "$FILE_PATH"

    echo "✅ 文件 ${FILE_PATH} 创建成功并已设置执行权限。"
done

# --- 3. 配置开机启动 ---
echo ""
echo "--- 2. 正在配置开机启动 (/etc/rc.local) ---"

# 要添加到 rc.local 的执行命令
AUTORUN_COMMANDS='
# --- START Custom Randomization Scripts ---
# 随机主机名
/etc/name.sh
# 随机 MAC 地址
/etc/mac.sh
# 随机 LAN IP 地址
/etc/ip.sh
# --- END Custom Randomization Scripts ---
'
INSERT_MARKER='exit 0'

# 检查标记是否存在，防止重复添加
if ! grep -q "Randomization Scripts" "$RC_LOCAL"; then
    # 查找 exit 0 行，并在其前插入启动命令
    sed -i "/$INSERT_MARKER/i$AUTORUN_COMMANDS" "$RC_LOCAL"
    echo "✅ 成功将三个脚本的启动命令添加到 ${RC_LOCAL}。"
else
    echo "⚠️ 启动命令已存在于 ${RC_LOCAL}，跳过添加。"
fi

# --- 4. 运行一次进行测试和初始化 ---
echo ""
echo "--- 3. 正在立即运行脚本进行初始化测试 (请注意网络中断) ---"
echo "--- 运行 /etc/name.sh ---"
/etc/name.sh
echo "--- 运行 /etc/mac.sh ---"
/etc/mac.sh
echo "--- 运行 /etc/ip.sh ---"
/etc/ip.sh

echo ""
echo "========================================"
echo "✨ 恭喜！一键部署和配置已完成！"
echo "🎉 新的**主机名、MAC地址和LAN IP地址**已随机生成并应用。"
echo "🚀 它们已被设置为**开机自动运行**。"
echo "💡 请注意：应用新的 **LAN IP** 可能会导致当前 SSH 连接中断，您需要使用新的 IP 重新连接。"
echo "========================================"
