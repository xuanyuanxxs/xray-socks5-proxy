#docker安装
yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine

yum install -y yum-utils device-mapper-persistent-data lvm2

yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

yum makecache fast

#yum install -y docker-ce docker-ce-cli containerd.io

yum install -y docker
systemctl enable docker
systemctl start docker

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