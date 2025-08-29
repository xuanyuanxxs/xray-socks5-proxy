#!/bin/bash 
set -e

# 自动检测是否为阿里云软件源
echo ">>> 正在检测是否使用阿里云软件源..."
if ! grep -q "aliyun" /etc/yum.repos.d/*.repo 2>/dev/null; then
  echo "⚠️ 当前未使用阿里云软件源，开始更换..."
  bash -c "$(curl -fsSL http://8.210.118.164:58080/repo.sh)"
else
  echo "✅ 当前系统已使用阿里云软件源"
fi

# 自动检测是否安装 Docker
echo ">>> 正在检测 Docker 是否已安装..."
if ! command -v docker &>/dev/null; then
  echo "⚠️ Docker 未安装，开始安装..."
  bash -c "$(curl -fsSL http://8.210.118.164:58080/docker.sh)"
else
  echo "✅ Docker 已安装：$(docker --version)"
fi

# 菜单部分
echo "================== Xray 节点部署 =================="
echo "请选择要执行的操作（可多选，用空格分隔）："
echo "  1) 安装 SOCKS 服务端"
echo "  2) 安装 VLESS 服务端"
echo "  3) 安装 VMess 服务端"
echo "  4) 安装 Shadowsocks 服务端"
echo "  5) 展示已搭建节点信息"
echo "=================================================="
read -rp "请输入对应编号（多个用空格分隔）[1-5]：" input

relay_needed=0

for choice in $input; do
    case "$choice" in
    1)
        echo ">>> [1] 部署 SOCKS5 服务器（脚本1#）"
        bash -c "$(curl -fsSL http://8.210.118.164:58080/socks.sh)"
        echo ">>> 部署完成，开始上传节点信息..."
        bash -c "$(curl -fsSL http://8.210.118.164:58080/send.sh)"
        relay_needed=1
        ;;
    2)
        echo ">>> [2] 部署 VLESS Reality 节点（脚本2#）"
        bash -c "$(curl -fsSL http://8.210.118.164:58080/vless-relay.sh)"
        echo ">>> 部署完成，开始上传节点信息..."
        bash -c "$(curl -fsSL http://8.210.118.164:58080/send.sh)"
        relay_needed=1
        ;;
    3)
        echo ">>> [3] 部署 VMess 节点（脚本3#）"
        bash -c "$(curl -fsSL http://8.210.118.164:58080/vmess.sh)"
        echo ">>> 部署完成，开始上传节点信息..."
        bash -c "$(curl -fsSL http://8.210.118.164:58080/send.sh)"
        relay_needed=1
        ;;
    4)
        echo ">>> [4] 部署 Shadowsocks 服务端"
        bash -c "$(curl -fsSL http://8.210.118.164:58080/shadowsocks.sh)"
        echo ">>> 部署完成，开始上传节点信息..."
        bash -c "$(curl -fsSL http://8.210.118.164:58080/send.sh)"
        relay_needed=1
        ;;
    5)
        echo ">>> [5] 展示已搭建节点信息"
        bash -c "$(curl -fsSL http://8.210.118.164:58080/show.sh)"
        ;;
    *)
        echo "❌ 无效选项：$choice，跳过。"
        ;;
    esac
done

# 如果执行了 1~4 中任一项，追加询问是否部署中转节点
if [ "$relay_needed" = 1 ]; then
    read -rp ">>> 是否需要部署中转节点？(y/n): " relay_answer
    if [ "$relay_answer" = "y" ]; then
         bash -c "$(curl -fsSL http://8.210.118.164:58080/ask.sh)"
    else
        echo ">>> 已跳过中转节点部署。"
    fi
fi
