#!/bin/sh 
# [1] 检查镜像是否已存在
if docker image inspect hub.rat.dev/teddysun/xray:latest &>/dev/null; then
  echo "[1] xray 镜像已存在，跳过导入"
elif [ -f /root/xray.tar ]; then
  echo "[1] 本地已存在 /root/xray.tar，开始导入..."
  docker load -i /root/xray.tar
else
  echo "[1] 镜像不存在，尝试从远程下载 xray.tar..."

  # 尝试地址 1
  if curl -fsSL -o /root/xray.tar http://47.100.25.61:58080/xray.tar; then
    echo "[+] 成功从地址 1 下载"
  # 尝试地址 2
  elif curl -fsSL -o /root/xray.tar http://8.210.118.164:58080/xray.tar; then
    echo "[+] 成功从地址 2 下载"
  else
    echo "[✗] 两个地址都无法下载 xray.tar，退出"
    exit 1
  fi

  docker load -i /root/xray.tar
fi

set -e

SOCKS_PORT=54321
SOCKS_USER="ekf6SxFf"
SOCKS_PASS="l01uI3fS"
CONTAINER_NAME="xray-socks5"
WORKDIR="/opt/xray-socks5-server"
INFO_FILE="/root/socks.txt"

echo "[1] 设置 SOCKS5 监听端口为 ${SOCKS_PORT}"

# 获取公网 IP（仅 IPv4）
echo "[2] 获取公网 IP..."

PUBLIC_IP=""
IP_SOURCES=(
  "https://api64.ipify.org"
  "https://api.ipify.org"
  "https://ipv4.icanhazip.com"
  "https://ifconfig.me"
  "https://ip.sb"
  "https://checkip.amazonaws.com"
)

for URL in "${IP_SOURCES[@]}"; do
  IP=$(curl -s --max-time 3 "$URL" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
  if [ -n "$IP" ]; then
    PUBLIC_IP="$IP"
    echo "✅ 使用公网 IP 来源：$URL -> $PUBLIC_IP"
    break
  fi
done

if [ -z "$PUBLIC_IP" ]; then
  echo "⚠️ 无法从公网地址服务获取 IPv4，使用 127.0.0.1 替代"
  PUBLIC_IP="127.0.0.1"
fi


echo "[3] 创建工作目录 $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[4] 删除旧容器（如存在）..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker stop "$CONTAINER_NAME"
  docker rm "$CONTAINER_NAME"
fi

echo "[5] 生成 Xray 配置..."
cat > config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${SOCKS_PORT},
    "protocol": "socks",
    "settings": {
      "udp": true,
      "auth": "password",
      "accounts": [{
        "user": "${SOCKS_USER}",
        "pass": "${SOCKS_PASS}"
      }]
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

echo "[6] 启动 SOCKS5 服务端容器 ${CONTAINER_NAME}..."
docker run -d --name "${CONTAINER_NAME}" --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  hub.rat.dev/teddysun/xray xray -config /etc/xray/config.json

echo "[7] 启动成功 ✅"
echo "SOCKS5 服务端信息如下："
echo "--------------------------------------"
echo "地址     : ${PUBLIC_IP}"
echo "端口     : ${SOCKS_PORT}"
echo "用户名   : ${SOCKS_USER}"
echo "密码     : ${SOCKS_PASS}"
echo "链接     : socks5://${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP}:${SOCKS_PORT}"
echo "--------------------------------------"

cat > "$INFO_FILE" <<EOF
socks5://${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP}:${SOCKS_PORT}
EOF

echo "[8] SOCKS 链接已保存到：$INFO_FILE"
