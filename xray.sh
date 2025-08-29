#!/bin/bash 
set -e

# 自动检测是否为阿里云软件源
echo ">>> 正在检测是否使用阿里云软件源..."
if ! grep -q "aliyun" /etc/yum.repos.d/*.repo 2>/dev/null; then
  echo "⚠️ 当前未使用阿里云软件源，开始更换..."
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/repo.sh)"
else
  echo "✅ 当前系统已使用阿里云软件源"
fi

# 自动检测是否安装 Docker
echo ">>> 正在检测 Docker 是否已安装..."
if ! command -v docker &>/dev/null; then
  echo "⚠️ Docker 未安装，开始安装..."
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/docker.sh)"
else
  echo "✅ Docker 已安装：$(docker --version)"
fi

#自动检测xray是否已下载
# ========== [Xray 镜像检查与拉取] ==========
IMAGE_NAME="hub.rat.dev/teddysun/xray:latest"
MIRRORS=(
  "hub.rat.dev/teddysun/xray:latest"
  "cf-workers-docker-io-95s.pages.dev/teddysun/xray:latest"
  "docker.061757.xyz/teddysun/xray:latest"
)

echo "[*] 检查镜像是否已存在..."
if docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "[1] 镜像已存在：$IMAGE_NAME，跳过拉取"
elif [ -f /root/xray.tar ]; then
  echo "[1] 本地已有 /root/xray.tar，开始导入..."
  docker load -i /root/xray.tar
else
  echo "[*] 镜像不存在，开始尝试 docker pull..."

  PULL_SUCCESS=0
  for mirror in "${MIRRORS[@]}"; do
    echo "  → 尝试拉取 $mirror ..."
    if docker pull "$mirror"; then
      echo "[+] 成功拉取 $mirror"
      docker tag "$mirror" "$IMAGE_NAME"
      PULL_SUCCESS=1
      break
    else
      echo "[✗] 拉取 $mirror 失败"
    fi
  done

  if [ $PULL_SUCCESS -eq 0 ]; then
    echo "[!] 所有 registry 拉取失败，改为尝试 http 下载..."

    if curl -fsSL -o /root/xray.tar http://47.100.25.61:58080/xray.tar; then
      echo "[+] 成功从地址 1 下载"
    elif curl -fsSL -o /root/xray.tar http://8.210.118.164:58080/xray.tar; then
      echo "[+] 成功从地址 2 下载"
    else
      echo "[✗] 两个地址都无法下载 xray.tar，退出"
      exit 1
    fi

    docker load -i /root/xray.tar
  fi
fi

echo "[✓] Xray 镜像准备完成：$IMAGE_NAME"

# 菜单部分
echo "================== Xray 节点部署 =================="
echo "请选择要执行的操作（可多选，用空格分隔）："
echo "  1) 安装 SOCKS 服务端"
echo "  2) 安装 VLESS 服务端"
echo "  3) 安装 VMess 服务端"
echo "  4) 安装 Shadowsocks 服务端"
echo "  5) 部署 中转节点"
echo "=================================================="
read -rp "请输入对应编号（多个用空格分隔）[1-5]：" input


for choice in $input; do
    case "$choice" in
    1)
        echo ">>> [1] 部署 SOCKS5 服务端"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/socks.sh)"
        echo ">>> 部署完成"
        ;;
    2)
        echo ">>> [2] 部署 VLESS 服务端"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/vless.sh)"
        echo ">>> 部署完成"
        ;;
    3)
        echo ">>> [3] 部署 VMess 服务端"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/vmess.sh)"
        echo ">>> 部署完成"
        ;;
    4)
        echo ">>> [4] 部署 Shadowsocks 服务端"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/shadowsocks.sh)"
        echo ">>> 部署完成"
        ;;
    5)
        echo ">>> [5] 部署中转节点"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/xuanyuanxxs/xray-socks5-proxy/main/xray-transfer.sh)"
        ;;
    *)
        echo "❌ 无效选项：$choice，跳过。"
        ;;
    esac
done
