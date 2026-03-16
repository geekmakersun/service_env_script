#!/bin/bash

# BBR 部署脚本
# 版本：1.0
# 日期：2026-03-16
# 功能：自动检查、部署和启用 BBR 拥塞控制算法

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
echo_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

echo_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
        VER=$(cat /etc/redhat-release | awk '{print $3}' | sed 's/\..*//')
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    echo_info "检测到系统：$OS $VER"
}

# 检查内核版本
check_kernel() {
    KERNEL_VERSION=$(uname -r | awk -F. '{print $1"."$2}')
    echo_info "当前内核版本：$(uname -r)"
    
    if (( $(echo "$KERNEL_VERSION >= 4.9" | bc -l) )); then
        echo_info "内核版本满足 BBR 要求（4.9+）"
        return 0
    else
        echo_warning "内核版本低于 4.9，需要升级内核"
        return 1
    fi
}

# 升级内核（Ubuntu）
upgrade_kernel_ubuntu() {
    echo_info "开始升级 Ubuntu 内核..."
    apt update && apt upgrade -y
    # 根据 Ubuntu 版本选择合适的内核包
    if [[ "$VER" == "20.04" ]]; then
        apt install --install-recommends linux-generic-hwe-20.04 -y
    elif [[ "$VER" == "22.04" ]]; then
        apt install --install-recommends linux-generic-hwe-22.04 -y
    else
        # 对于 24.04 及以上版本，使用默认内核
        apt install --install-recommends linux-generic -y
    fi
    echo_warning "内核升级完成，需要重启系统"
}

# 升级内核（CentOS）
upgrade_kernel_centos() {
    echo_info "开始升级 CentOS 内核..."
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    yum install https://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm -y
    yum --enablerepo=elrepo-kernel install kernel-ml -y
    grub2-set-default 0
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo_warning "内核升级完成，需要重启系统"
}

# 启用 BBR
enable_bbr() {
    echo_info "开始启用 BBR 拥塞控制..."
    
    # 检查配置文件是否已包含 BBR 设置
    if grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
        echo_info "BBR 已在配置文件中设置"
    else
        cat >> /etc/sysctl.conf << EOF
# 启用 BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        echo_info "已添加 BBR 配置到 /etc/sysctl.conf"
    fi
    
    # 应用配置
    sysctl -p
    echo_info "配置已应用"
}

# 验证 BBR
verify_bbr() {
    echo_info "验证 BBR 是否启用..."
    
    # 检查内核版本
    echo_info "内核版本：$(uname -r)"
    
    # 检查 BBR 模块
    if lsmod | grep -q bbr; then
        echo_info "BBR 模块已加载"
    else
        echo_warning "BBR 模块未加载"
    fi
    
    # 检查拥塞控制算法
    CONGESTION_CONTROL=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [ "$CONGESTION_CONTROL" = "bbr" ]; then
        echo_info "当前拥塞控制算法：$CONGESTION_CONTROL"
    else
        echo_error "当前拥塞控制算法：$CONGESTION_CONTROL（不是 BBR）"
    fi
    
    # 检查队列管理算法
    QUEUE_DISC=$(sysctl net.core.default_qdisc | awk '{print $3}')
    if [ "$QUEUE_DISC" = "fq" ]; then
        echo_info "当前队列管理算法：$QUEUE_DISC"
    else
        echo_warning "当前队列管理算法：$QUEUE_DISC（建议使用 fq）"
    fi
}

# 网络参数优化
optimize_network() {
    echo_info "开始优化网络参数..."
    
    # 检查是否已添加优化参数
    if grep -q "# TCP 缓冲区优化" /etc/sysctl.conf; then
        echo_info "网络优化参数已存在"
    else
        cat >> /etc/sysctl.conf << EOF

# TCP 缓冲区优化
net.ipv4.tcp_mem = 786432 1048576 1572864
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304

# 连接超时设置
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200

# 端口范围
net.ipv4.ip_local_port_range = 1024 65535
EOF
        echo_info "已添加网络优化参数"
    fi
    
    # 应用配置
    sysctl -p
    echo_info "网络参数优化完成"
}

# 禁用 BBR
disable_bbr() {
    echo_info "开始禁用 BBR..."
    
    # 注释掉 BBR 配置
    sed -i 's/net.ipv4.tcp_congestion_control = bbr/#net.ipv4.tcp_congestion_control = bbr/' /etc/sysctl.conf
    sed -i 's/net.core.default_qdisc = fq/#net.core.default_qdisc = fq/' /etc/sysctl.conf
    
    # 应用配置
    sysctl -p
    
    # 验证
    CONGESTION_CONTROL=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    echo_info "当前拥塞控制算法：$CONGESTION_CONTROL"
    echo_info "BBR 已禁用"
}

# 主菜单
main_menu() {
    clear
    echo "======================================"
    echo "          BBR 部署脚本"
    echo "======================================"
    echo "1. 检查系统环境"
    echo "2. 升级内核（如需）"
    echo "3. 启用 BBR"
    echo "4. 验证 BBR"
    echo "5. 优化网络参数"
    echo "6. 禁用 BBR"
    echo "7. 退出"
    echo "======================================"
    read -p "请选择操作：" choice
    
    case $choice in
        1)
            detect_os
            check_kernel
            read -p "按回车键返回菜单..."
            main_menu
            ;;
        2)
            detect_os
            if [ "$OS" = "Ubuntu" ]; then
                upgrade_kernel_ubuntu
            elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ]; then
                upgrade_kernel_centos
            else
                echo_error "暂不支持 $OS 系统的内核升级"
            fi
            read -p "按回车键返回菜单..."
            main_menu
            ;;
        3)
            enable_bbr
            read -p "按回车键返回菜单..."
            main_menu
            ;;
        4)
            verify_bbr
            read -p "按回车键返回菜单..."
            main_menu
            ;;
        5)
            optimize_network
            read -p "按回车键返回菜单..."
            main_menu
            ;;
        6)
            disable_bbr
            read -p "按回车键返回菜单..."
            main_menu
            ;;
        7)
            echo_info "脚本退出"
            exit 0
            ;;
        *)
            echo_error "无效选择，请重新输入"
            read -p "按回车键返回菜单..."
            main_menu
            ;;
    esac
}

# 脚本开始
echo "======================================"
echo "          BBR 部署脚本"
echo "======================================"
echo "此脚本用于部署和启用 BBR 拥塞控制算法"
echo "适用于 Linux 内核 4.9+ 系统"
echo "======================================"

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo_error "请以 root 权限运行此脚本"
    exit 1
fi

# 启动主菜单
main_menu