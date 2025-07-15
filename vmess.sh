#!/bin/bash
set -e

WORKDIR="/etc/xray-vmess"
echo "[1] 创建工作目录 $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
echo "[2] 当前目录：$(pwd)"

PORT=$((RANDOM % 40000 + 20000))
echo "[3] 随机生成端口: $PORT"

UUID=$(uuidgen)
echo "[4] 生成 UUID: $UUID"

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

if [[ -z "$IP" ]]; then
    echo "❌ 获取公网 IP 失败，脚本终止"
    exit 1
fi

echo "[6] 写入配置文件 config.json"
cat > config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": ${PORT},
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "${UUID}",
        "alterId": 0,
        "security": "none"
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "none"
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

if [ ! -f config.json ]; then
    echo "❌ 配置文件写入失败"
    exit 1
fi

echo "[7] 清理旧容器"
docker rm -f xray-vmess >/dev/null 2>&1 || true

echo "[8] 启动新容器"
docker run -d --name xray-vmess --network host \
  --restart unless-stopped \
  -v "$(pwd)/config.json:/etc/xray/config.json:ro" \
  hub.rat.dev/teddysun/xray xray -config /etc/xray/config.json

echo "[9] 生成 VMess 链接"
VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "vmess-tcp",
  "add": "${IP}",
  "port": "${PORT}",
  "id": "${UUID}",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "",
  "sni": "",
  "alpn": "",
  "scy": "none"
}
EOF
)

VMESS_LINK="vmess://$(echo "$VMESS_JSON" | base64 -w 0)"

echo "✅ VMess 启动完成，配置信息如下："
echo "--------------------------------------"
echo "IP       : $IP"
echo "端口     : $PORT"
echo "UUID     : $UUID"
echo "客户端链接："
echo "$VMESS_LINK"
echo "--------------------------------------"

echo "$VMESS_LINK" > /root/vmess.txt
echo "✅ 已保存到 /root/vmess.txt"
