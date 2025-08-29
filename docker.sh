#!/bin/bash
set -e

# ========== [Docker 安装] ==========
echo "[*] 安装 Docker..."
yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast

yum install -y docker
systemctl enable docker
systemctl start docker

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
