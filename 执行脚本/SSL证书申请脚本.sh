#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 日志函数
log_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查依赖
test_dependencies() {
    log_info "检查依赖..."
    local dependencies=(curl openssl)
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "缺少依赖: $dep"
            exit 1
        fi
    done
    log_info "依赖检查完成"
}

# 检查 Let's Encrypt 速率限制
check_letsencrypt_rate_limit() {
    log_info "检查 Let's Encrypt 速率限制..."
    local test_domain="test-rate-limit.${RANDOM}.com"
    local acme_script="$(command -v acme.sh || echo "")"
    
    if [ -z "$acme_script" ]; then
        log_warn "未找到 acme.sh，将直接使用备用提供商"
        return 1
    fi
    
    # 使用 acme.sh 测试速率限制
    $acme_script --issue --standalone -d "$test_domain" --dry-run 2>&1 | grep -q "rate limit" && return 0 || return 1
}

# 使用指定 CA 申请证书
obtain_cert() {
    local domain="$1"
    local email="$2"
    local webroot="$3"
    local ca="$4"
    local ca_name="$5"
    
    log_info "使用 $ca_name 申请证书..."
    
    # 检查 acme.sh 是否已安装
    if ! command -v acme.sh &> /dev/null; then
        log_info "安装 acme.sh..."
        curl https://get.acme.sh | sh -s email="$email"
        source ~/.bashrc
    fi
    
    # 切换到指定 CA
    ~/.acme.sh/acme.sh --set-default-ca --server "$ca"
    
    # 申请证书
    if [ -n "$webroot" ]; then
        ~/.acme.sh/acme.sh --issue -d "$domain" --webroot "$webroot"
    else
        ~/.acme.sh/acme.sh --issue -d "$domain" --standalone
    fi
    
    if [ $? -eq 0 ]; then
        log_info "$ca_name 证书申请成功"
        return 0
    else
        log_error "$ca_name 证书申请失败"
        return 1
    fi
}

# 检测当前 Nginx 站点配置
detect_nginx_sites() {
    log_info "检测当前 Nginx 站点配置..."
    
    # 检查 Nginx 配置目录
    local nginx_conf_dir="/etc/nginx"
    local sites_available="$nginx_conf_dir/sites-available"
    local sites_enabled="$nginx_conf_dir/sites-enabled"
    
    if [ ! -d "$nginx_conf_dir" ]; then
        log_error "未找到 Nginx 配置目录"
        return 1
    fi
    
    # 收集站点配置
    local sites=()
    
    # 检查 sites-enabled 目录
    if [ -d "$sites_enabled" ]; then
        for site in "$sites_enabled"/*; do
            if [ -f "$site" ]; then
                local site_name=$(basename "$site")
                sites+=($site_name)
            fi
        done
    fi
    
    # 检查 sites-available 目录
    if [ -d "$sites_available" ]; then
        for site in "$sites_available"/*; do
            if [ -f "$site" ]; then
                local site_name=$(basename "$site")
                # 避免重复
                if [[ ! "${sites[*]}" =~ "$site_name" ]]; then
                    sites+=($site_name)
                fi
            fi
        done
    fi
    
    # 检查主配置文件中的 server 块
    if [ -f "$nginx_conf_dir/nginx.conf" ]; then
        if grep -q "server {" "$nginx_conf_dir/nginx.conf"; then
            sites+=('nginx.conf')
        fi
    fi
    
    if [ ${#sites[@]} -eq 0 ]; then
        log_error "未找到 Nginx 站点配置"
        return 1
    fi
    
    log_info "找到以下 Nginx 站点配置:"
    for i in "${!sites[@]}"; do
        log_info "$((i+1)). ${sites[$i]}"
    done
    
    # 让用户选择站点
    read -p "请选择要为哪个站点申请证书 (输入编号): " site_index
    while [[ ! "$site_index" =~ ^[0-9]+$ ]] || [ "$site_index" -lt 1 ] || [ "$site_index" -gt ${#sites[@]} ]; do
        log_error "请输入正确的编号"
        read -p "请选择要为哪个站点申请证书 (输入编号): " site_index
    done
    
    local selected_site=${sites[$((site_index-1))]}
    log_info "已选择站点: $selected_site"
    
    # 提取域名和 webroot
    if [ "$selected_site" == "nginx.conf" ]; then
        local conf_file="$nginx_conf_dir/nginx.conf"
    elif [ -f "$sites_enabled/$selected_site" ]; then
        local conf_file="$sites_enabled/$selected_site"
    else
        local conf_file="$sites_available/$selected_site"
    fi
    
    # 提取域名
    domain=$(grep -E 'server_name' "$conf_file" | head -1 | awk '{print $2}' | sed 's/;//')
    if [ -z "$domain" ]; then
        log_error "未在配置文件中找到 server_name"
        return 1
    fi
    
    # 提取 webroot
    webroot=$(grep -E 'root' "$conf_file" | head -1 | awk '{print $2}' | sed 's/;//')
    if [ -z "$webroot" ]; then
        log_error "未在配置文件中找到 root 路径"
        return 1
    fi
    
    # 验证 webroot 路径
    if [ ! -d "$webroot" ]; then
        log_error "webroot 路径不存在: $webroot"
        return 1
    fi
    
    log_info "从配置中提取的信息:"
    log_info "域名: $domain"
    log_info "webroot 路径: $webroot"
    
    return 0
}

# 交互式获取用户输入
get_user_input() {
    log_info "=== SSL 证书申请工具 ==="
    log_info "此工具使用 acme.sh 自动申请和管理 SSL 证书"
    log_info "支持多种证书提供商和验证方式，适用于不同场景"
    log_info ""
    log_info "支持的证书提供商:"
    log_info "1. Let's Encrypt: 免费、广泛使用的证书提供商"
    log_info "2. ZeroSSL: 备用证书提供商，当 Let's Encrypt 达到速率限制时使用"
    log_info "3. Buypass: 另一个备用证书提供商，提供额外的申请机会"
    log_info ""
    log_info "验证方式:"
    log_info "- webroot: 通过网站根目录验证域名所有权"
    log_info "- standalone: 通过临时服务器验证域名所有权"
    log_info ""
    log_info "使用流程:"
    log_info "1. 选择或输入域名信息"
    log_info "2. 选择验证方式"
    log_info "3. 系统自动申请证书"
    log_info "4. 证书申请成功后可用于配置 HTTPS"
    log_info ""
    
    # 检测 Nginx 站点
    if ! detect_nginx_sites; then
        log_info "手动输入站点信息"
        
        # 获取域名
        read -p "请输入域名: " domain
        while [ -z "$domain" ]; do
            log_error "域名不能为空，请重新输入"
            read -p "请输入域名: " domain
        done
        
        # 获取邮箱
        read -p "请输入邮箱: " email
        while [ -z "$email" ]; do
            log_error "邮箱不能为空，请重新输入"
            read -p "请输入邮箱: " email
        done
        
        # 获取验证方式
        log_info "验证方式说明:"
        log_info "1. webroot: 使用网站根目录进行验证，适合已有网站运行的情况"
        log_info "   - 优点: 不需要停止现有服务，验证过程对用户无感知"
        log_info "   - 适用: 网站正常运行，80端口可访问的场景"
        log_info "2. standalone: 使用临时服务器进行验证，适合无网站运行的情况"
        log_info "   - 优点: 不依赖现有网站配置，适合新服务器"
        log_info "   - 适用: 网站未运行，或80端口空闲的场景"
        read -p "请选择验证方式 (1. webroot 2. standalone): " verify_method
        while [[ "$verify_method" != "1" && "$verify_method" != "2" ]]; do
            log_error "请输入正确的验证方式"
            read -p "请选择验证方式 (1. webroot 2. standalone): " verify_method
        done
        
        # 如果选择 webroot，获取 webroot 路径
        if [ "$verify_method" == "1" ]; then
            read -p "请输入 webroot 路径: " webroot
            while [ -z "$webroot" ] || [ ! -d "$webroot" ]; do
                if [ ! -d "$webroot" ]; then
                    log_error "webroot 路径不存在，请重新输入"
                else
                    log_error "webroot 路径不能为空，请重新输入"
                fi
                read -p "请输入 webroot 路径: " webroot
            done
        else
            webroot=""
        fi
    else
        # 获取邮箱
        read -p "请输入邮箱: " email
        while [ -z "$email" ]; do
            log_error "邮箱不能为空，请重新输入"
            read -p "请输入邮箱: " email
        done
        # 使用 webroot 验证
        verify_method="1"
    fi
    
    # 显示用户输入
    log_info ""
    log_info "=== 申请信息 ==="
    log_info "域名: $domain"
    log_info "邮箱: $email"
    if [ "$verify_method" == "1" ]; then
        log_info "验证方式: webroot"
        log_info "webroot 路径: $webroot"
    else
        log_info "验证方式: standalone"
    fi
    log_info ""
    
    # 确认信息
    read -p "确认申请临时证书吗？(y/n): " confirm
    while [[ "$confirm" != "y" && "$confirm" != "n" ]]; do
        log_error "请输入正确的选项"
        read -p "确认申请临时证书吗？(y/n): " confirm
    done
    
    if [ "$confirm" == "n" ]; then
        log_info "已取消申请"
        exit 0
    fi
    
    log_info ""
    log_info "=== 证书申请说明 ==="
    log_info "1. 系统会先检查 Let's Encrypt 的速率限制情况"
    log_info "2. 如果未达到速率限制，将优先使用 Let's Encrypt 申请证书"
    log_info "3. 如果达到速率限制或申请失败，将自动尝试使用 ZeroSSL 和 Buypass"
    log_info "4. 所有证书均为免费且有效的 SSL 证书，有效期通常为 90 天"
    log_info "5. acme.sh 会自动设置定时任务，在证书到期前进行续期"
    log_info ""
    log_info "=== 注意事项 ==="
    log_info "- 确保域名已正确解析到服务器 IP"
    log_info "- 如果使用 webroot 验证，请确保网站根目录可写"
    log_info "- 如果使用 standalone 验证，请确保 80 端口未被占用"
    log_info "- 每个域名每周最多可申请 5 次证书，请合理使用"
    log_info ""
}

# 主函数
main() {
    # 获取用户输入
    get_user_input
    
    test_dependencies
    
    # 检查 Let's Encrypt 速率限制
    if check_letsencrypt_rate_limit; then
        log_warn "检测到 Let's Encrypt 速率限制"
        
        # 尝试使用 ZeroSSL
        if obtain_cert "$domain" "$email" "$webroot" "zerossl" "ZeroSSL"; then
            log_info "证书申请成功，已使用 ZeroSSL"
            exit 0
        fi
        
        # 尝试使用 Buypass
        if obtain_cert "$domain" "$email" "$webroot" "buypass" "Buypass"; then
            log_info "证书申请成功，已使用 Buypass"
            exit 0
        fi
        
        log_error "所有 SSL 提供商都申请失败"
        exit 1
    else
        log_info "Let's Encrypt 未达到速率限制，使用默认提供商"
        
        # 使用默认提供商（Let's Encrypt）
        if command -v acme.sh &> /dev/null; then
            if [ -n "$webroot" ]; then
                ~/.acme.sh/acme.sh --issue -d "$domain" --webroot "$webroot" --email "$email"
            else
                ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --email "$email"
            fi
        else
            log_error "未找到 acme.sh"
            exit 1
        fi
        
        if [ $? -eq 0 ]; then
            log_info "Let's Encrypt 证书申请成功"
            exit 0
        else
            log_error "Let's Encrypt 证书申请失败，尝试备用提供商"
            
            # 尝试使用 ZeroSSL
            if obtain_cert "$domain" "$email" "$webroot" "zerossl" "ZeroSSL"; then
                log_info "证书申请成功，已使用 ZeroSSL"
                exit 0
            fi
            
            # 尝试使用 Buypass
            if obtain_cert "$domain" "$email" "$webroot" "buypass" "Buypass"; then
                log_info "证书申请成功，已使用 Buypass"
                exit 0
            fi
            
            log_error "所有 SSL 提供商都申请失败"
            exit 1
        fi
    fi
}

# 执行主函数
main