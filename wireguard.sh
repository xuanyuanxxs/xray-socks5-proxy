#!/bin/bash
set -e
# ====== 换源 ======
# 检测系统 codename
if [ -r /etc/os-release ]; then
    . /etc/os-release
    CODENAME=$(echo "$VERSION_CODENAME")
fi

# 如果没取到 codename，再 fallback
if [ -z "$CODENAME" ] && [ -r /etc/debian_version ]; then
    DEB_VER=$(cut -d'.' -f1 /etc/debian_version)
    case $DEB_VER in
        11) CODENAME="bullseye" ;;
        12) CODENAME="bookworm" ;;
        *) CODENAME="stable" ;;
    esac
fi

echo ">>> 检测到系统版本: $CODENAME"
echo ">>> 正在将源更换为阿里云..."

cat > /etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/debian/ $CODENAME main contrib non-free
deb http://mirrors.aliyun.com/debian/ $CODENAME-updates main contrib non-free
deb http://mirrors.aliyun.com/debian-security $CODENAME-security main contrib non-free
EOF

echo ">>> 更新软件包索引..."
apt update -y
echo ">>> 换源完成 ✅"
#启用内核转发
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward)

if [ "$IP_FORWARD" -eq 1 ]; then
    echo "内核 IP 转发已开启，继续执行后续操作..."
else
    echo "内核 IP 转发未开启，正在开启..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
fi
echo ">>> 启用内核转发 ✅"
# ====== 颜色变量 ======
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_bai='\033[0m'

# ====== 常用函数 ======
break_end() {
    echo -e "${gl_lv}操作完成${gl_bai}"
    echo "按任意键继续..."
    read -n 1 -s -r -p ""
    echo ""
    #clear
}

ip_address() {
    get_public_ip() {
        curl -s https://ipinfo.io/ip && echo
    }
    get_local_ip() {
        ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || \
        hostname -I 2>/dev/null | awk '{print $1}' || \
        ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1
    }
    public_ip=$(get_public_ip)
    isp_info=$(curl -s --max-time 3 http://ipinfo.io/org)
    if echo "$isp_info" | grep -Eiq 'mobile|unicom|telecom'; then
        ipv4_address=$(get_local_ip)
    else
        ipv4_address="$public_ip"
    fi
    ipv6_address=$(curl -s --max-time 1 https://v6.ipinfo.io/ip && echo)
}

# ====== 安装 Docker（自动切换镜像源） ======
install_docker() {
    if command -v docker &>/dev/null; then
        echo -e "${gl_lv}Docker 已安装，跳过...${gl_bai}"
        return
    fi
    echo -e "${gl_huang}正在安装 Docker 环境...${gl_bai}"

    if command -v apt &>/dev/null; then
        apt update -y
        apt install -y curl ca-certificates gnupg lsb-release
        echo -e "${gl_huang}尝试官方 get.docker.com 脚本安装...${gl_bai}"
        if curl -fsSL https://get.docker.com | sh; then
            echo -e "${gl_lv}Docker 官方安装成功${gl_bai}"
        else
            echo -e "${gl_huang}官方源安装失败，切换到清华镜像源...${gl_bai}"
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian \
              $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update
            apt install -y docker-ce docker-ce-cli containerd.io
            systemctl enable docker
            systemctl start docker
        fi

    elif command -v yum &>/dev/null; then
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
        systemctl enable docker
        systemctl start docker

    elif command -v dnf &>/dev/null; then
        dnf install -y dnf-plugins-core
        dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
        systemctl enable docker
        systemctl start docker

    elif command -v apk &>/dev/null; then
        apk add docker docker-openrc
        rc-update add docker boot
        service docker start

    else
        echo "不支持的发行版，请手动安装 Docker"
        exit 1
    fi
}

# ====== WireGuard 部署 ======
deploy_wireguard() {
    local docker_name="wireguard"
    local docker_img="lscr.io/linuxserver/wireguard:latest"

    # 用户输入端口
    read -e -p "请输入 WireGuard 服务端口 (默认 51820): " WG_PORT
    WG_PORT=${WG_PORT:-51820}

    # 固定客户端数量为 1
    COUNT=1
    PEERS="wg01"

    # 固定网段为 10.13.13.0
    NETWORK="10.13.13.0"

    ip link delete wg0 &>/dev/null || true

    ip_address
    #检测镜像是否存在，不存在则拉取镜像
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -wq "$docker_img"; then
        echo "镜像 $docker_img 已存在，继续执行后续操作..."
    else
        echo "镜像 $docker_img不存在，开始拉取镜像..."
    docker pull docker.061757.xyz/linuxserver/wireguard:latest
    docker tag docker.061757.xyz/linuxserver/wireguard:latest $docker_img
    fi
    if docker ps -a --format '{{.Names}}' | grep -wq wireguard; then
        echo "检测到已存在 wireguard 容器，正在删除..."
    docker rm -f wireguard
    else
        echo "未检测到 wireguard 容器，继续执行后续操作..."
    fi
    echo "镜像 $docker_img拉取完成，开始部署wireguard..."

    docker run -d \
      --name=$docker_name \
      --network host \
      --cap-add=NET_ADMIN \
      --cap-add=SYS_MODULE \
      -e PUID=1000 \
      -e PGID=1000 \
      -e TZ=Etc/UTC \
      -e SERVERURL=${ipv4_address} \
      -e SERVERPORT=$WG_PORT \
      -e PEERS=${PEERS} \
      -e INTERNAL_SUBNET=${NETWORK} \
      -e ALLOWEDIPS=${NETWORK}/24 \
      -e PERSISTENTKEEPALIVE_PEERS=all \
      -e LOG_CONFS=true \
      -v /home/docker/wireguard/config:/config \
      -v /lib/modules:/lib/modules \
      --restart=always \
      $docker_img

    sleep 3

    docker exec $docker_name sh -c "
    f='/config/wg_confs/wg0.conf'
    sed -i 's/51820/${WG_PORT}/g' \$f
    "
    docker exec $docker_name sh -c "
    for d in /config/peer_*; do
      sed -i 's/51820/${WG_PORT}/g' \$d/*.conf
    done
    "
    docker exec $docker_name sh -c '
    for d in /config/peer_*; do
      sed -i "/^DNS/d" "$d"/*.conf
    done
    '
    docker exec $docker_name sh -c '
    for d in /config/peer_*; do
      for f in "$d"/*.conf; do
        grep -q "^PersistentKeepalive" "$f" || \
        sed -i "/^AllowedIPs/ a PersistentKeepalive = 25" "$f"
      done
    done
    '
    docker exec -it $docker_name bash -c '
    for d in /config/peer_*; do
      cd "$d" || continue
      conf_file=$(ls *.conf)
      base_name="${conf_file%.conf}"
      qrencode -o "$base_name.png" < "$conf_file"
    done
    '
    sed -i 's/-o eth+/-o e+/g' /home/docker/wireguard/config/wg_confs/wg0.conf

    docker restart $docker_name

    echo
    echo -e "${gl_huang}客户端二维码配置:${gl_bai}"
    docker exec -it $docker_name bash -c '/app/show-peer wg01'
    echo
    echo -e "${gl_huang}客户端配置代码:${gl_bai}"
    docker exec $docker_name sh -c 'cat /config/peer_wg01/*.conf'
    echo -e "${gl_lv}客户端配置已生成，可通过二维码或复制配置使用${gl_bai}"
    echo -e "${gl_lv}官方下载: https://www.wireguard.com/install/${gl_bai}"
    break_end
}

# ====== 主流程 ======
install_docker
deploy_wireguard
