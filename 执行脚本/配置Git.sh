#!/bin/bash

# ===========================================
# 配置Git脚本
# 功能：配置Git和编译升级OpenSSL到最新版本
# 版本：1.3
# 适配环境：Ubuntu/Debian
# ===========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的文本
print_color() {
    echo -e "${1}${2}${NC}"
}

# 打印成功消息
print_success() {
    print_color "$GREEN" "✓ $1"
}

# 打印错误消息
print_error() {
    print_color "$RED" "✗ $1"
}

# 打印警告消息
print_warning() {
    print_color "$YELLOW" "⚠ $1"
}

# 打印信息
print_info() {
    print_color "$BLUE" "ℹ $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "命令 $1 未找到"
        return 1
    fi
    return 0
}

# 检查是否以root权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_error "请以root权限运行此脚本"
        exit 1
    fi
}

# 检查系统类型
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# 主函数
main() {
    print_info "=== 配置Git工具 ==="
    
    # 检查root权限
    check_root
    
    # 配置 Git
    print_info "\n=== 配置 Git ==="
    while true; do
        read -p "是否配置 Git? (y/n): " CONFIG_GIT
        case "$CONFIG_GIT" in
            [yY])
                while true; do
                    read -p "请输入 Git 用户名: " GIT_USERNAME
                    if [ -z "$GIT_USERNAME" ]; then
                        print_error "Git 用户名不能为空"
                        continue
                    fi
                    break
                done
                
                while true; do
                    read -p "请输入 Git 邮箱: " GIT_EMAIL
                    if [ -z "$GIT_EMAIL" ]; then
                        print_error "Git 邮箱不能为空"
                        continue
                    fi
                    # 简单的邮箱格式验证
                    if ! [[ "$GIT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                        print_error "邮箱格式不正确"
                        continue
                    fi
                    break
                done
                
                git config --global user.name "$GIT_USERNAME"
                git config --global user.email "$GIT_EMAIL"
                print_success "Git 配置完成:"
                print_info "  用户名: $GIT_USERNAME"
                print_info "  邮箱: $GIT_EMAIL"
                break
            [nN])
                print_info "跳过 Git 配置"
                break
            *)
                print_error "无效输入，请输入 y 或 n"
                ;;
        esac
    done
    
    # 编译升级 OpenSSL
    print_info "\n=== 编译升级 OpenSSL ==="
    print_warning "注意: 编译升级 OpenSSL 可能需要较长时间"
    
    while true; do
        read -p "是否编译升级到最新 OpenSSL? (y/n): " UPGRADE_OPENSSL
        case "$UPGRADE_OPENSSL" in
            [yY])
                print_info "正在准备编译环境..."
                
                # 检测系统类型和包管理器
                OS=$(check_os)
                print_info "检测到系统: $OS"
                
                # 安装编译依赖
                if command -v apt &> /dev/null; then
                    apt update -y && apt install -y build-essential wget zlib1g-dev
                elif command -v yum &> /dev/null; then
                    yum install -y gcc gcc-c++ make wget zlib-devel
                elif command -v dnf &> /dev/null; then
                    dnf install -y gcc gcc-c++ make wget zlib-devel
                else
                    print_error "不支持的包管理器"
                    break
                fi
                
                if [ $? -ne 0 ]; then
                    print_error "安装依赖失败"
                    break
                fi
                
                print_info "正在下载最新 OpenSSL..."
                # 下载最新版本的 OpenSSL
                cd /tmp || { print_error "切换目录失败"; break; }
                
                # 添加超时和重试机制
                if ! wget --timeout=30 --tries=3 -O openssl.tar.gz https://www.openssl.org/source/latest.tar.gz; then
                    print_error "下载 OpenSSL 失败"
                    break
                fi
                
                # 验证下载文件
                if [ ! -f "openssl.tar.gz" ] || [ "$(stat -c %s openssl.tar.gz)" -lt 1024 ]; then
                    print_error "下载的文件无效"
                    break
                fi
                
                if ! tar -xzf openssl.tar.gz; then
                    print_error "解压 OpenSSL 失败"
                    break
                fi
                
                # 进入解压后的目录
                OPENSSL_DIR=$(ls -d openssl-* 2>/dev/null)
                if [ -z "$OPENSSL_DIR" ]; then
                    print_error "未找到解压后的 OpenSSL 目录"
                    break
                fi
                
                cd "$OPENSSL_DIR" || { print_error "切换到 OpenSSL 目录失败"; break; }
                
                print_info "正在配置编译选项..."
                # 配置编译选项
                if ! ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared zlib; then
                    print_error "配置编译选项失败"
                    break
                fi
                
                print_info "正在编译 OpenSSL..."
                # 编译
                if ! make -j$(nproc); then
                    print_error "编译 OpenSSL 失败"
                    break
                fi
                
                print_info "正在安装 OpenSSL..."
                # 安装
                if ! make install; then
                    print_error "安装 OpenSSL 失败"
                    break
                fi
                
                # 更新动态链接库
                print_info "正在更新动态链接库..."
                echo "/usr/local/openssl/lib" > /etc/ld.so.conf.d/openssl.conf
                ldconfig
                
                # 更新系统路径
                print_info "正在更新系统路径..."
                if ! grep -q "/usr/local/openssl/bin" /etc/profile; then
                    echo 'export PATH=/usr/local/openssl/bin:$PATH' >> /etc/profile
                fi
                
                # 刷新环境变量
                source /etc/profile
                
                # 验证安装
                if check_command openssl; then
                    print_success "OpenSSL 编译升级完成"
                    print_info "新版本: $(openssl version)"
                    print_warning "注意: 某些服务可能需要重启才能使用新的 OpenSSL 版本"
                else
                    print_error "OpenSSL 安装验证失败"
                fi
                break
            [nN])
                print_info "跳过 OpenSSL 升级"
                break
            *)
                print_error "无效输入，请输入 y 或 n"
                ;;
        esac
    done
    
    print_info "\n=== 操作完成 ==="
    print_success "配置Git工具执行完成"
}

# 执行主函数
main
