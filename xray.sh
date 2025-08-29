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
