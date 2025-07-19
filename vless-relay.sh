#!/bin/bash
set -e

# [0] 检查并安装 Docker（仅适用于 CentOS 7）
if ! command -v docker &> /dev/null; then
  echo "[0] Docker 未安装，开始使用 yum 安装..."
  yum install -y docker
  systemctl start docker
  systemctl enable docker
  echo "[0] Docker 安装完成并已启动"
else
  echo "[0] Docker 已安装，确保服务已启用"
  systemctl start docker
  systemctl enable docker
fi

# [1] 检查镜像是否已存在
if docker image inspect hub.rat.dev/teddysun/xray:latest &>/dev/null; then
  echo "[1] xray 镜像已存在，跳过导入"
elif [ -f /root/xray.tar ]; then
  echo "[1] 本地已存在 /root/xray.tar，开始导入..."
  docker load -i /root/xray.tar
else
  echo "[1] 镜像不存在，尝试从远程下载 xray.tar..."
  curl -L -o /root/xray.tar http://8.210.118.164:58080/xray.tar
  docker load -i /root/xray.tar
fi

# 设置工作目录
WORKDIR="/opt/xray-reality"
echo "[2] 创建工作目录 $WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
echo "[3] 当前目录：$(pwd)"

# 随机端口与 ID
PORT=$((RANDOM % 40000 + 20000))
UUID=$(uuidgen)
SHORT_ID=$(openssl rand -hex 8)
SNI="weixin.qq.com"

echo "[4] 生成 UUID: $UUID"
echo "[4] 生成 SHORT_ID: $SHORT_ID"

# 获取公网 IP
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

# 生成 Reality 密钥对
echo "[6] 生成 Reality 密钥对..."
REALITY_KEY=$(docker run --rm hub.rat.dev/teddysun/xray xray x25519)
PRIVATE_KEY=$(echo "$REALITY_KEY" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$REALITY_KEY" | grep "Public key" | awk '{print $3}')

echo "[6] Private Key: $PRIVATE_KEY"
echo "[6] Public Key: $PUBLIC_KEY"

# 配置文件生成
echo "[7] 生成配置文件..."
cat > config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}" }],
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
  echo "[7] 配置文件生成成功"
else
  echo "❌ 配置文件生成失败！"
  exit 1
fi

# 删除旧容器
echo "[8] 检查旧容器..."
if docker ps -a --format '{{.Names}}' | grep -q '^xray-reality$'; then
  echo "[8] 停止并删除旧容器"
  docker stop xray-reality
  docker rm xray-reality
fi

# 启动新容器
echo "[9] 启动容器..."
docker run -d --name xray-reality --network host \
  --restart unless-stopped \
  -v "$WORKDIR/config.json":/etc/xray/config.json:ro \
  hub.rat.dev/teddysun/xray xray -config /etc/xray/config.json

# 输出连接信息
VLESS_LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=%2F${SHORT_ID}%3Fdw%3D2560&host=${SNI}#Xray-Reality"

echo "[10] 启动完成！代理信息如下："
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
echo "[11] VLESS 链接已保存到 /root/vless.txt"
