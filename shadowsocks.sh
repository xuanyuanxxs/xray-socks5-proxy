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
  if curl -fsSL -o /root/xray.tar http://8.210.118.164:58080/xray.tar; then
    echo "[+] 成功从地址 1 下载"
  # 尝试地址 2
  elif curl -fsSL -o /root/xray.tar http://47.100.25.61:58080/xray.tar; then
    echo "[+] 成功从地址 2 下载"
  else
    echo "[✗] 两个地址都无法下载 xray.tar，退出"
    exit 1
  fi

  docker load -i /root/xray.tar
fi

set -e

SS_PORT=25432
SS_METHOD="chacha20-ietf-poly1305"
SS_PASSWORD="XK9fd1Jw"
CONTAINER_NAME="xray-ss-server"
WORKDIR="/opt/xray-ss-server"
INFO_FILE="/root/shadowsocks.txt"

echo "[1] 设置 Shadowsocks 监听端口为 ${SS_PORT}"

# 获取公网 IP
echo "[2] 获取公网 IP..."
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
if [ -z "$PUBLIC_IP" ] || echo "$PUBLIC_IP" | grep -q "html"; then
  echo "⚠️ 无法获取公网 IP，使用 127.0.0.1 替代"
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
    "port": ${SS_PORT},
    "protocol": "shadowsocks",
    "settings": {
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}",
      "network": "tcp,udp"
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

echo "[6] 启动 Shadowsocks 服务端容器 ${CONTAINER_NAME}..."
docker run -d --name "${CONTAINER_NAME}" --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  hub.rat.dev/teddysun/xray xray -config /etc/xray/config.json

echo "[7] 启动成功 ✅"
echo "Shadowsocks 服务端信息如下："
echo "--------------------------------------"
echo "地址     : ${PUBLIC_IP}"
echo "端口     : ${SS_PORT}"
echo "加密方式 : ${SS_METHOD}"
echo "密码     : ${SS_PASSWORD}"
echo "链接     : ss://$(echo -n "${SS_METHOD}:${SS_PASSWORD}@${PUBLIC_IP}:${SS_PORT}" | base64 -w0)"
echo "--------------------------------------"

cat > "$INFO_FILE" <<EOF
ss://$(echo -n "${SS_METHOD}:${SS_PASSWORD}@${PUBLIC_IP}:${SS_PORT}" | base64 -w0)
EOF

echo "[8] SS 链接已保存到：$INFO_FILE"
