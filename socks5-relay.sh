#!/bin/bash
set -e

echo "[1] 请输入 VLESS Reality 链接（vless://...）"
read -p "> " VLESS_URL

if [[ "$VLESS_URL" != vless://* ]]; then
  echo "❌ 链接格式不正确，请以 vless:// 开头"
  exit 1
fi

# 去除 # 后的标签部分
VLESS_URL_CLEAN=${VLESS_URL%%#*}

# 获取 uuid 和地址
URL_BODY=${VLESS_URL_CLEAN#vless://}
UUID=${URL_BODY%%@*}
ADDR_PARAM=${URL_BODY#*@}
SERVER_IP_PORT=${ADDR_PARAM%%\?*}
SERVER_IP=${SERVER_IP_PORT%%:*}
SERVER_PORT=${SERVER_IP_PORT##*:}
QUERY_STRING=${ADDR_PARAM#*\?}

# 手动解析参数
for kv in ${QUERY_STRING//&/ }; do
  key="${kv%%=*}"
  val="${kv#*=}"
  case "$key" in
    pbk) PUBLIC_KEY="$val" ;;
    sid) SHORT_ID="$val" ;;
    sni) SNI="$val" ;;
    path) PATH_ENC="$val" ;;
    host) HOST="$val" ;;
  esac
done

# 校验参数
if [[ -z "$UUID" || -z "$SERVER_IP" || -z "$SERVER_PORT" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" || -z "$SNI" ]]; then
  echo "❌ 无法从链接中解析出必要信息"
  exit 1
fi

echo "[2] 请输入本地 SOCKS5 监听端口（如 10808）："
read -p "> " SOCKS_PORT
if ! [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ 端口必须是数字"
  exit 1
fi

SOCKS_USER="ekf6SxFf"
SOCKS_PASS="l01uI3fS"
CONTAINER_NAME="xray-${SOCKS_PORT}"
WORKDIR="/opt/xray-socks5-${SOCKS_PORT}"
INFO_FILE="/root/${SOCKS_PORT}.txt"

# 获取公网 IP
echo "[3] 获取公网 IP..."
PUBLIC_IP=""
for url in \
  "https://api.ipify.org" \
  "https://ifconfig.me" \
  "https://ipinfo.io/ip" \
  "https://icanhazip.com" \
  "https://ident.me"
do
  PUBLIC_IP=$(timeout 5 curl -s "$url" || true)
  [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
done
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="127.0.0.1"

echo "[4] 创建工作目录 $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[5] 删除旧容器（如有）..."
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "[6] 写入 Xray 配置文件..."
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
      "network": "xhttp",
      "security": "reality",
      "realitySettings": {
        "serverName": "${SNI}",
        "fingerprint": "chrome",
        "publicKey": "${PUBLIC_KEY}",
        "shortId": "${SHORT_ID}",
        "show": false
      },
      "xhttpSettings": {
        "host": "${HOST:-$SNI}",
        "path": "/${SHORT_ID}?dw=2560",
        "mode": "stream-one"
      }
    }
  }]
}
EOF

echo "[7] 启动中转容器 ${CONTAINER_NAME}..."
docker run -d --name "${CONTAINER_NAME}" --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  docker.1panel.live/teddysun/xray xray -config /etc/xray/config.json

echo "[8] 启动完成 ✅ SOCKS5 代理信息如下："
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

echo "[9] 已保存信息到：$INFO_FILE"
