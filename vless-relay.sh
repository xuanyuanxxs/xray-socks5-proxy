#!/bin/bash
set -e

WORKDIR="/opt/xray-reality"
echo "[1] 创建工作目录 $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
echo "[2] 当前目录：$(pwd)"

# 生成随机端口（20000-60000）
PORT=$((RANDOM % 40000 + 20000))
echo "[3] 随机生成代理端口: $PORT"

SNI="weixin.qq.com"
SHORT_ID=$(openssl rand -hex 8)
echo "[4] 生成 SHORT_ID: $SHORT_ID"

echo "[5] 获取公网 IP..."
IP=""
for url in \
  "https://api.ipify.org" \
  "https://ifconfig.me" \
  "https://ipinfo.io/ip" \
  "https://icanhazip.com" \
  "https://ident.me"
do
    echo "尝试获取 IP：$url"
    IP=$(timeout 5 curl -s "$url" || true)
    if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "✅ 获取公网 IP: $IP"
        break
    fi
done

if [[ -z "$IP" || "$IP" != *.* ]]; then
    echo "❌ 获取公网 IP 失败，脚本终止"
    exit 1
fi

echo "[6] 生成 Reality 密钥对..."
REALITY_KEY=$(docker run --rm docker.1panel.live/teddysun/xray xray x25519)
echo "$REALITY_KEY"

PRIVATE_KEY=$(echo "$REALITY_KEY" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$REALITY_KEY" | grep "Public key" | awk '{print $3}')
echo "[6] Private Key: $PRIVATE_KEY"
echo "[6] Public Key: $PUBLIC_KEY"

UUID=$(uuidgen)
echo "[7] 生成 UUID: $UUID"

echo "[8] 生成配置文件..."
cat > config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "${UUID}"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${SNI}:443",
        "xver": 0,
        "serverNames": ["${SNI}"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}"]
      },
      "xhttpSettings": {
        "host": "${SNI}",
        "path": "/${SHORT_ID}?dw=2560",
        "mode": "stream-one"
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

if [ -f config.json ]; then
  echo "[8] 配置文件生成成功"
else
  echo "❌ 配置文件生成失败！"
  exit 1
fi

echo "[9] 检查旧容器..."
if docker ps -a --format '{{.Names}}' | grep -q '^xray-reality$'; then
  echo "[9] 停止并删除旧容器"
  docker stop xray-reality
  docker rm xray-reality
fi

echo "[10] 启动容器..."
docker run -d --name xray-reality --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  docker.1panel.live/teddysun/xray xray -config /etc/xray/config.json

VLESS_LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=%2F${SHORT_ID}%3Fdw%3D2560&host=${SNI}#Xray-Reality"

echo "[11] 启动完成！代理信息如下："
echo "--------------------------------------"
echo "IP       : ${IP}"
echo "端口     : ${PORT}"
echo "UUID     : ${UUID}"
echo "PublicKey: ${PUBLIC_KEY}"
echo "ShortID  : ${SHORT_ID}"
echo "SNI      : ${SNI}"
echo ""
echo "客户端链接："
echo "$VLESS_LINK"
echo "--------------------------------------"

# 保存到 /root/vless.txt
echo "$VLESS_LINK" > /root/vless.txt
echo "[12] VLESS 链接已保存到 /root/vless.txt"
