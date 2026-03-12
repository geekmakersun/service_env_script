#!/bin/bash

# ===========================================
# Nginx 站点管理工具
# 交互式创建站点配置，支持多种应用类型和 SSL
# 支持多版本 PHP 自动检测
# ===========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置路径
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SNIPPETS="/etc/nginx/snippets"
WWW_ROOT="/var/www"
SSL_CERT_DIR="/etc/letsencrypt/live"
LOG_DIR="/var/log/nginx/site"
PHP_FPM_DIR="/run/php-fpm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/ssl-config"

# 应用类型和对应的伪静态规则
declare -A APP_TYPES
declare -A APP_DESCRIPTIONS

APP_TYPES=(
    [1]="纯静态网站"
    [2]="WordPress"
    [3]="ThinkPHP"
    [4]="Laravel"
    [5]="Vue/React SPA"
    [6]="Typecho"
    [7]="Discuz"
    [8]="迅睿CMS"
    [9]="自定义PHP"
)

APP_DESCRIPTIONS=(
    [1]="HTML/CSS/JS 静态页面"
    [2]="WordPress 博客/CMS"
    [3]="ThinkPHP 框架"
    [4]="Laravel 框架"
    [5]="单页应用（前端路由）"
    [6]="Typecho 博客"
    [7]="Discuz 论坛"
    [8]="迅睿CMS系统"
    [9]="通用PHP应用"
)

# 打印带颜色的文本
print_color() {
    echo -e "${1}${2}${NC}"
}

# 打印标题
print_header() {
    echo ""
    print_color "$CYAN" "==========================================="
    print_color "$CYAN" "  $1"
    print_color "$CYAN" "==========================================="
    echo ""
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

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 显示菜单
show_menu() {
    clear
    print_header "Nginx 站点管理工具"
    echo "  1. Git导入站点"
    echo "  2. 创建新站点"
    echo "  3. 删除站点"
    echo "  4. 列出所有站点"
    echo "  5. 查看站点配置"
    echo "  6. 申请 SSL 证书"
    echo "  7. 检测 PHP 版本"
    echo "  8. 查看共用配置"
    echo "  9. 强制 HTTPS 重定向"
    echo " 10. 测试并重载 Nginx"
    echo "  0. 退出"
    echo ""
}

# 获取用户输入（带默认值）
get_input() {
    local prompt="$1"
    local default="$2"
    local input

    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${YELLOW}${prompt} [${default}]: ${NC}")" input
        echo "${input:-$default}"
    else
        read -rp "$(echo -e "${YELLOW}${prompt}: ${NC}")" input
        echo "$input"
    fi
}

# 确认操作
confirm() {
    local message="$1"
    local default="${2:-N}"
    local prompt="[y/N]"
    if [[ "$default" == "Y" ]]; then
        prompt="[Y/n]"
    fi
    local response

    read -rp "$(echo -e "${YELLOW}${message} $prompt: ${NC}")" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

# 验证域名格式
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# 检测所有可用的 PHP 版本
detect_php_versions() {
    local versions=()

    if [[ -d "$PHP_FPM_DIR" ]]; then
        for sock in "$PHP_FPM_DIR"/php*-fpm.sock; do
            if [[ -S "$sock" ]]; then
                local ver=$(basename "$sock" -fpm.sock)
                versions+=("$ver")
            fi
        done
    fi

    # 如果没有找到，尝试其他常见路径
    if [[ ${#versions[@]} -eq 0 ]]; then
        for sock in /var/run/php/php*-fpm.sock; do
            if [[ -S "$sock" ]]; then
                local ver=$(basename "$sock" .sock | sed 's/-fpm//')
                versions+=("$ver")
            fi
        done
    fi

    # 排序（从新到旧）并输出去重
    printf '%s\n' "${versions[@]}" | sort -V -r | uniq
}

# 获取可用的 PHP 版本列表
get_available_php_versions() {
    detect_php_versions
}

# 生成伪静态规则
generate_rewrite_rules() {
    local app_type="$1"
    local rules=""

    case "$app_type" in
        "纯静态网站")
            rules="    location / {
        try_files \$uri \$uri/ =404;
    }"
            ;;
        "WordPress")
            rules="    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # WordPress 安全设置
    include snippets/wordpress-security.conf;"
            ;;
        "ThinkPHP")
            rules="    location / {
        if (!-e \$request_filename) {
            rewrite ^(.*)\$ /index.php?s=\$1 last;
        }
    }"
            ;;
        "Laravel")
            rules="    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }"
            ;;
        "Vue/React SPA")
            rules="    location / {
        try_files \$uri \$uri/ /index.html;
    }"
            ;;
        "Typecho")
            rules="    location / {
        index index.php index.html;
        if (-f \$request_filename/index.html) {
            rewrite ^(.*)\$ \$1/index.html break;
        }
        if (-f \$request_filename/index.php) {
            rewrite ^(.*)\$ \$1/index.php;
        }
        if (!-e \$request_filename) {
            rewrite ^(.*)\$ /index.php\$1 last;
        }
    }"
            ;;
        "Discuz")
            rules="    location / {
        rewrite ^([^\\.]*/forum-\\w+-\\d+\\.html)\$ \$1 last;
        rewrite ^([^\\.]*/thread-\\w+-\\d+-\\d+\\.html)\$ \$1 last;
        rewrite ^([^\\.]*/space-(username|uid)-(.+)\\.html)\$ \$1 last;
        rewrite ^([^\\.]*/archiver/(fid|tid)-([0-9]+)\\.html)\$ \$1 last;
        if (!-e \$request_filename) {
            return 404;
        }
    }";
            ;;
        "迅睿CMS")
            rules="    location / {
        if (!-e \$request_filename) {
            rewrite ^(.*)\$ /index.php?s=\$1 last;
        }
    }";
            ;;
        "自定义PHP")
            rules="    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }";
            ;;
    esac

    echo "$rules"
}

# 生成站点配置
generate_site_config() {
    local domain="$1"
    local app_type="$2"
    local php_version="$3"
    local enable_ssl="$4"
    local force_https="$5"
    local document_root="${WWW_ROOT}/${domain}"
    
    # 迅睿CMS使用public目录作为web根目录
    if [[ "$app_type" == "迅睿CMS" ]]; then
        document_root="${WWW_ROOT}/${domain}/public"
    fi

    # 检查证书目录（支持带序号的情况）
    local cert_dir=""
    if [ -d "${SSL_CERT_DIR}/${domain}" ]; then
        cert_dir="${domain}"
    elif [ -d "${SSL_CERT_DIR}/${domain}-0001" ]; then
        cert_dir="${domain}-0001"
    fi

    local config="server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    root ${document_root};
    index index.php index.html index.htm;

    access_log ${LOG_DIR}/${domain}.access.log main;
    error_log ${LOG_DIR}/${domain}.error.log warn;

    # 错误页面处理
    include snippets/error-pages.conf;
"

    # 强制 HTTPS 重定向
    if [[ "$force_https" == "yes" && -n "$cert_dir" ]]; then
        config+="
    # 强制 HTTPS 重定向
    return 301 https://\$server_name\$request_uri;
}
"
        echo "$config"
        return
    fi

    config+="
    # 伪静态规则
$(generate_rewrite_rules "$app_type")
"

    # 添加 PHP 处理（按需引用 snippets）
    if [[ "$app_type" != "纯静态网站" && "$app_type" != "Vue/React SPA" ]]; then
        config+="
    # PHP 处理（按需调用）
    include snippets/${php_version}.conf;
"
    fi

    # 添加通用安全设置
    config+="
    # 安全设置
    include snippets/security.conf;

    # 静态文件缓存
    include snippets/static-cache.conf;
"

    # 添加 SSL 配置（如果启用）
    if [[ "$enable_ssl" == "yes" ]]; then
        config+="
    # HTTPS 配置
    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate ${SSL_CERT_DIR}/${cert_dir}/fullchain.pem;
    ssl_certificate_key ${SSL_CERT_DIR}/${cert_dir}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
"
    else
        if [ -n "$cert_dir" ]; then
            config+="
    # HTTPS 预留配置（已有证书）
    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate ${SSL_CERT_DIR}/${cert_dir}/fullchain.pem;
    ssl_certificate_key ${SSL_CERT_DIR}/${cert_dir}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
"
        else
            config+="
    # HTTPS 预留配置（取消注释并配置证书后启用）
    # listen 443 ssl;
    # listen [::]:443 ssl;
    # ssl_certificate ${SSL_CERT_DIR}/${domain}/fullchain.pem;
    # ssl_certificate_key ${SSL_CERT_DIR}/${domain}/privkey.pem;
"
        fi
    fi

    config+="}
"

    echo "$config"
}

# 显示 PHP 版本检测信息
show_php_versions() {
    print_header "PHP 版本检测"

    print_info "正在检测可用的 PHP-FPM 版本..."
    echo ""

    local versions=($(get_available_php_versions))

    if [[ ${#versions[@]} -eq 0 ]]; then
        print_warning "未检测到任何 PHP-FPM 版本"
        print_info "请确保 PHP-FPM 已安装并正在运行"
        print_info "检测路径: $PHP_FPM_DIR"
    else
        print_success "检测到 ${#versions[@]} 个 PHP 版本："
        echo ""
        for ver in "${versions[@]}"; do
            local sock_path="${PHP_FPM_DIR}/${ver}-fpm.sock"
            echo "  ✓ $ver"
            echo "    Socket: $sock_path"
        done
    fi
    echo ""
    read -rp "按回车键继续..."
}

# 创建站点
create_site() {
    print_header "创建新站点"

    # 输入域名
    while true; do
        domain=$(get_input "请输入网站域名（如：www.example.com）")
        if [[ -z "$domain" ]]; then
            print_error "域名不能为空"
            continue
        fi
        if ! validate_domain "$domain"; then
            print_error "域名格式不正确"
            continue
        fi
        if [[ -f "${NGINX_SITES_AVAILABLE}/${domain}.conf" ]]; then
            print_error "该域名已存在配置"
            continue
        fi
        break
    done

    # 选择应用类型
    echo ""
    print_color "$CYAN" "请选择网站类型："
    for i in $(seq 1 9); do
        if [[ -n "${APP_TYPES[$i]}" ]]; then
            printf "  %d. %-15s - %s\n" "$i" "${APP_TYPES[$i]}" "${APP_DESCRIPTIONS[$i]}"
        fi
    done
    echo ""

    while true; do
        app_choice=$(get_input "请选择")
        if [[ -n "${APP_TYPES[$app_choice]}" ]]; then
            app_type="${APP_TYPES[$app_choice]}"
            break
        fi
        print_error "无效选择"
    done

    print_success "已选择: $app_type"

    # 选择 PHP 版本（如果需要）
    local php_version=""
    if [[ "$app_type" != "纯静态网站" && "$app_type" != "Vue/React SPA" ]]; then
        echo ""
        local available_php=($(get_available_php_versions))

        if [[ ${#available_php[@]} -eq 0 ]]; then
            print_error "未检测到可用的 PHP-FPM 版本"
            print_info "请先安装 PHP-FPM 或选择纯静态网站类型"
            return 1
        fi

        print_color "$CYAN" "可用的 PHP 版本："
        for i in "${!available_php[@]}"; do
            echo "  $((i+1)). ${available_php[$i]}"
        done
        echo ""

        while true; do
            php_choice=$(get_input "请选择 PHP 版本" "1")
            if [[ -z "$php_choice" ]]; then
                php_choice=1
            fi
            if [[ "$php_choice" =~ ^[0-9]+$ ]] && (( php_choice >= 1 && php_choice <= ${#available_php[@]} )); then
                php_version="${available_php[$((php_choice-1))]}"
                break
            fi
            print_error "无效选择"
        done

        print_success "已选择 PHP: $php_version"
    fi

    # 是否启用 SSL
    echo ""
    enable_ssl="no"
    local validation_choice=""
    if confirm "是否申请并启用 SSL 证书（需要域名已解析到本机）"; then
        enable_ssl="yes"
        
        # 选择验证方式
        print_color "$CYAN" "请选择验证方式："
        echo "  1. 标准 HTTP 验证（需要 80 端口可访问）"
        echo "  2. 阿里云 DNS 验证（推荐，无需开放端口）"
        echo "  3. Cloudflare DNS 验证（推荐，无需开放端口）"
        echo ""
        
        while true; do
            validation_choice=$(get_input "请选择")
            if [[ "$validation_choice" =~ ^[1-3]$ ]]; then
                break
            fi
            print_error "无效选择"
        done
    fi

    # 确认配置
    echo ""
    print_color "$CYAN" "配置摘要："
    echo "  域名: $domain"
    echo "  类型: $app_type"
    [[ -n "$php_version" ]] && echo "  PHP版本: $php_version"
    echo "  SSL: $([[ "$enable_ssl" == "yes" ]] && echo "启用" || echo "不启用")"
    [[ "$enable_ssl" == "yes" ]] && echo "  验证方式: $([[ "$validation_choice" == "1" ]] && echo "HTTP验证" || [[ "$validation_choice" == "2" ]] && echo "阿里云DNS验证" || echo "Cloudflare DNS验证")"
    echo "  网站目录: ${WWW_ROOT}/${domain}"
    echo ""

    if ! confirm "确认创建站点"; then
        print_warning "已取消"
        return
    fi

    # 创建网站目录
    mkdir -p "${WWW_ROOT}/${domain}"
    chown -R www-data:www-data "${WWW_ROOT}/${domain}"
    print_success "创建网站目录: ${WWW_ROOT}/${domain}"

    # 先生成HTTP配置（SSL暂时设为no，后面再更新）
    mkdir -p "${NGINX_SITES_AVAILABLE}" "${NGINX_SITES_ENABLED}"
    local config=$(generate_site_config "$domain" "$app_type" "$php_version" "no")
    echo "$config" > "${NGINX_SITES_AVAILABLE}/${domain}.conf"
    print_success "创建配置文件: ${NGINX_SITES_AVAILABLE}/${domain}.conf"

    # 创建软链接启用站点
    if [ ! -L "${NGINX_SITES_ENABLED}/${domain}.conf" ]; then
        ln -s "${NGINX_SITES_AVAILABLE}/${domain}.conf" "${NGINX_SITES_ENABLED}/"
        print_success "已启用站点: ${NGINX_SITES_ENABLED}/${domain}.conf"
    fi

    # 测试并重载 Nginx（确保HTTP可访问）
    if nginx -t 2>/dev/null; then
        nginx -s reload
        print_success "Nginx 配置测试通过并已重载"
    else
        print_error "Nginx 配置测试失败"
        print_info "请手动检查配置: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
        return 1
    fi

    # 申请 SSL 证书（如果启用）- 此时HTTP已可访问
    if [[ "$enable_ssl" == "yes" ]]; then
        apply_ssl_certificate "$domain" "$validation_choice"
    fi

    echo ""
    print_color "$GREEN" "==========================================="
    print_color "$GREEN" "  站点创建成功！"
    print_color "$GREEN" "==========================================="
    echo ""
    print_info "网站地址: http://$domain"
    [[ "$enable_ssl" == "yes" ]] && print_info "HTTPS地址: https://$domain"
    print_info "网站目录: ${WWW_ROOT}/${domain}"
    print_info "配置文件: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
    echo ""
}

# 申请 SSL 证书
apply_ssl_certificate() {
    local domain="$1"
    local validation_choice="$2"
    local cert_storage="/etc/letsencrypt/live"
    local record_file="$CONFIG_DIR/.申请记录"

    print_header "申请 SSL 证书"
    print_info "正在为 $domain 申请 SSL 证书..."

    # 确保配置目录存在
    [ ! -d "$CONFIG_DIR" ] && { mkdir -p "$CONFIG_DIR"; chmod 700 "$CONFIG_DIR"; }

    # 如果没有提供验证方式，默认使用 HTTP 验证
    if [[ -z "$validation_choice" ]]; then
        validation_choice="1"
    fi

    # 检查 acme.sh 是否安装
    if ! command -v acme.sh &> /dev/null; then
        print_info "acme.sh 未安装，尝试安装..."
        curl https://get.acme.sh | sh -s email="admin@${domain}"
        source ~/.bashrc
        if ! command -v acme.sh &> /dev/null; then
            print_error "acme.sh 安装失败"
            print_info "请手动安装 acme.sh:"
            print_info "  curl https://get.acme.sh | sh"
            return 1
        fi
    fi
    
    # 安装必要的 DNS 验证环境
    print_info "检查并安装必要的 DNS 验证环境..."
    
    if [[ "$validation_choice" == "2" ]]; then
        # 阿里云 DNS 验证准备
        print_info "准备阿里云 DNS 验证环境..."
        print_info "请确保已设置 Ali_Key 和 Ali_Secret 环境变量"
        print_info "或在后续步骤中输入阿里云 AccessKey"
    elif [[ "$validation_choice" == "3" ]]; then
        # Cloudflare DNS 验证准备
        print_info "准备 Cloudflare DNS 验证环境..."
        print_info "请确保已设置 CF_Token 环境变量"
        print_info "或在后续步骤中输入 Cloudflare API Token"
    fi

    # 检查速率限制
    if [ -f "$record_file" ]; then
        local one_week_ago=$(date -d "7 days ago" +%s)
        
        # 检查域名级别的速率限制
        local domain_attempts=$(awk -F'|' -v d="$domain" -v w="$one_week_ago" '$1==d && $3=="success" && $2>=w {c++} END{print c+0}' "$record_file")
        
        # 检查全局速率限制（所有域名）
        local global_attempts=$(awk -F'|' -v w="$one_week_ago" '$3=="success" && $2>=w {c++} END{print c+0}' "$record_file")
        
        print_info "本周申请（当前域名）: $domain_attempts/5 次"
        print_info "本周申请（全局）: $global_attempts/50 次"
        
        # 检查域名级别的限制
        if [ $domain_attempts -ge 5 ]; then
            print_error "该域名已达申请上限（5次/周）"
            return 1
        fi
        
        # 检查全局限制
        if [ $global_attempts -ge 50 ]; then
            print_error "全局申请已达上限（50次/周）"
            return 1
        fi
        
        # 接近域名上限时提示
        if [ $domain_attempts -ge 4 ]; then
            read -p "接近域名上限，继续? [y/N]: " c
            [[ ! "$c" =~ ^[Yy]$ ]] && return 1
        fi
        
        # 接近全局上限时提示
        if [ $global_attempts -ge 45 ]; then
            read -p "接近全局上限，继续? [y/N]: " c
            [[ ! "$c" =~ ^[Yy]$ ]] && return 1
        fi
    fi
    
    # 检查证书是否已存在且未过期
    if [ -d "$cert_storage/$domain" ]; then
        local cert_file="$cert_storage/$domain/fullchain.pem"
        if [ -f "$cert_file" ]; then
            local expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
            local days=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))
            
            if [ $days -gt 30 ]; then
                print_info "证书已存在且有效期还有 $days 天，无需重新申请"
                return 0
            fi
        fi
    fi

    # 正式申请
    print_info "进行正式申请..."
    local prod_cmd="~/.acme.sh/acme.sh --issue -d $domain --email admin@$domain"

    local log_file="~/.acme.sh/acme.sh.log"
    
    case "$validation_choice" in
        "1")
            # 标准 HTTP 验证
            prod_cmd+=" --standalone"
            
            # 暂时停止 Nginx 以释放 80 端口
            print_info "停止 Nginx 以释放 80 端口..."
            
            # 尝试多种方法停止 Nginx
            if command -v systemctl &> /dev/null; then
                systemctl stop nginx 2>/dev/null
            elif command -v service &> /dev/null; then
                service nginx stop 2>/dev/null
            else
                pkill -9 -f nginx 2>/dev/null
            fi
            
            sleep 3
            
            # 确保端口 80 已释放
            local port_attempts=0
            local max_port_attempts=5
            while [ $port_attempts -lt $max_port_attempts ]; do
                if ! lsof -i :80 > /dev/null 2>&1; then
                    print_success "端口 80 已释放"
                    break
                fi
                
                print_warning "端口 80 仍被占用，尝试强制释放..."
                fuser -k 80/tcp 2>/dev/null
                sleep 2
                port_attempts=$((port_attempts+1))
                
                if [ $port_attempts -eq $max_port_attempts ]; then
                    print_error "无法释放端口 80，请手动停止占用该端口的进程"
                    return 1
                fi
            done
            ;;
        "2")
            # 阿里云 DNS 验证
            local aliyun_conf="$CONFIG_DIR/aliyunak.conf"
            if [ ! -f "$aliyun_conf" ]; then
                print_info "阿里云密钥配置文件不存在，开始创建..."
                read -rp "请输入阿里云 AccessKey ID: " access_key_id
                read -rp "请输入阿里云 AccessKey Secret: " access_key_secret
                
                # 导出阿里云密钥环境变量
                export Ali_Key="$access_key_id"
                export Ali_Secret="$access_key_secret"
                
                # 保存到配置文件
                cat > "$aliyun_conf" << EOF
# Aliyun DNS API credentials
Ali_Key = $access_key_id
Ali_Secret = $access_key_secret
EOF
                chmod 600 "$aliyun_conf"
                print_success "阿里云密钥配置文件已创建"
            else
                # 从配置文件加载密钥
                export Ali_Key=$(grep "Ali_Key" "$aliyun_conf" | cut -d'=' -f2 | tr -d ' ')
                export Ali_Secret=$(grep "Ali_Secret" "$aliyun_conf" | cut -d'=' -f2 | tr -d ' ')
            fi
            
            prod_cmd+=" --dns dns_ali"
            ;;
        "3")
            # Cloudflare DNS 验证
            local cloudflare_conf="$CONFIG_DIR/cloudflare.conf"
            if [ ! -f "$cloudflare_conf" ]; then
                print_info "Cloudflare 密钥配置文件不存在，开始创建..."
                read -rp "请输入 Cloudflare API Token: " cloudflare_token
                
                # 导出 Cloudflare 密钥环境变量
                export CF_Token="$cloudflare_token"
                
                # 保存到配置文件
                cat > "$cloudflare_conf" << EOF
# Cloudflare API token
CF_Token = $cloudflare_token
EOF
                chmod 600 "$cloudflare_conf"
                print_success "Cloudflare 密钥配置文件已创建"
            else
                # 从配置文件加载密钥
                export CF_Token=$(grep "CF_Token" "$cloudflare_conf" | cut -d'=' -f2 | tr -d ' ')
            fi
            
            prod_cmd+=" --dns dns_cf"
            ;;
    esac
    
    # 尝试最多3次，每次间隔5秒
    local attempts=0
    local max_attempts=3
    local success=false
    local error_message=""
    
    while [ $attempts -lt $max_attempts ]; do
        print_info "尝试 $((attempts+1))/$max_attempts..."
        if eval $prod_cmd 2>&1 | tee /tmp/acme_output.txt; then
            success=true
            break
        else
            error_message=$(grep -A 5 -B 5 "error" /tmp/acme_output.txt | tail -20)
            attempts=$((attempts+1))
            if [ $attempts -lt $max_attempts ]; then
                print_info "申请失败，5秒后重试..."
                sleep 5
                # 再次确保端口 80 已释放（仅 HTTP 验证需要）
                if [[ "$validation_choice" == "1" ]]; then
                    pkill -f nginx 2>/dev/null; sleep 2
                    fuser -k 80/tcp 2>/dev/null; sleep 1
                fi
            fi
        fi
    done
    
    if [ "$success" = false ]; then
        print_error "SSL 证书申请失败"
        print_info "详细错误信息:"
        echo "$error_message"
        print_info "请确保:"
        if [[ "$validation_choice" == "1" ]]; then
            print_info "  1. 域名已正确解析到本机 IP"
            print_info "  2. 80 端口可以从外网访问"
        else
            print_info "  1. 域名已正确解析到您的账户"
            print_info "  2. API 密钥配置正确且有权限"
        fi
        print_info "  3. 未超过 Let's Encrypt 速率限制"
        print_info "  4. 网络连接正常"
        print_info "更多详细信息请查看日志: $log_file"
        # 重启 Nginx（仅 HTTP 验证需要）
        if [[ "$validation_choice" == "1" ]]; then
            print_info "重启 Nginx..."
            pkill -f nginx 2>/dev/null; sleep 2
            nginx
        fi
        return 1
    fi
    
    # 清理临时文件
    rm -f /tmp/acme_output.txt

    # 安装证书到标准位置
    local cert_dir="$cert_storage/$domain"
    mkdir -p "$cert_dir"
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$cert_dir/privkey.pem" \
        --fullchain-file "$cert_dir/fullchain.pem"
    
    print_success "SSL 证书申请成功"
    print_info "证书已存储: $cert_dir/fullchain.pem"
    print_info "私钥已存储: $cert_dir/privkey.pem"

    # 更新 Nginx 配置
    print_info "更新 Nginx 配置..."
    local config_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [ -f "$config_file" ]; then
        # 启用 SSL 配置
        sed -i 's|# listen 443|listen 443|' "$config_file"
        sed -i "s|# ssl_certificate.*|ssl_certificate $cert_dir/fullchain.pem;|" "$config_file"
        sed -i "s|# ssl_certificate_key.*|ssl_certificate_key $cert_dir/privkey.pem;|" "$config_file"
        print_success "Nginx 配置已更新"
    fi

    # 记录申请结果
    echo "$domain|$(date +%s)|success|$cert_dir/" >> "$record_file"

    # 重启 Nginx（仅 HTTP 验证需要）
    if [[ "$validation_choice" == "1" ]]; then
        print_info "重启 Nginx..."
        pkill -f nginx 2>/dev/null; sleep 2
        nginx
    else
        # 重新加载 Nginx 配置
        print_info "重新加载 Nginx 配置..."
        nginx -t && nginx -s reload
    fi
    
    # 如果是 Gitea 站点，自动更新 Gitea 配置
    if [[ "$domain" == git.* ]]; then
        print_info "更新 Gitea 配置..."
        if [ -f /etc/gitea/app.ini ]; then
            sed -i "s|^ROOT_URL.*|ROOT_URL = https://${domain}/|" /etc/gitea/app.ini
            systemctl restart gitea
            print_success "Gitea 配置已更新并重启"
        fi
    fi
    
    return 0
}

# 删除站点
delete_site() {
    print_header "删除站点"

    # 获取所有站点
    local sites=()
    while IFS= read -r line; do
        sites+=("$line")
    done < <(ls -1 "${NGINX_SITES_AVAILABLE}"/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.conf$//')

    if [[ ${#sites[@]} -eq 0 ]]; then
        print_warning "没有可删除的站点"
        return
    fi

    echo "现有站点："
    for i in "${!sites[@]}"; do
        echo "  $((i+1)). ${sites[$i]}"
    done
    echo ""

    read -rp "$(echo -e "${YELLOW}请选择要删除的站点编号（多个用空格分隔，0取消）: ${NC}")" choices

    if [[ "$choices" == "0" ]]; then
        return
    fi

    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#sites[@]} )); then
            local domain="${sites[$((choice-1))]}"

            echo ""
            print_warning "即将删除站点: $domain"

            if confirm "是否同时删除网站文件（${WWW_ROOT}/${domain}）"; then
                rm -rf "${WWW_ROOT}/${domain}"
                print_success "删除网站文件"
            fi

            if confirm "是否同时删除 SSL 证书"; then
                rm -f "${SSL_CERT_DIR}/${domain}.crt" "${SSL_CERT_DIR}/${domain}.key"
                print_success "删除 SSL 证书"
            fi

            if confirm "是否同时删除日志文件"; then
                rm -f "${LOG_DIR}/${domain}.access.log" "${LOG_DIR}/${domain}.error.log"
                print_success "删除日志文件"
            fi

            # 删除软链接
            rm -f "${NGINX_SITES_ENABLED}/${domain}.conf"
            print_success "删除站点软链接"

            # 删除配置文件
            rm -f "${NGINX_SITES_AVAILABLE}/${domain}.conf"
            print_success "删除配置文件"

            nginx -s reload 2>/dev/null && print_success "重载 Nginx"
        fi
    done
}

# 列出所有站点
list_sites() {
    print_header "站点列表"

    local configs=()
    while IFS= read -r line; do
        configs+=("$line")
    done < <(ls -1 "${NGINX_SITES_AVAILABLE}"/*.conf 2>/dev/null)

    if [[ ${#configs[@]} -eq 0 ]]; then
        print_warning "没有找到站点配置"
        return
    fi

    printf "%-5s %-30s %-15s %-10s %-10s\n" "序号" "域名" "类型" "PHP" "SSL"
    echo "-------------------------------------------------------------------"

    local i=1
    for config in "${configs[@]}"; do
        local domain=$(basename "$config" .conf)
        local has_php="否"
        local php_ver="-"
        local has_ssl="✗"

        if grep -q "php-fpm" "$config" 2>/dev/null; then
            has_php="是"
            php_ver=$(grep -oE 'php[0-9]+-fpm' "$config" 2>/dev/null | head -1 | sed 's/-fpm//')
        fi

        if grep -q "^\s*listen 443" "$config" 2>/dev/null; then
            has_ssl="✓"
        fi

        local app_type="静态"
        if grep -q "wordpress" "$config" 2>/dev/null; then
            app_type="WordPress"
        elif grep -q "Laravel\|laravel" "$config" 2>/dev/null; then
            app_type="Laravel"
        elif grep -q "ThinkPHP\|thinkphp" "$config" 2>/dev/null; then
            app_type="ThinkPHP"
        elif [[ "$has_php" == "是" ]]; then
            app_type="PHP"
        fi

        printf "%-5d %-30s %-15s %-10s %-10s\n" "$i" "$domain" "$app_type" "${php_ver}" "$has_ssl"
        ((i++))
    done
    echo ""
}

# 查看站点配置
view_config() {
    print_header "查看站点配置"

    local sites=()
    while IFS= read -r line; do
        sites+=("$line")
    done < <(ls -1 "${NGINX_SITES_AVAILABLE}"/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.conf$//')

    if [[ ${#sites[@]} -eq 0 ]]; then
        print_warning "没有可查看的站点"
        return
    fi

    echo "现有站点："
    for i in "${!sites[@]}"; do
        echo "  $((i+1)). ${sites[$i]}"
    done
    echo ""

    local choice=$(get_input "请选择要查看的站点编号（0取消）")

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#sites[@]} )); then
        local domain="${sites[$((choice-1))]}"
        echo ""
        print_color "$CYAN" "配置文件: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
        echo "-------------------------------------------------------------------"
        cat "${NGINX_SITES_AVAILABLE}/${domain}.conf"
        echo "-------------------------------------------------------------------"
        echo ""
        read -rp "按回车键继续..."
    fi
}

# SSL 证书管理
manage_ssl() {
    print_header "SSL 证书管理"

    local sites=()
    while IFS= read -r line; do
        sites+=("$line")
    done < <(ls -1 "${NGINX_SITES_AVAILABLE}"/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.conf$//')

    if [[ ${#sites[@]} -eq 0 ]]; then
        print_warning "没有可管理的站点"
        return
    fi

    echo "现有站点："
    for i in "${!sites[@]}"; do
        local has_ssl=""
        if grep -q "^\s*listen 443" "${NGINX_SITES_AVAILABLE}/${sites[$i]}.conf" 2>/dev/null; then
            has_ssl="[已启用SSL]"
        fi
        echo "  $((i+1)). ${sites[$i]} $has_ssl"
    done
    echo ""

    local choice=$(get_input "请选择要申请 SSL 的站点编号（0取消）")

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#sites[@]} )); then
        local domain="${sites[$((choice-1))]}"

        # 选择验证方式
        print_color "$CYAN" "请选择验证方式："
        echo "  1. 标准 HTTP 验证（需要 80 端口可访问）"
        echo "  2. 阿里云 DNS 验证（推荐，无需开放端口）"
        echo "  3. Cloudflare DNS 验证（推荐，无需开放端口）"
        echo ""
        
        local validation_choice
        while true; do
            validation_choice=$(get_input "请选择")
            if [[ "$validation_choice" =~ ^[1-3]$ ]]; then
                break
            fi
            print_error "无效选择"
        done

        if apply_ssl_certificate "$domain" "$validation_choice"; then
            # 更新配置文件启用 SSL
            sed -i 's/# listen 443/listen 443/' "${NGINX_SITES_AVAILABLE}/${domain}.conf"
            sed -i 's/# ssl_certificate/ssl_certificate/' "${NGINX_SITES_AVAILABLE}/${domain}.conf"
            nginx -t && nginx -s reload
            print_success "SSL 已启用并生效"
        fi
    fi
}

# 更新共用配置
update_common_config() {
    print_header "更新 Nginx 共用配置"

    local common_conf="$NGINX_SNIPPETS/common.conf"

    if [ ! -f "$common_conf" ]; then
        print_error "未找到共用配置文件: $common_conf"
        return 1
    fi

    print_info "当前共用配置包含:"
    grep -E "^#.*配置|^location" "$common_conf" | head -20

    echo ""
    print_info "如需修改共用配置，请直接编辑: $common_conf"
}

# 强制 HTTPS 重定向
force_https_redirect() {
    print_header "强制 HTTPS 重定向"

    local sites=()
    while IFS= read -r line; do
        sites+=("$line")
    done < <(ls -1 "${NGINX_SITES_AVAILABLE}"/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.conf$//')

    if [[ ${#sites[@]} -eq 0 ]]; then
        print_warning "没有可管理的站点"
        return
    fi

    echo "现有站点:"
    for i in "${!sites[@]}"; do
        echo "  $((i+1)). ${sites[$i]}"
    done
    echo ""

    local site_choice=$(get_input "选择要强制 HTTPS 的站点编号（0取消）")
    [[ "$site_choice" -eq 0 ]] && return

    if [[ "$site_choice" -lt 1 || "$site_choice" -gt ${#sites[@]} ]]; then
        print_error "无效选择"
        return
    fi

    local domain="${sites[$((site_choice-1))]}"
    local config_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"

    # 检查证书
    local cert_dir=""
    if [ -d "${SSL_CERT_DIR}/${domain}" ]; then
        cert_dir="${domain}"
    elif [ -d "${SSL_CERT_DIR}/${domain}-0001" ]; then
        cert_dir="${domain}-0001"
    fi

    if [ -z "$cert_dir" ]; then
        print_error "该站点没有 SSL 证书，请先申请 SSL 证书"
        return
    fi

    print_info "正在为 $domain 强制 HTTPS 重定向..."

    # 生成强制 HTTPS 配置
    local force_https_config=$(generate_site_config "$domain" "纯静态网站" "php8.4-fpm" "no" "yes")

    # 读取原配置中的 HTTPS 部分
    local https_config=""
    local in_https_block=false
    while IFS= read -r line; do
        if echo "$line" | grep -q "listen 443 ssl"; then
            in_https_block=true
        fi
        if $in_https_block; then
            https_config+="$line"$'\n'
        fi
        if echo "$line" | grep -q "^}$" && $in_https_block; then
            break
        fi
    done < <(grep -A 20 "listen 443 ssl" "$config_file" 2>/dev/null || echo "")

    # 替换配置文件
    {
        echo "$force_https_config"
        echo ""
        echo "$https_config"
    } > "$config_file"

    # 重新加载 Nginx
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        print_success "强制 HTTPS 重定向已启用"
        print_info "HTTP 请求将自动重定向到 HTTPS"
    else
        print_error "Nginx 配置测试失败"
    fi
}

# 测试并重载 Nginx
reload_nginx() {
    print_header "测试并重载 Nginx"

    print_info "测试 Nginx 配置..."
    if nginx -t; then
        print_success "配置测试通过"

        if confirm "是否重载 Nginx?"; then
            systemctl reload nginx
            print_success "Nginx 已重载"
        fi
    else
        print_error "配置测试失败，请检查配置"
        return 1
    fi
}

# 主程序
main() {
    check_root

    # 确保必要目录存在
    mkdir -p "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED" "$WWW_ROOT" "$SSL_CERT_DIR" "$LOG_DIR"

    while true; do
        show_menu
        choice=$(get_input "请输入选项")

        case "$choice" in
            1)
                git_import_site
                echo ""
                read -rp "按回车键继续..."
                ;;
            2)
                create_site
                echo ""
                read -rp "按回车键继续..."
                ;;
            3)
                delete_site
                echo ""
                read -rp "按回车键继续..."
                ;;
            4)
                list_sites
                echo ""
                read -rp "按回车键继续..."
                ;;
            5)
                view_config
                ;;
            6)
                manage_ssl
                echo ""
                read -rp "按回车键继续..."
                ;;
            7)
                show_php_versions
                ;;
            8)
                update_common_config
                echo ""
                read -rp "按回车键继续..."
                ;;
            9)
                force_https_redirect
                echo ""
                read -rp "按回车键继续..."
                ;;
            10)
                reload_nginx
                echo ""
                read -rp "按回车键继续..."
                ;;
            0)
                print_color "$GREEN" "再见！"
                exit 0
                ;;
            *)
                print_error "无效选项"
                sleep 1
                ;;
        esac
    done
}

# Git导入站点
git_import_site() {
    print_header "Git导入站点"

    # 输入Git仓库地址
    git_url=$(get_input "请输入Git仓库地址（如：https://gitlab.com/username/repo.git）")
    if [[ -z "$git_url" ]]; then
        print_error "Git仓库地址不能为空"
        return 1
    fi

    # 输入域名
    while true; do
        domain=$(get_input "请输入网站域名（如：www.example.com）")
        if [[ -z "$domain" ]]; then
            print_error "域名不能为空"
            continue
        fi
        if ! validate_domain "$domain"; then
            print_error "域名格式不正确"
            continue
        fi
        if [[ -f "${NGINX_SITES_AVAILABLE}/${domain}.conf" ]]; then
            print_error "该域名已存在配置"
            continue
        fi
        break
    done

    # 选择应用类型
    echo ""
    print_color "$CYAN" "请选择网站类型："
    for i in $(seq 1 9); do
        if [[ -n "${APP_TYPES[$i]}" ]]; then
            printf "  %d. %-15s - %s\n" "$i" "${APP_TYPES[$i]}" "${APP_DESCRIPTIONS[$i]}"
        fi
    done
    echo ""

    while true; do
        app_choice=$(get_input "请选择")
        if [[ -n "${APP_TYPES[$app_choice]}" ]]; then
            app_type="${APP_TYPES[$app_choice]}"
            break
        fi
        print_error "无效选择"
    done

    print_success "已选择: $app_type"

    # 选择 PHP 版本（如果需要）
    local php_version=""
    if [[ "$app_type" != "纯静态网站" && "$app_type" != "Vue/React SPA" ]]; then
        echo ""
        local available_php=($(get_available_php_versions))

        if [[ ${#available_php[@]} -eq 0 ]]; then
            print_error "未检测到可用的 PHP-FPM 版本"
            print_info "请先安装 PHP-FPM 或选择纯静态网站类型"
            return 1
        fi

        print_color "$CYAN" "可用的 PHP 版本："
        for i in "${!available_php[@]}"; do
            echo "  $((i+1)). ${available_php[$i]}"
        done
        echo ""

        while true; do
            php_choice=$(get_input "请选择 PHP 版本" "1")
            if [[ -z "$php_choice" ]]; then
                php_choice=1
            fi
            if [[ "$php_choice" =~ ^[0-9]+$ ]] && (( php_choice >= 1 && php_choice <= ${#available_php[@]} )); then
                php_version="${available_php[$((php_choice-1))]}"
                break
            fi
            print_error "无效选择"
        done

        print_success "已选择 PHP: $php_version"
    fi

    # 是否启用 SSL
    echo ""
    enable_ssl="no"
    local validation_choice=""
    if confirm "是否申请并启用 SSL 证书（需要域名已解析到本机）"; then
        enable_ssl="yes"
        
        # 选择验证方式
        print_color "$CYAN" "请选择验证方式："
        echo "  1. 标准 HTTP 验证（需要 80 端口可访问）"
        echo "  2. 阿里云 DNS 验证（推荐，无需开放端口）"
        echo "  3. Cloudflare DNS 验证（推荐，无需开放端口）"
        echo ""
        
        while true; do
            validation_choice=$(get_input "请选择")
            if [[ "$validation_choice" =~ ^[1-3]$ ]]; then
                break
            fi
            print_error "无效选择"
        done
    fi

    # 确认配置
    echo ""
    print_color "$CYAN" "配置摘要："
    echo "  Git仓库: $git_url"
    echo "  域名: $domain"
    echo "  类型: $app_type"
    [[ -n "$php_version" ]] && echo "  PHP版本: $php_version"
    echo "  SSL: $([[ "$enable_ssl" == "yes" ]] && echo "启用" || echo "不启用")"
    [[ "$enable_ssl" == "yes" ]] && echo "  验证方式: $([[ "$validation_choice" == "1" ]] && echo "HTTP验证" || [[ "$validation_choice" == "2" ]] && echo "阿里云DNS验证" || echo "Cloudflare DNS验证")"
    echo "  网站目录: ${WWW_ROOT}/${domain}"
    echo ""

    if ! confirm "确认导入站点" "Y"; then
        print_warning "已取消"
        return
    fi

    # 检查Git是否安装
    if ! command -v git &> /dev/null; then
        print_warning "Git 未安装，正在尝试安装..."
        apt update && apt install -y git
        if [[ $? -ne 0 ]]; then
            print_error "Git 安装失败"
            return 1
        fi
    fi

    # 克隆Git仓库
    print_info "正在克隆Git仓库..."
    if git clone "$git_url" "${WWW_ROOT}/${domain}"; then
        print_success "Git仓库克隆成功"
    else
        print_error "Git仓库克隆失败"
        return 1
    fi

    # 设置权限
    chown -R www-data:www-data "${WWW_ROOT}/${domain}"
    print_success "设置网站目录权限"

    # 先生成HTTP配置（SSL暂时设为no，后面再更新）
    local config=$(generate_site_config "$domain" "$app_type" "$php_version" "no")
    echo "$config" > "${NGINX_SITES_AVAILABLE}/${domain}.conf"
    print_success "创建配置文件: ${NGINX_SITES_AVAILABLE}/${domain}.conf"

    # 测试并重载 Nginx（确保HTTP可访问）
    if nginx -t 2>/dev/null; then
        nginx -s reload
        print_success "Nginx 配置测试通过并已重载"
    else
        print_error "Nginx 配置测试失败"
        print_info "请手动检查配置: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
        return 1
    fi

    # 申请 SSL 证书（如果启用）- 此时HTTP已可访问
    if [[ "$enable_ssl" == "yes" ]]; then
        if apply_ssl_certificate "$domain" "$validation_choice"; then
            # 更新配置文件启用 SSL
            local ssl_config=$(generate_site_config "$domain" "$app_type" "$php_version" "yes")
            echo "$ssl_config" > "${NGINX_SITES_AVAILABLE}/${domain}.conf"
            if nginx -t 2>/dev/null; then
                nginx -s reload
                print_success "Nginx SSL 配置已更新并重载"
            else
                print_error "Nginx SSL 配置测试失败"
                print_info "请手动检查配置: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
            fi
        fi
    fi

    echo ""
    print_color "$GREEN" "==========================================="
    print_color "$GREEN" "  站点导入成功！"
    print_color "$GREEN" "==========================================="
    echo ""
    print_info "网站地址: http://$domain"
    [[ "$enable_ssl" == "yes" ]] && print_info "HTTPS地址: https://$domain"
    print_info "网站目录: ${WWW_ROOT}/${domain}"
    print_info "配置文件: ${NGINX_SITES_AVAILABLE}/${domain}.conf"
    print_info "Git仓库: $git_url"
    echo ""
}

# 命令行模式处理
cli_mode() {
    local domain="$1"
    local validation_choice="$2"
    local test_mode=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --aliyun-dns)
                validation_choice="2"
                ;;
            --cloudflare-dns)
                validation_choice="3"
                ;;
            --test)
                test_mode=true
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                ;;
        esac
        shift
    done
    
    if [[ -z "$domain" ]]; then
        print_error "用法: $0 <域名> [--aliyun-dns|--cloudflare-dns] [--test]"
        exit 1
    fi
    
    # 确保配置目录存在
    [ ! -d "$CONFIG_DIR" ] && { mkdir -p "$CONFIG_DIR"; chmod 700 "$CONFIG_DIR"; }
    
    # 检查配置文件是否存在
    local config_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [ ! -f "$config_file" ]; then
        print_error "错误: 配置文件不存在: $config_file"
        print_info "请先创建站点配置或使用交互式模式"
        exit 1
    fi
    
    # 测试模式
    if [ "$test_mode" = true ]; then
        print_header "测试 SSL 证书申请"
        print_info "正在为 $domain 进行测试申请..."
        
        # 检查 certbot 是否安装
        if ! command -v certbot &> /dev/null; then
            print_info "Certbot 未安装，尝试安装..."
            
            if command -v apt-get &>/dev/null; then
                DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y certbot
            elif command -v yum &>/dev/null; then
                yum install -y epel-release && yum install -y certbot -y
            elif command -v dnf &>/dev/null; then
                dnf install -y certbot
            else
                print_error "未找到证书申请工具 (certbot)"
                exit 1
            fi
        fi
        
        # 安装必要的 DNS 验证插件
        print_info "检查并安装必要的 DNS 验证插件..."
        
        if [[ "$validation_choice" == "2" ]]; then
            # 阿里云 DNS 验证插件
            print_info "安装阿里云 DNS 验证插件..."
            if command -v apt-get &>/dev/null; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip && pip3 install certbot-dns-aliyun
            elif command -v yum &>/dev/null; then
                yum install -y python3-pip && pip3 install certbot-dns-aliyun
            elif command -v dnf &>/dev/null; then
                dnf install -y python3-pip && pip3 install certbot-dns-aliyun
            fi
            print_info "阿里云 DNS 验证插件安装完成"
        elif [[ "$validation_choice" == "3" ]]; then
            # Cloudflare DNS 验证插件
            print_info "安装 Cloudflare DNS 验证插件..."
            if command -v apt-get &>/dev/null; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip && pip3 install certbot-dns-cloudflare
            elif command -v yum &>/dev/null; then
                yum install -y python3-pip && pip3 install certbot-dns-cloudflare
            elif command -v dnf &>/dev/null; then
                dnf install -y python3-pip && pip3 install certbot-dns-cloudflare
            fi
            print_info "Cloudflare DNS 验证插件安装完成"
        fi
        
        # 构建测试命令
        local test_cmd="certbot certonly --non-interactive --agree-tos --register-unsafely-without-email -d $domain --test-cert -v"
        
        case "$validation_choice" in
            "2")
                # 阿里云 DNS 验证
                local aliyun_conf="$CONFIG_DIR/aliyunak.conf"
                if [ ! -f "$aliyun_conf" ]; then
                    print_info "阿里云密钥配置文件不存在，开始创建..."
                    read -rp "请输入阿里云 AccessKey ID: " access_key_id
                    read -rp "请输入阿里云 AccessKey Secret: " access_key_secret
                    
                    cat > "$aliyun_conf" << EOF
# Aliyun DNS API credentials
dns_aliyun_access_key = $access_key_id
dns_aliyun_access_key_secret = $access_key_secret
EOF
                    chmod 600 "$aliyun_conf"
                    print_success "阿里云密钥配置文件已创建"
                fi
                
                test_cmd+=" --authenticator dns-aliyun --dns-aliyun-credentials $aliyun_conf --dns-aliyun-propagation-seconds 60"
                ;;
            "3")
                # Cloudflare DNS 验证
                local cloudflare_conf="$CONFIG_DIR/cloudflare.conf"
                if [ ! -f "$cloudflare_conf" ]; then
                    print_info "Cloudflare 密钥配置文件不存在，开始创建..."
                    read -rp "请输入 Cloudflare API Token: " cloudflare_token
                    
                    cat > "$cloudflare_conf" << EOF
# Cloudflare API token
dns_cloudflare_api_token = $cloudflare_token
EOF
                    chmod 600 "$cloudflare_conf"
                    print_success "Cloudflare 密钥配置文件已创建"
                fi
                
                test_cmd+=" --authenticator dns-cloudflare --dns-cloudflare-credentials $cloudflare_conf --dns-cloudflare-propagation-seconds 60"
                ;;
            *)
                # 标准 HTTP 验证
                test_cmd+=" --standalone"
                
                # 暂时停止 Nginx 以释放 80 端口
                print_info "停止 Nginx 以释放 80 端口..."
                if command -v systemctl &> /dev/null; then
                    systemctl stop nginx 2>/dev/null
                elif command -v service &> /dev/null; then
                    service nginx stop 2>/dev/null
                else
                    pkill -9 -f nginx 2>/dev/null
                fi
                sleep 3
                ;;
        esac
        
        # 执行测试申请
        if eval $test_cmd 2>&1 | tee /tmp/certbot_test_output.txt; then
            print_success "测试申请成功"
            print_info "清理测试证书..."
            rm -rf "/etc/letsencrypt/live/$domain" "/etc/letsencrypt/archive/$domain" "/etc/letsencrypt/renewal/$domain.conf"
        else
            print_error "测试申请失败"
            print_info "详细错误信息:"
            grep -A 5 -B 5 "error" /tmp/certbot_test_output.txt | tail -20
        fi
        
        # 重启 Nginx（如果停止了）
        if [[ -z "$validation_choice" || "$validation_choice" == "1" ]]; then
            print_info "重启 Nginx..."
            pkill -f nginx 2>/dev/null; sleep 2
            nginx
        fi
        
        # 清理临时文件
        rm -f /tmp/certbot_test_output.txt
        exit 0
    fi
    
    # 正式申请
    if [[ -z "$validation_choice" ]]; then
        # 默认使用 HTTP 验证
        validation_choice="1"
    fi
    
    if apply_ssl_certificate "$domain" "$validation_choice"; then
        print_success "SSL 证书申请成功"
        exit 0
    else
        print_error "SSL 证书申请失败"
        exit 1
    fi
}

# 运行主程序
if [[ $# -gt 0 ]]; then
    # 命令行模式
    cli_mode "$@"
else
    # 交互式模式
    main "$@"
fi
