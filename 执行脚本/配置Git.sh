#!/bin/bash

# ===========================================
# 配置Git脚本
# 功能：配置Git和升级到最新版本
# 版本：1.5
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
            ;;
        esac
    done
    
    # 升级 Git 到最新版本
    print_info "\n=== 升级 Git ==="
    
    while true; do
        read -p "是否升级 Git 到最新版本? (y/n): " UPGRADE_GIT
        case "$UPGRADE_GIT" in
            [yY])
                print_info "正在添加 Git 官方 PPA..."
                add-apt-repository ppa:git-core/ppa -y
                
                print_info "正在更新软件包列表..."
                apt update -y
                
                print_info "正在升级 Git..."
                apt install -y git
                
                print_success "Git 升级完成"
                print_info "新版本: $(git --version)"
                break
            ;;
            [nN])
                print_info "跳过 Git 升级"
                break
            ;;
            *)
                print_error "无效输入，请输入 y 或 n"
                ;;
        esac
    done
    
    # 生成 SSH 密钥
    print_info "\n=== 生成 SSH 密钥 ==="
    
    while true; do
        read -p "是否生成 SSH 密钥? (y/n): " GENERATE_SSH_KEY
        case "$GENERATE_SSH_KEY" in
            [yY])
                while true; do
                    read -p "请输入 SSH 密钥邮箱: " SSH_KEY_EMAIL
                    if [ -z "$SSH_KEY_EMAIL" ]; then
                        print_error "邮箱不能为空"
                        continue
                    fi
                    if ! [[ "$SSH_KEY_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                        print_error "邮箱格式不正确"
                        continue
                    fi
                    break
                done
                
                SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
                
                if [ -f "$SSH_KEY_PATH" ]; then
                    print_warning "SSH 密钥已存在: $SSH_KEY_PATH"
                    read -p "是否覆盖现有密钥? (y/n): " OVERWRITE_KEY
                    if [[ ! "$OVERWRITE_KEY" =~ ^[yY]$ ]]; then
                        print_info "跳过生成密钥"
                        break
                    fi
                fi
                
                print_info "正在生成 Ed25519 SSH 密钥..."
                ssh-keygen -t ed25519 -C "$SSH_KEY_EMAIL" -f "$SSH_KEY_PATH" -N ""
                
                if [ $? -eq 0 ]; then
                    chmod 600 "$SSH_KEY_PATH"
                    chmod 644 "${SSH_KEY_PATH}.pub"
                    
                    print_success "SSH 密钥生成完成"
                    print_info "私钥路径: $SSH_KEY_PATH"
                    print_info "公钥路径: ${SSH_KEY_PATH}.pub"
                    print_warning "请将以下公钥添加到 Git 服务商 (GitHub/GitLab 等):"
                    echo ""
                    cat "${SSH_KEY_PATH}.pub"
                    echo ""
                else
                    print_error "SSH 密钥生成失败"
                fi
                break
            ;;
            [nN])
                print_info "跳过生成密钥"
                break
            ;;
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
