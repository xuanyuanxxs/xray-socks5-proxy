#!/bin/bash
set -e

echo "[1] 请输入 VLESS Reality 链接（vless://...）"
read -p "> " VLESS_URL

if [[ "$VLESS_URL" != vless://* ]]; then
  echo "❌ 链接格式不正确，请以 vless:// 开头"
  exit 1
fi

# 去除标签部分
VLESS_URL_CLEAN=${VLESS_URL%%#*}
VLESS_BASE=$(echo "$VLESS_URL_CLEAN" | cut -d '/' -f 3)
UUID=$(echo "$VLESS_BASE" | cut -d '@' -f 1)
ADDR_PORT=$(echo "$VLESS_BASE" | cut -d '@' -f 2)
SERVER_IP=$(echo "$ADDR_PORT" | cut -d ':' -f 1)
SERVER_PORT_OR_PARAM=$(echo "$ADDR_PORT" | cut -d ':' -f 2)
SERVER_PORT=$(echo "$SERVER_PORT_OR_PARAM" | cut -d '?' -f 1)

QUERY=$(echo "$VLESS_URL_CLEAN" | cut -d '?' -f 2)
PUBLIC_KEY=$(echo "$QUERY" | tr '&' '\n' | grep '^pbk=' | cut -d '=' -f 2)
SHORT_ID=$(echo "$QUERY" | tr '&' '\n' | grep '^sid=' | cut -d '=' -f 2)
SNI=$(echo "$QUERY" | tr '&' '\n' | grep '^sni=' | cut -d '=' -f 2)

if [[ -z "$UUID" || -z "$SERVER_IP" || -z "$SERVER_PORT" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" || -z "$SNI" ]]; then
  echo "❌ 无法从链接中完整解析出必要信息"
  exit 1
fi

echo "[2] 请输入本地 SOCKS5 代理监听端口（例如 10808）"
read -p "> " SOCKS_PORT
if ! [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ 端口必须为数字"
  exit 1
fi

SOCKS_USER="ekf6SxFf"
SOCKS_PASS="l01uI3fS"
CONTAINER_NAME="xray-${SOCKS_PORT}"
WORKDIR="/opt/xray-socks5-${SOCKS_PORT}"
INFO_FILE="/root/${SOCKS_PORT}.txt"

# 获取公网 IP
echo "[3] 获取公网 IP..."
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == *"html"* ]]; then
  echo "⚠️ 无法获取公网 IP，使用 127.0.0.1 替代"
  PUBLIC_IP="127.0.0.1"
fi

echo "[4] 创建工作目录 $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[5] 删除旧容器（如存在）..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker stop "$CONTAINER_NAME"
  docker rm "$CONTAINER_NAME"
fi

echo "[6] 生成 Xray 配置..."
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
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${SERVER_IP}",
        "port": ${SERVER_PORT},
        "users": [{
          "id": "${UUID}",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "${SNI}",
        "fingerprint": "chrome",
        "publicKey": "${PUBLIC_KEY}",
        "shortId": "${SHORT_ID}",
        "show": false
      }
    }
  }]
}
EOF

echo "[7] 启动中转容器 ${CONTAINER_NAME}..."
docker run -d --name "${CONTAINER_NAME}" --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  hub.rat.dev/teddysun/xray xray -config /etc/xray/config.json

echo "[8] 启动成功 ✅"
echo "SOCKS5 代理信息如下："
echo "--------------------------------------"
echo "地址     : ${PUBLIC_IP}"
echo "端口     : ${SOCKS_PORT}"
echo "用户名   : ${SOCKS_USER}"
echo "密码     : ${SOCKS_PASS}"
echo "--------------------------------------"

cat > "$INFO_FILE" <<EOF
SOCKS5 代理信息：
地址     : ${PUBLIC_IP}
端口     : ${SOCKS_PORT}
用户名   : ${SOCKS_USER}
密码     : ${SOCKS_PASS}
EOF

echo "[9] SOCKS5 信息已保存到：$INFO_FILE"
