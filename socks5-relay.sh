#!/bin/bash
set -e

echo "[1] 请输入 VLESS Reality 链接（vless://...）"
read -p "> " VLESS_URL

if [[ "$VLESS_URL" != vless://* ]]; then
  echo "❌ 链接格式不正确，请以 vless:// 开头"
  exit 1
fi

VLESS_URL_CLEAN=${VLESS_URL%%#*}
VLESS_BASE=$(echo "$VLESS_URL_CLEAN" | cut -d '/' -f 3)
UUID=$(echo "$VLESS_BASE" | cut -d '@' -f 1)
ADDR_PORT=$(echo "$VLESS_BASE" | cut -d '@' -f 2)
SERVER_IP=$(echo "$ADDR_PORT" | cut -d ':' -f 1)
SERVER_PORT=$(echo "$ADDR_PORT" | cut -d ':' -f 2 | cut -d '?' -f 1)

QUERY=$(echo "$VLESS_URL_CLEAN" | cut -d '?' -f 2)
PUBLIC_KEY=$(echo "$QUERY" | tr '&' '\n' | grep '^pbk=' | cut -d '=' -f 2)
SHORT_ID=$(echo "$QUERY" | tr '&' '\n' | grep '^sid=' | cut -d '=' -f 2)
SNI=$(echo "$QUERY" | tr '&' '\n' | grep '^sni=' | cut -d '=' -f 2)
PATH_ENC=$(echo "$QUERY" | tr '&' '\n' | grep '^path=' | cut -d '=' -f 2)
PATH=$(printf '%b' "${PATH_ENC//%/\\x}")
HOST=$(echo "$QUERY" | tr '&' '\n' | grep '^host=' | cut -d '=' -f 2)

if [[ -z "$UUID" || -z "$SERVER_IP" || -z "$SERVER_PORT" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" || -z "$SNI" || -z "$PATH" || -z "$HOST" ]]; then
  echo "❌ 无法完整解析链接"
  exit 1
fi

echo "[2] 请输入本地 SOCKS5 端口（例如 10808）"
read -p "> " SOCKS_PORT
[[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] || { echo "❌ 端口必须为数字"; exit 1; }

SOCKS_USER="ekf6SxFf"
SOCKS_PASS="l01uI3fS"
CONTAINER_NAME="xray-${SOCKS_PORT}"
WORKDIR="/opt/xray-socks5-${SOCKS_PORT}"
INFO_FILE="/root/${SOCKS_PORT}.txt"

echo "[3] 获取公网 IP..."
IP=""
for url in \
  "https://api.ipify.org" \
  "https://ifconfig.me" \
  "https://ipinfo.io/ip" \
  "https://icanhazip.com" \
  "https://ident.me"
do
    IP=$(timeout 5 curl -s "$url" || true)
    [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
done
[[ -z "$IP" ]] && IP="127.0.0.1"

echo "[4] 创建目录并清理旧容器..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "[5] 生成配置..."
cat > config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${SOCKS_PORT},
    "protocol": "socks",
    "settings": {
      "udp": true,
      "auth": "password",
      "accounts": [{ "user": "${SOCKS_USER}", "pass": "${SOCKS_PASS}" }]
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "${SERVER_IP}",
        "port": ${SERVER_PORT},
        "users": [{ "id": "${UUID}", "encryption": "none" }]
      }]
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "reality",
      "realitySettings": {
        "serverName": "${SNI}",
        "publicKey": "${PUBLIC_KEY}",
        "shortId": "${SHORT_ID}",
        "fingerprint": "chrome",
        "show": false
      },
      "xhttpSettings": {
        "host": "${HOST}",
        "path": "${PATH}",
        "mode": "stream-one"
      }
    }
  }]
}
EOF

echo "[6] 启动容器..."
docker run -d --name "${CONTAINER_NAME}" --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  hub.rat.dev/teddysun/xray xray -config /etc/xray/config.json

echo "[7] 启动完成 ✅ SOCKS5 代理信息如下："
cat <<EOF | tee "$INFO_FILE"
--------------------------------------
地址     : ${IP}
端口     : ${SOCKS_PORT}
用户名   : ${SOCKS_USER}
密码     : ${SOCKS_PASS}
--------------------------------------
EOF
echo "[8] 信息已保存到：$INFO_FILE"
