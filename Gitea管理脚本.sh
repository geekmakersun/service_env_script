#!/bin/bash

# ===========================================
# Gitea Git 服务部署脚本
# 交互式部署，支持分步骤执行
# 版本: 2.4
# 适配环境: Ubuntu 22.04.5 LTS
# ===========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置变量
GITEA_VERSION="1.25.4"
GITEA_DOMAIN=""
GITEA_SSH_PORT="2222"
GITEA_HTTP_PORT="3000"
GITEA_INSTALL_DIR="/service/gitea"
GITEA_WORK_DIR="/var/lib/gitea"
NGINX_SITE_DIR="/etc/nginx/sites-available"
NGINX_LOG_DIR="/var/log/nginx/site"
CONFIG_DIR="/etc/ssl-config"
ACT_RUNNER_VERSION="0.2.6"
ACT_RUNNER_INSTALL_DIR="/service/act-runner"
ACT_RUNNER_DATA_DIR="/var/lib/act-runner"

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

# 日志函数（兼容旧代码）
log_info() {
    print_info "$1"
}

log_warn() {
    print_warning "$1"
}

log_error() {
    print_error "$1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
}

# 显示主菜单
show_menu() {
    clear
    print_header "Gitea Git 服务部署脚本 v${GITEA_VERSION}"
    echo "  1. 完整部署（一键安装，含HTTPS）"
    echo "  2. 环境检查"
    echo "  3. 创建 Git 用户"
    echo "  4. 安装 Gitea"
    echo "  5. 配置 Systemd 服务"
    echo "  6. 配置 Nginx 反向代理"
    echo "  7. 修复权限问题"
    echo "  8. 查看部署信息"
    echo "  9. 申请并部署 SSL 证书"
    echo "  10. 重启 Gitea 服务"
        echo "  11. 查看 Gitea 日志"
        echo "  12. 安装 Act Runner (工作流)"
        echo "  13. 删除 Act Runner (工作流)"
        echo "  14. 修改端口号配置"
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

# 交互式配置
configure_interactive() {
    echo ""
    print_header "配置项设置"

    # 域名配置
    while true; do
        GITEA_DOMAIN=$(get_input "请输入 Gitea 服务域名" "${GITEA_DOMAIN}")
        if [[ -z "$GITEA_DOMAIN" ]]; then
            print_error "域名不能为空"
            continue
        fi
        break
    done

    # SSH 端口配置
    local input_ssh_port
    input_ssh_port=$(get_input "请输入 SSH 端口" "$GITEA_SSH_PORT")
    if [[ -n "$input_ssh_port" ]]; then
        GITEA_SSH_PORT="$input_ssh_port"
    fi

    # HTTP 端口配置
    local input_http_port
    input_http_port=$(get_input "请输入 HTTP 端口" "$GITEA_HTTP_PORT")
    if [[ -n "$input_http_port" ]]; then
        GITEA_HTTP_PORT="$input_http_port"
    fi

    echo
    print_info "配置摘要:"
    echo "  - 域名: ${GITEA_DOMAIN}"
    echo "  - SSH 端口: ${GITEA_SSH_PORT}"
    echo "  - HTTP 端口: ${GITEA_HTTP_PORT}"
    echo

    if ! confirm "确认以上配置" "Y"; then
        print_info "配置已取消"
        return 1
    fi
    echo
    return 0
}

# 系统环境检查
check_environment() {
    print_header "系统环境检查"

    # 检查并安装依赖
    if ! command -v nginx &> /dev/null; then
        print_warning "Nginx 未安装，正在安装..."
        apt update && apt install -y nginx
    fi

    if systemctl is-active --quiet nginx; then
        print_success "Nginx 服务运行正常"
    else
        print_warning "Nginx 服务未运行，正在启动..."
        systemctl start nginx
        systemctl enable nginx
    fi

    if ! command -v git &> /dev/null; then
        print_warning "Git 未安装，正在安装..."
        apt update && apt install -y git
    fi

    print_success "Git 版本: $(git --version)"

    # 检查并安装 idn 工具（用于处理国际化域名 IDN）
    if ! command -v idn &> /dev/null; then
        print_warning "idn 工具未安装，正在安装..."
        apt update && apt install -y idn
    fi

    # 检查内存
    local MEM_TOTAL
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    if [[ -n "$MEM_TOTAL" ]]; then
        print_info "系统总内存: ${MEM_TOTAL}MB"
    else
        print_warning "无法获取系统内存信息"
    fi

    # 检查端口占用
    print_info "检查端口占用情况..."
    if ss -tlnp | grep -q ":${GITEA_HTTP_PORT} "; then
        print_warning "端口 ${GITEA_HTTP_PORT} 已被占用"
    else
        print_success "端口 ${GITEA_HTTP_PORT} 可用"
    fi

    if ss -tlnp | grep -q ":${GITEA_SSH_PORT} "; then
        print_warning "端口 ${GITEA_SSH_PORT} 已被占用"
    else
        print_success "端口 ${GITEA_SSH_PORT} 可用"
    fi

    echo
    read -p "按回车键继续..."
}

# 创建 Git 用户
create_git_user() {
    print_header "创建 Git 用户"

    if id "git" &>/dev/null; then
        print_info "Git 用户已存在"
    else
        adduser --system --shell /bin/bash --gecos 'Git Version Control' \
            --group --disabled-password --home /home/git git
        print_success "Git 用户创建成功"
    fi

    # 创建必要的目录结构
    print_info "创建必要的目录结构..."
    
    # 用户主目录
    mkdir -p /home/git/{data,custom/conf,log}
    
    # Gitea工作目录
    mkdir -p "${GITEA_WORK_DIR}"/custom/conf
    mkdir -p "${GITEA_WORK_DIR}"/data
    mkdir -p "${GITEA_WORK_DIR}"/log
    mkdir -p "${GITEA_WORK_DIR}"/cache
    mkdir -p "${GITEA_WORK_DIR}"/sessions
    mkdir -p "${GITEA_WORK_DIR}"/queue
    mkdir -p "${GITEA_WORK_DIR}"/indexers
    mkdir -p "${GITEA_WORK_DIR}"/data/repositories
    mkdir -p "${GITEA_WORK_DIR}"/data/lfs
    mkdir -p "${GITEA_WORK_DIR}"/data/attachments
    mkdir -p "${GITEA_WORK_DIR}"/data/avatars
    mkdir -p "${GITEA_WORK_DIR}"/custom/public
    mkdir -p "${GITEA_WORK_DIR}"/custom/templates
    
    # 配置目录
    mkdir -p /etc/gitea

    # 设置正确的权限
    print_info "设置目录权限..."
    
    # /home/git 目录
    chown -R git:git /home/git
    chmod -R 755 /home/git
    
    # /var/lib/gitea 目录
    chown -R git:git "${GITEA_WORK_DIR}"
    chmod -R 750 "${GITEA_WORK_DIR}"
    
    # 特殊权限设置
    chmod 755 "${GITEA_WORK_DIR}"/custom
    chmod 755 "${GITEA_WORK_DIR}"/custom/conf
    chmod 755 "${GITEA_WORK_DIR}"/custom/public
    chmod 755 "${GITEA_WORK_DIR}"/custom/templates
    
    # /etc/gitea 目录
    chown root:git /etc/gitea
    chmod 770 /etc/gitea

    print_success "Git 用户目录创建完成"
    echo
    read -p "按回车键继续..."
}

# 安装 Gitea
install_gitea() {
    print_header "安装 Gitea ${GITEA_VERSION}"

    # 创建安装目录
    mkdir -p "${GITEA_INSTALL_DIR}"
    cd "${GITEA_INSTALL_DIR}"

    # 检测系统架构
    local ARCH
    ARCH=$(uname -m)
    local GITEA_ARCH
    if [[ "$ARCH" == "x86_64" ]]; then
        GITEA_ARCH="linux-amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        GITEA_ARCH="linux-arm64"
    else
        print_error "不支持的系统架构: $ARCH"
        return 1
    fi

    # 检查是否已存在
    if [[ -f "${GITEA_INSTALL_DIR}/gitea" ]]; then
        print_info "Gitea 已存在"
        if confirm "是否重新下载" "N"; then
            print_info "正在下载 Gitea ${GITEA_VERSION} (${GITEA_ARCH})..."
            wget -O gitea "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-${GITEA_ARCH}"
        fi
    else
        print_info "正在下载 Gitea ${GITEA_VERSION} (${GITEA_ARCH})..."
        wget -O gitea "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-${GITEA_ARCH}"
    fi

    # 设置权限
    chmod +x gitea
    chown git:git gitea

    # 验证安装
    if ./gitea --version &> /dev/null; then
        print_success "Gitea 安装成功: $(./gitea --version)"
    else
        print_error "Gitea 安装失败"
        return 1
    fi

    print_success "Gitea 安装完成"
    echo
    read -p "按回车键继续..."
}

# 配置 Systemd 服务
configure_systemd() {
    print_header "配置 Systemd 服务"

    # 检查 SSL 证书
    local ssl_enabled="no"
    local cert_dir=""
    if [[ -d "/etc/letsencrypt/live/${GITEA_DOMAIN}" ]]; then
        cert_dir="${GITEA_DOMAIN}"
        ssl_enabled="yes"
    elif [[ -d "/etc/letsencrypt/live/${GITEA_DOMAIN}-0001" ]]; then
        cert_dir="${GITEA_DOMAIN}-0001"
        ssl_enabled="yes"
    fi

    # 创建配置文件
    if [[ ! -f /etc/gitea/app.ini ]]; then
        # 生成随机密钥
        local secret_key
        secret_key=$(openssl rand -base64 32)
        local internal_token
        internal_token=$(openssl rand -base64 32)
        local jwt_secret
        jwt_secret=$(openssl rand -base64 32)
        
        cat > /etc/gitea/app.ini << EOF
APP_NAME = Gitea: Git with a cup of tea
RUN_MODE = prod
WORK_PATH = ${GITEA_WORK_DIR}

[server]
PROTOCOL         = http
DOMAIN           = ${GITEA_DOMAIN}
HTTP_ADDR        = 127.0.0.1
HTTP_PORT        = ${GITEA_HTTP_PORT}
ROOT_URL         = https://${GITEA_DOMAIN}/
DISABLE_SSH      = false
SSH_PORT         = ${GITEA_SSH_PORT}
START_SSH_SERVER = true
LFS_START_SERVER = true
OFFLINE_MODE     = false
APP_DATA_PATH    = ${GITEA_WORK_DIR}/data

[database]
DB_TYPE  = sqlite3
PATH     = ${GITEA_WORK_DIR}/gitea.db

[repository]
ROOT = ${GITEA_WORK_DIR}/data/repositories

[session]
PROVIDER        = file
PROVIDER_CONFIG = ${GITEA_WORK_DIR}/sessions

[cache]
ADAPTER = file
PATH    = ${GITEA_WORK_DIR}/cache

[queue]
TYPE = file
PATH = ${GITEA_WORK_DIR}/queue

[indexer]
ISSUE_INDEXER_PATH   = ${GITEA_WORK_DIR}/indexers/issues.bleve
REPO_INDEXER_ENABLED = false

[log]
MODE      = console, file
LEVEL     = info
ROOT_PATH = ${GITEA_WORK_DIR}/log

[security]
INSTALL_LOCK = true
SECRET_KEY   = ${secret_key}
INTERNAL_TOKEN = ${internal_token}
PASSWORD_HASH_ALGO = pbkdf2
MIN_PASSWORD_LENGTH = 8
PASSWORD_COMPLEXITY = off
SUCCESSFUL_TOKENS_CACHE_SIZE = 20

[service]
REGISTER_EMAIL_CONFIRM   = false
ENABLE_NOTIFY_MAIL       = false
DISABLE_REGISTRATION     = false
ALLOW_EXTERNAL_REGISTRATION = false
ENABLE_CAPTCHA           = false
REQUIRE_SIGNIN_VIEW      = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = true
NO_REPLY_ADDRESS = noreply.local

[mailer]
ENABLED = false

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[oauth2]
JWT_SECRET = ${jwt_secret}

[picture]
DISABLE_GRAVATAR = false
ENABLE_FEDERATED_AVATAR = false

[attachment]
ENABLED = true
PATH = ${GITEA_WORK_DIR}/data/attachments
ALLOWED_TYPES = image/jpeg|image/png|application/zip|application/gzip
MAX_SIZE = 4
MAX_FILES = 5
EOF
        chown git:git /etc/gitea/app.ini
        chmod 640 /etc/gitea/app.ini
        print_success "配置文件已创建"
    else
        print_info "配置文件已存在"
        if confirm "是否重新生成配置文件" "N"; then
            mv /etc/gitea/app.ini /etc/gitea/app.ini.bak.$(date +%Y%m%d_%H%M%S)
            print_info "原配置文件已备份"
            # 重新生成配置（简化版，实际应调用完整配置生成）
            touch /etc/gitea/app.ini
            chown git:git /etc/gitea/app.ini
            chmod 640 /etc/gitea/app.ini
        fi
    fi

    # 检查服务文件是否存在
    if [[ -f /etc/systemd/system/gitea.service ]]; then
        print_info "Gitea 服务文件已存在"
        if confirm "是否重新生成服务文件" "N"; then
            mv /etc/systemd/system/gitea.service /etc/systemd/system/gitea.service.bak.$(date +%Y%m%d_%H%M%S)
        else
            systemctl daemon-reload
            systemctl enable gitea
            print_success "Systemd 服务已配置"
            echo
            read -p "按回车键继续..."
            return 0
        fi
    fi

    cat > /etc/systemd/system/gitea.service << EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
User=git
Group=git
WorkingDirectory=${GITEA_WORK_DIR}/
ExecStart=${GITEA_INSTALL_DIR}/gitea web -c /etc/gitea/app.ini
Restart=always
RestartSec=3

CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

LimitNOFILE=524288:524288
LimitNPROC=512:512

Environment=GITEA_WORK_DIR=${GITEA_WORK_DIR}
Environment=GITEA_CUSTOM=${GITEA_WORK_DIR}/custom
Environment=HOME=/home/git
Environment=USER=git

[Install]
WantedBy=multi-user.target
EOF
    print_success "Gitea 服务文件创建成功"

    # 重载 systemd
    systemctl daemon-reload

    # 启用开机自启
    systemctl enable gitea

    # 启动服务
    if confirm "是否立即启动 Gitea 服务" "Y"; then
        systemctl start gitea
        sleep 3

        if systemctl is-active --quiet gitea; then
            print_success "Gitea 服务启动成功"
        else
            print_warning "Gitea 服务启动失败，请检查配置"
            print_info "查看日志: journalctl -u gitea -f"
        fi
    fi

    echo
    read -p "按回车键继续..."
}

# 配置 Nginx 反向代理
configure_nginx() {
    print_header "配置 Nginx 反向代理"

    # 创建站点配置目录
    mkdir -p "${NGINX_SITE_DIR}"

    # 检查是否已存在配置
    if [[ -f "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" ]]; then
        print_info "Nginx 配置已存在"
        if ! confirm "是否重新生成配置" "N"; then
            echo
            read -p "按回车键继续..."
            return 0
        fi
        # 备份原配置
        mv "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    # 创建 Nginx 配置文件
    cat > "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" << EOF
# Gitea Git 服务反向代理配置
# 域名: ${GITEA_DOMAIN}

upstream gitea_backend {
    server 127.0.0.1:${GITEA_HTTP_PORT};
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${GITEA_DOMAIN};

    access_log ${NGINX_LOG_DIR}/${GITEA_DOMAIN}.access.log;
    error_log ${NGINX_LOG_DIR}/${GITEA_DOMAIN}.error.log;

    client_max_body_size 100M;

    location / {
        proxy_pass http://gitea_backend;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF
    print_success "Nginx 配置文件已创建"

    # 创建日志目录
    mkdir -p "${NGINX_LOG_DIR}"
    touch "${NGINX_LOG_DIR}/${GITEA_DOMAIN}.access.log"
    touch "${NGINX_LOG_DIR}/${GITEA_DOMAIN}.error.log"
    chown -R www-data:www-data "${NGINX_LOG_DIR}"

    # 创建软链接启用站点
    mkdir -p /etc/nginx/sites-enabled
    if [[ -L /etc/nginx/sites-enabled/${GITEA_DOMAIN}.conf ]]; then
        rm -f /etc/nginx/sites-enabled/${GITEA_DOMAIN}.conf
    fi
    ln -s "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" /etc/nginx/sites-enabled/
    print_success "Nginx 站点已启用"

    # 测试 Nginx 配置
    if nginx -t &> /dev/null; then
        print_success "Nginx 配置测试通过"
        systemctl reload nginx
        print_success "Nginx 配置已重载"
    else
        print_error "Nginx 配置测试失败"
        nginx -t
        return 1
    fi

    echo
    read -p "按回车键继续..."
}

# 修复权限问题
fix_permissions() {
    print_header "修复权限问题"

    print_info "正在修复目录权限..."
    
    # /home/git 目录
    if [[ -d /home/git ]]; then
        chown -R git:git /home/git
        chmod -R 755 /home/git
        print_success "/home/git 权限已修复"
    fi
    
    # /var/lib/gitea 目录
    if [[ -d "${GITEA_WORK_DIR}" ]]; then
        chown -R git:git "${GITEA_WORK_DIR}"
        chmod -R 750 "${GITEA_WORK_DIR}"
        
        # 特殊权限设置
        if [[ -d "${GITEA_WORK_DIR}/custom" ]]; then
            chmod 755 "${GITEA_WORK_DIR}/custom"
        fi
        if [[ -d "${GITEA_WORK_DIR}/custom/conf" ]]; then
            chmod 755 "${GITEA_WORK_DIR}/custom/conf"
        fi
        if [[ -d "${GITEA_WORK_DIR}/custom/public" ]]; then
            chmod 755 "${GITEA_WORK_DIR}/custom/public"
        fi
        if [[ -d "${GITEA_WORK_DIR}/custom/templates" ]]; then
            chmod 755 "${GITEA_WORK_DIR}/custom/templates"
        fi
        print_success "${GITEA_WORK_DIR} 权限已修复"
    fi
    
    # /etc/gitea 目录
    if [[ -d /etc/gitea ]]; then
        chown root:git /etc/gitea
        chmod 770 /etc/gitea
        if [[ -f /etc/gitea/app.ini ]]; then
            chown git:git /etc/gitea/app.ini
            chmod 640 /etc/gitea/app.ini
        fi
        print_success "/etc/gitea 权限已修复"
    fi
    
    # Gitea 可执行文件
    if [[ -f "${GITEA_INSTALL_DIR}/gitea" ]]; then
        chown git:git "${GITEA_INSTALL_DIR}/gitea"
        chmod +x "${GITEA_INSTALL_DIR}/gitea"
        print_success "Gitea 可执行文件权限已修复"
    fi

    # 重启服务
    if systemctl is-active --quiet gitea; then
        print_info "重启 Gitea 服务..."
        systemctl restart gitea
        sleep 2
        if systemctl is-active --quiet gitea; then
            print_success "Gitea 服务重启成功"
        else
            print_warning "Gitea 服务重启失败"
        fi
    fi

    print_success "权限修复完成"
    echo
    read -p "按回车键继续..."
}

# 显示部署信息
show_deployment_info() {
    print_header "Gitea 部署信息"

    if [[ -z "$GITEA_DOMAIN" ]]; then
        print_warning "尚未配置域名，请先进行配置"
        echo
        read -p "按回车键继续..."
        return
    fi

    echo "服务信息:"
    echo "  - 域名: ${GITEA_DOMAIN}"
    echo "  - HTTP 访问: http://${GITEA_DOMAIN}"
    echo "  - HTTPS 访问: https://${GITEA_DOMAIN}"
    echo "  - 内部端口: ${GITEA_HTTP_PORT}"
    echo "  - SSH 端口: ${GITEA_SSH_PORT}"
    echo ""
    echo "目录信息:"
    echo "  - 安装目录: ${GITEA_INSTALL_DIR}"
    echo "  - 工作目录: ${GITEA_WORK_DIR}"
    echo "  - 配置文件: /etc/gitea/app.ini"
    echo ""
    echo "服务状态:"
    if systemctl is-active --quiet gitea; then
        print_success "Gitea 服务运行中"
    else
        print_warning "Gitea 服务未运行"
    fi
    echo ""
    echo "=========================================="
    echo "重要提示:"
    echo "=========================================="
    echo ""
    echo "1. 访问 https://${GITEA_DOMAIN} 进行 Web 初始化配置"
    echo "2. 在初始化页面选择:"
    echo "   - 数据库类型: SQLite3 (推荐) 或 MySQL/MariaDB"
    echo "   - 域名: ${GITEA_DOMAIN}"
    echo "   - SSH 端口: ${GITEA_SSH_PORT}"
    echo "   - HTTP 端口: ${GITEA_HTTP_PORT}"
    echo "3. 创建管理员账户"
    echo ""
    echo "=== 常见问题解决 ==="
    echo "1. 如果后台显示不全，请清除浏览器缓存后重试"
    echo "2. 如果迁移仓库时出现404错误，请检查："
    echo "   - 是否已登录管理员账户"
    echo "   - 是否有足够的权限创建仓库"
    echo "   - GitHub访问令牌是否正确"
    echo ""
    echo "常用命令:"
    echo "  - 查看状态: systemctl status gitea"
    echo "  - 重启服务: systemctl restart gitea"
    echo "  - 查看日志: journalctl -u gitea -f"
    echo "  - 权限修复: 选择菜单选项 7"
    echo ""
    echo "=========================================="

    echo
    read -p "按回车键继续..."
}

# 申请并部署 SSL 证书
apply_ssl_certificate() {
    print_header "申请并部署 SSL 证书"

    if [[ -z "$GITEA_DOMAIN" ]]; then
        print_info "尚未配置域名，正在设置..."
        echo ""
        
        # 提示用户输入域名
        while true; do
            GITEA_DOMAIN=$(get_input "请输入 Gitea 服务域名" "${GITEA_DOMAIN}")
            if [[ -z "$GITEA_DOMAIN" ]]; then
                print_error "域名不能为空"
                continue
            fi
            break
        done
        
        print_success "域名配置完成: ${GITEA_DOMAIN}"
        echo ""
    fi

    print_info "域名: ${GITEA_DOMAIN}"
    
    # 检查 acme.sh 是否安装
    if ! command -v acme.sh &> /dev/null && [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        print_warning "acme.sh 未安装，正在安装..."
        curl https://get.acme.sh | sh -s email="admin@${GITEA_DOMAIN}"
        source ~/.bashrc
        # 设置默认 CA 为 Let's Encrypt
        $HOME/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    fi

    # 确保 idn 工具已安装（处理 IDN 国际化域名）
    if ! command -v idn &> /dev/null; then
        print_warning "idn 工具未安装，正在安装..."
        apt update && apt install -y idn
    fi
    
    # 选择申请方式
    echo ""
    print_info "请选择 SSL 证书申请方式:"
    echo ""
    echo "  1. Webroot 方式 (推荐，需要80端口可访问)"
    echo "  2. Standalone 方式 (需要临时停止Nginx，使用80端口)"
    echo "  3. 阿里云 DNS 验证 (推荐，无需开放端口)"
    echo "  4. Cloudflare DNS 验证 (推荐，无需开放端口)"
    echo "  5. 手动 DNS 方式 (适用于无法使用80端口的情况)"
    echo "  6. 使用现有证书 (手动指定证书路径)"
    echo "  7. 跳过证书申请"
    echo ""

    local cert_method
    read -rp "$(echo -e "${YELLOW}请选择申请方式 (1-7): ${NC}")" cert_method

    case $cert_method in
        1)
            apply_ssl_webroot
            ;;
        2)
            apply_ssl_standalone
            ;;
        3)
            apply_ssl_aliyun_dns
            ;;
        4)
            apply_ssl_cloudflare_dns
            ;;
        5)
            apply_ssl_manual_dns
            ;;
        6)
            use_existing_certificate
            ;;
        7)
            print_info "跳过证书申请"
            return
            ;;
        *)
            print_warning "无效选择，默认使用 Webroot 方式"
            apply_ssl_webroot
            ;;
    esac
}

# Webroot 方式申请证书
apply_ssl_webroot() {
    print_info "使用 Webroot 方式申请证书..."
    
    # 检查 Nginx 配置文件是否存在
    if [[ ! -f "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" ]]; then
        print_error "Nginx 配置文件不存在，请先配置 Nginx 反向代理"
        print_info "请选择菜单选项 6: 配置 Nginx 反向代理"
        echo
        read -p "按回车键继续..."
        return
    fi
    
    # 检查 Nginx 服务是否运行
    if ! systemctl is-active --quiet nginx; then
        print_error "Nginx 服务未运行"
        print_info "请先启动 Nginx 服务: systemctl start nginx"
        echo
        read -p "按回车键继续..."
        return
    fi
    
    print_info "请确保:"
    echo "  1. 域名 ${GITEA_DOMAIN} 已正确解析到本服务器"
    echo "  2. 端口 80 已开放且可访问"
    echo "  3. Nginx 服务正在运行"
    echo ""
    
    if ! confirm "是否继续申请证书" "Y"; then
        return
    fi
    
    # 使用 webroot 方式申请证书
    local webroot_path="/var/www/${GITEA_DOMAIN}"
    mkdir -p "${webroot_path}/.well-known/acme-challenge"
    chown -R www-data:www-data "${webroot_path}"
    
    # 临时添加 webroot 验证配置到 Nginx
    local temp_config="/etc/nginx/sites-available/${GITEA_DOMAIN}-acme.conf"
    cat > "$temp_config" << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${GITEA_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root ${webroot_path};
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    
    # 启用临时配置
    ln -sf "$temp_config" "/etc/nginx/sites-enabled/${GITEA_DOMAIN}-acme.conf"
    nginx -t && systemctl reload nginx
    
    # 申请证书
    print_info "正在申请 SSL 证书..."
    if ~/.acme.sh/acme.sh --issue -d "${GITEA_DOMAIN}" --webroot "${webroot_path}" --server https://acme-v02.api.letsencrypt.org/directory --email "admin@${GITEA_DOMAIN}"; then
        print_success "SSL 证书申请成功"
        
        # 移除临时配置
        rm -f "/etc/nginx/sites-enabled/${GITEA_DOMAIN}-acme.conf"
        rm -f "$temp_config"
        
        # 安装证书到标准位置
        local cert_dir="/etc/letsencrypt/live/${GITEA_DOMAIN}"
        mkdir -p "$cert_dir"
        ~/.acme.sh/acme.sh --install-cert -d "${GITEA_DOMAIN}" \
            --key-file "$cert_dir/privkey.pem" \
            --fullchain-file "$cert_dir/fullchain.pem"
        
        # 更新 Nginx 配置为 HTTPS
        update_nginx_for_https
        
        # 更新 Gitea 配置为 HTTPS
        update_gitea_for_https
        
        # 配置自动续期
        configure_cert_renewal
    else
        print_error "SSL 证书申请失败"
        print_info "请检查:"
        echo "  - 域名解析是否正确"
        echo "  - 端口 80 是否可访问"
        echo "  - Nginx 配置是否正确"
        echo ""
        print_info "查看详细日志: ~/.acme.sh/acme.sh.log"
        
        # 移除临时配置
        rm -f "/etc/nginx/sites-enabled/${GITEA_DOMAIN}-acme.conf"
        rm -f "$temp_config"
        nginx -t && systemctl reload nginx
    fi

    echo
    read -p "按回车键继续..."
}

# Standalone 方式申请证书
apply_ssl_standalone() {
    print_info "使用 Standalone 方式申请证书..."
    
    # 检查 Nginx 配置文件是否存在
    if [[ ! -f "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" ]]; then
        print_error "Nginx 配置文件不存在，请先配置 Nginx 反向代理"
        print_info "请选择菜单选项 6: 配置 Nginx 反向代理"
        echo
        read -p "按回车键继续..."
        return
    fi
    
    print_warning "此方式需要临时停止 Nginx 服务"
    print_info "请确保:"
    echo "  1. 域名 ${GITEA_DOMAIN} 已正确解析到本服务器"
    echo "  2. 端口 80 已开放且未被占用"
    echo ""
    
    if ! confirm "是否继续申请证书" "Y"; then
        return
    fi
    
    # 停止 Nginx
    print_info "正在停止 Nginx 服务..."
    systemctl stop nginx
    
    # 申请证书
    print_info "正在申请 SSL 证书..."
    if ~/.acme.sh/acme.sh --issue -d "${GITEA_DOMAIN}" --standalone --server https://acme-v02.api.letsencrypt.org/directory --email "admin@${GITEA_DOMAIN}"; then
        print_success "SSL 证书申请成功"
        
        # 启动 Nginx
        print_info "正在启动 Nginx 服务..."
        systemctl start nginx
        
        # 安装证书到标准位置
        local cert_dir="/etc/letsencrypt/live/${GITEA_DOMAIN}"
        mkdir -p "$cert_dir"
        ~/.acme.sh/acme.sh --install-cert -d "${GITEA_DOMAIN}" \
            --key-file "$cert_dir/privkey.pem" \
            --fullchain-file "$cert_dir/fullchain.pem"
        
        # 更新 Nginx 配置为 HTTPS
        update_nginx_for_https
        
        # 更新 Gitea 配置为 HTTPS
        update_gitea_for_https
        
        # 配置自动续期
        configure_cert_renewal
    else
        print_error "SSL 证书申请失败"
        print_info "请检查:"
        echo "  - 域名解析是否正确"
        echo "  - 端口 80 是否可访问"
        echo ""
        print_info "查看详细日志: ~/.acme.sh/acme.sh.log"
        
        # 启动 Nginx
        print_info "正在启动 Nginx 服务..."
        systemctl start nginx
    fi

    echo
    read -p "按回车键继续..."
}

# 阿里云 DNS 验证方式申请证书
apply_ssl_aliyun_dns() {
    print_info "使用阿里云 DNS 验证方式申请证书..."

    print_info "此方式适用于:"
    echo "  - 服务器无法通过公网80端口访问"
    echo "  - 域名使用阿里云 DNS 解析"
    echo "  - 需要阿里云 AccessKey 进行自动验证"
    echo ""

    if ! confirm "是否继续申请证书" "Y"; then
        return
    fi

    # 配置阿里云密钥
    local aliyun_conf="$CONFIG_DIR/aliyunak.conf"
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    if [ ! -f "$aliyun_conf" ]; then
        print_info "阿里云密钥配置文件不存在，开始创建..."
        local access_key_id access_key_secret
        read -rp "$(echo -e "${YELLOW}请输入阿里云 AccessKey ID: ${NC}")" access_key_id
        read -rp "$(echo -e "${YELLOW}请输入阿里云 AccessKey Secret: ${NC}")" access_key_secret

        # 导出阿里云密钥环境变量
        export Ali_Key="$access_key_id"
        export Ali_Secret="$access_key_secret"
        
        # 保存到配置文件以便后续使用
        cat > "$aliyun_conf" << EOF
# Aliyun DNS API credentials
Ali_Key = $access_key_id
Ali_Secret = $access_key_secret
EOF
        chmod 600 "$aliyun_conf"
        print_success "阿里云密钥配置文件已创建"
    else
        print_success "阿里云密钥配置文件已存在"
        # 从配置文件加载密钥
        export Ali_Key=$(grep "Ali_Key" "$aliyun_conf" | cut -d'=' -f2 | tr -d ' ')
        export Ali_Secret=$(grep "Ali_Secret" "$aliyun_conf" | cut -d'=' -f2 | tr -d ' ')
    fi

    # 申请证书
    print_info "正在申请 SSL 证书..."
    if ~/.acme.sh/acme.sh --issue -d "${GITEA_DOMAIN}" --dns dns_ali --server https://acme-v02.api.letsencrypt.org/directory --email "admin@${GITEA_DOMAIN}"; then
        print_success "SSL 证书申请成功"

        # 安装证书到标准位置
        local cert_dir="/etc/letsencrypt/live/${GITEA_DOMAIN}"
        mkdir -p "$cert_dir"
        ~/.acme.sh/acme.sh --install-cert -d "${GITEA_DOMAIN}" \
            --key-file "$cert_dir/privkey.pem" \
            --fullchain-file "$cert_dir/fullchain.pem"

        # 更新 Nginx 配置为 HTTPS
        update_nginx_for_https

        # 更新 Gitea 配置为 HTTPS
        update_gitea_for_https

        # 配置自动续期
        configure_cert_renewal
    else
        print_error "SSL 证书申请失败"
        print_info "请检查:"
        echo "  - 阿里云 AccessKey 是否正确"
        echo "  - 域名是否使用阿里云 DNS 解析"
        echo "  - 该 AccessKey 是否有 DNS 管理权限"
        echo ""
        print_info "查看详细日志: ~/.acme.sh/acme.sh.log"
    fi

    echo
    read -p "按回车键继续..."
}

# Cloudflare DNS 验证方式申请证书
apply_ssl_cloudflare_dns() {
    print_info "使用 Cloudflare DNS 验证方式申请证书..."

    print_info "此方式适用于:"
    echo "  - 服务器无法通过公网80端口访问"
    echo "  - 域名使用 Cloudflare DNS 解析"
    echo "  - 需要 Cloudflare API Token 或 Global API Key 进行自动验证"
    echo ""

    if ! confirm "是否继续申请证书" "Y"; then
        return
    fi

    # 配置 Cloudflare 凭证
    local cloudflare_conf="$CONFIG_DIR/cloudflare.conf"
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    if [ ! -f "$cloudflare_conf" ]; then
        print_info "Cloudflare 配置文件不存在，开始创建..."
        local auth_type
        while true; do
            read -rp "$(echo -e "${YELLOW}请选择认证方式 (1=API Token, 2=Global API Key): ${NC}")" auth_type
            if [[ "$auth_type" == "1" || "$auth_type" == "2" ]]; then
                break
            fi
            print_error "请选择 1 或 2"
        done

        if [[ "$auth_type" == "1" ]]; then
            # API Token 方式
            local cloudflare_token
            read -rp "$(echo -e "${YELLOW}请输入 Cloudflare API Token: ${NC}")" cloudflare_token

            # 导出 Cloudflare 密钥环境变量
            export CF_Token="$cloudflare_token"
            
            # 保存到配置文件以便后续使用
            cat > "$cloudflare_conf" << EOF
# Cloudflare 认证方式: API Token
CF_Token = $cloudflare_token
EOF
        else
            # Global API Key 方式
            local cloudflare_email
            local cloudflare_key
            read -rp "$(echo -e "${YELLOW}请输入 Cloudflare 邮箱: ${NC}")" cloudflare_email
            read -rp "$(echo -e "${YELLOW}请输入 Cloudflare Global API Key: ${NC}")" cloudflare_key

            # 导出 Cloudflare 密钥环境变量
            export CF_Email="$cloudflare_email"
            export CF_Key="$cloudflare_key"
            
            # 保存到配置文件以便后续使用
            cat > "$cloudflare_conf" << EOF
# Cloudflare 认证方式: Global API Key
CF_Email = $cloudflare_email
CF_Key = $cloudflare_key
EOF
        fi
        chmod 600 "$cloudflare_conf"
        print_success "Cloudflare 配置文件已创建"
    else
        print_success "Cloudflare 配置文件已存在"
        # 从配置文件加载密钥
        if grep -q "CF_Token" "$cloudflare_conf"; then
            # API Token 方式
            export CF_Token=$(grep "CF_Token" "$cloudflare_conf" | cut -d'=' -f2 | tr -d ' ')
        else
            # Global API Key 方式
            export CF_Email=$(grep "CF_Email" "$cloudflare_conf" | cut -d'=' -f2 | tr -d ' ')
            export CF_Key=$(grep "CF_Key" "$cloudflare_conf" | cut -d'=' -f2 | tr -d ' ')
        fi
    fi

    # 确保 idn 工具已安装（处理 IDN 国际化域名）
    if ! command -v idn &> /dev/null; then
        print_warning "idn 工具未安装，正在安装..."
        apt update && apt install -y idn
    fi

    # 申请证书
    print_info "正在申请 SSL 证书..."
    if ~/.acme.sh/acme.sh --issue -d "${GITEA_DOMAIN}" --dns dns_cf --server https://acme-v02.api.letsencrypt.org/directory --email "admin@${GITEA_DOMAIN}"; then
        print_success "SSL 证书申请成功"

        # 安装证书到标准位置
        local cert_dir="/etc/letsencrypt/live/${GITEA_DOMAIN}"
        mkdir -p "$cert_dir"
        ~/.acme.sh/acme.sh --install-cert -d "${GITEA_DOMAIN}" \
            --key-file "$cert_dir/privkey.pem" \
            --fullchain-file "$cert_dir/fullchain.pem"

        # 更新 Nginx 配置为 HTTPS
        update_nginx_for_https

        # 更新 Gitea 配置为 HTTPS
        update_gitea_for_https

        # 配置自动续期
        configure_cert_renewal
    else
        print_error "SSL 证书申请失败"
        print_info "请检查:"
        echo "  - Cloudflare API Token 是否正确"
        echo "  - 域名是否使用 Cloudflare DNS 解析"
        echo "  - 该 Token 是否有 Zone:Edit 权限"
        echo ""
        print_info "查看详细日志: ~/.acme.sh/acme.sh.log"
    fi

    echo
    read -p "按回车键继续..."
}

# 手动 DNS 方式申请证书
apply_ssl_manual_dns() {
    print_info "使用手动 DNS 方式申请证书..."

    print_info "此方式适用于:"
    echo "  - 服务器无法通过公网80端口访问"
    echo "  - 需要使用 DNS 验证域名所有权"
    echo ""
    print_warning "注意: 需要手动添加 DNS TXT 记录"
    echo ""

    if ! confirm "是否继续申请证书" "Y"; then
        return
    fi

    print_info "请按照提示操作..."
    print_info "正在准备 DNS 验证..."

    # 使用 manual 方式，需要用户手动添加 DNS 记录
    if ~/.acme.sh/acme.sh --issue -d "${GITEA_DOMAIN}" --dns --server https://acme-v02.api.letsencrypt.org/directory --email "admin@${GITEA_DOMAIN}"; then
        print_success "SSL 证书申请成功"

        # 安装证书到标准位置
        local cert_dir="/etc/letsencrypt/live/${GITEA_DOMAIN}"
        mkdir -p "$cert_dir"
        ~/.acme.sh/acme.sh --install-cert -d "${GITEA_DOMAIN}" \
            --key-file "$cert_dir/privkey.pem" \
            --fullchain-file "$cert_dir/fullchain.pem"

        # 更新 Nginx 配置为 HTTPS
        update_nginx_for_https

        # 更新 Gitea 配置为 HTTPS
        update_gitea_for_https

        # 配置自动续期
        print_warning "手动 DNS 方式申请的证书无法自动续期"
        print_info "请在证书到期前手动续期"
    else
        print_error "SSL 证书申请失败"
        print_info "请检查 DNS 记录是否正确添加"
    fi

    echo
    read -p "按回车键继续..."
}

# 使用现有证书
use_existing_certificate() {
    print_info "使用现有 SSL 证书..."
    
    echo ""
    local cert_path
    local key_path
    
    read -rp "$(echo -e "${YELLOW}请输入证书文件路径 (fullchain.pem): ${NC}")" cert_path
    read -rp "$(echo -e "${YELLOW}请输入私钥文件路径 (privkey.pem): ${NC}")" key_path
    
    if [[ ! -f "$cert_path" ]]; then
        print_error "证书文件不存在: $cert_path"
        echo
        read -p "按回车键继续..."
        return
    fi
    
    if [[ ! -f "$key_path" ]]; then
        print_error "私钥文件不存在: $key_path"
        echo
        read -p "按回车键继续..."
        return
    fi
    
    # 创建证书目录
    local cert_dir="/etc/letsencrypt/live/${GITEA_DOMAIN}"
    mkdir -p "$cert_dir"
    
    # 复制证书
    cp "$cert_path" "$cert_dir/fullchain.pem"
    cp "$key_path" "$cert_dir/privkey.pem"
    chmod 644 "$cert_dir/fullchain.pem"
    chmod 600 "$cert_dir/privkey.pem"
    
    print_success "证书已复制到: $cert_dir"
    
    # 更新 Nginx 配置为 HTTPS
    update_nginx_for_https
    
    # 更新 Gitea 配置为 HTTPS
    update_gitea_for_https
    
    print_warning "使用现有证书时，请确保证书在到期前手动更新"

    echo
    read -p "按回车键继续..."
}

# 更新 Nginx 配置为 HTTPS（无http2版本）
update_nginx_for_https() {
    print_info "更新 Nginx 配置为 HTTPS..."
    
    if [[ ! -f "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" ]]; then
        print_warning "Nginx 配置文件不存在"
        return
    fi
    
    # 检测证书路径
    local cert_dir="${GITEA_DOMAIN}"
    if [[ ! -d "/etc/letsencrypt/live/${cert_dir}" ]]; then
        if [[ -d "/etc/letsencrypt/live/${cert_dir}-0001" ]]; then
            cert_dir="${cert_dir}-0001"
            print_info "使用证书目录: ${cert_dir}"
        else
            print_error "证书目录不存在"
            return 1
        fi
    fi
    
    # 备份原配置
    cp "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf.bak.$(date +%Y%m%d_%H%M%S)"
    
    # 创建新的 HTTPS 配置（无http2）
    cat > "${NGINX_SITE_DIR}/${GITEA_DOMAIN}.conf" << EOF
# Gitea Git 服务反向代理配置（HTTPS）
# 域名: ${GITEA_DOMAIN}

upstream gitea_backend {
    server 127.0.0.1:${GITEA_HTTP_PORT};
    keepalive 32;
}

# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${GITEA_DOMAIN};

    access_log ${NGINX_LOG_DIR}/${GITEA_DOMAIN}.access.log;
    error_log ${NGINX_LOG_DIR}/${GITEA_DOMAIN}.error.log;

    location /.well-known/acme-challenge/ {
        root /var/www/${GITEA_DOMAIN};
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS 配置
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${GITEA_DOMAIN};

    access_log ${NGINX_LOG_DIR}/${GITEA_DOMAIN}.access.log;
    error_log ${NGINX_LOG_DIR}/${GITEA_DOMAIN}.error.log;

    client_max_body_size 100M;

    # SSL 证书配置
    ssl_certificate /etc/letsencrypt/live/${cert_dir}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${cert_dir}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://gitea_backend;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF
    
    print_success "Nginx 配置已更新为 HTTPS"
    
    # 测试并重载 Nginx
    if nginx -t &> /dev/null; then
        print_success "Nginx 配置测试通过"
        systemctl reload nginx
        print_success "Nginx 配置已重载"
    else
        print_error "Nginx 配置测试失败"
        nginx -t
        return 1
    fi
}

# 更新 Gitea 配置为 HTTPS
update_gitea_for_https() {
    print_info "更新 Gitea 配置为 HTTPS..."
    
    if [[ ! -f /etc/gitea/app.ini ]]; then
        print_warning "Gitea 配置文件不存在"
        return
    fi
    
    # 备份原配置
    cp /etc/gitea/app.ini /etc/gitea/app.ini.bak.$(date +%Y%m%d_%H%M%S)
    
    # 更新 ROOT_URL 为 HTTPS
    sed -i "s|^ROOT_URL.*|ROOT_URL = https://${GITEA_DOMAIN}/|" /etc/gitea/app.ini
    
    # 确保 PROTOCOL 为 http（因为 Nginx 处理 HTTPS）
    sed -i "s|^PROTOCOL.*|PROTOCOL = http|" /etc/gitea/app.ini
    
    print_success "Gitea 配置已更新为 HTTPS"
    
    # 重启 Gitea 服务
    if systemctl is-active --quiet gitea; then
        print_info "重启 Gitea 服务..."
        systemctl restart gitea
        sleep 2
        if systemctl is-active --quiet gitea; then
            print_success "Gitea 服务重启成功"
        else
            print_warning "Gitea 服务重启失败"
        fi
    fi
}

# 配置自动续期
configure_cert_renewal() {
    print_info "配置 SSL 证书自动续期..."
    
    # 创建续期钩子脚本
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/gitea-restart.sh << EOF
#!/bin/bash
# SSL 证书续期后重启 Gitea 和 Nginx

# 重载 Nginx
systemctl reload nginx

# 重启 Gitea
systemctl restart gitea

# 记录日志
echo "[\$(date)] SSL 证书已续期，Gitea 和 Nginx 已重启" >> /var/log/gitea-cert-renewal.log
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/gitea-restart.sh
    
    print_success "自动续期配置完成"
    print_info "证书将在到期前自动续期"
}

# 重启 Gitea 服务
restart_gitea_service() {
    print_header "重启 Gitea 服务"

    if systemctl is-active --quiet gitea; then
        print_info "正在重启 Gitea 服务..."
        systemctl restart gitea
        sleep 2

        if systemctl is-active --quiet gitea; then
            print_success "Gitea 服务重启成功"
        else
            print_error "Gitea 服务重启失败"
            print_info "查看日志: journalctl -u gitea -n 50"
        fi
    else
        print_warning "Gitea 服务未运行，正在启动..."
        systemctl start gitea
        sleep 2

        if systemctl is-active --quiet gitea; then
            print_success "Gitea 服务启动成功"
        else
            print_error "Gitea 服务启动失败"
            print_info "查看日志: journalctl -u gitea -n 50"
        fi
    fi

    echo
    read -p "按回车键继续..."
}

# 查看 Gitea 日志
view_gitea_logs() {
    print_header "Gitea 日志"

    echo "正在显示 Gitea 日志（按 Ctrl+C 退出）..."
    echo ""
    journalctl -u gitea -f --no-pager
}

# 安装 Act Runner (工作流)
install_act_runner() {
    print_header "安装 Act Runner (Gitea Actions)"

    # 创建安装目录
    mkdir -p "${ACT_RUNNER_INSTALL_DIR}"
    mkdir -p "${ACT_RUNNER_DATA_DIR}"

    # 检测系统架构
    local ARCH
    ARCH=$(uname -m)
    local RUNNER_ARCH
    if [[ "$ARCH" == "x86_64" ]]; then
        RUNNER_ARCH="linux-amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        RUNNER_ARCH="linux-arm64"
    else
        print_error "不支持的系统架构: $ARCH"
        return 1
    fi

    # 检查 Node.js 24 是否已安装
    print_info "检查 Node.js 版本..."
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        print_success "Node.js 已安装: $node_version"
        # 确保使用 Node.js 24
        if command -v nvm &> /dev/null; then
            nvm use 24
            print_info "已切换到 Node.js 24"
        fi
    else
        print_warning "Node.js 未安装，继续安装 Act Runner"
    fi

    # 下载 Act Runner
    print_info "正在下载 Act Runner ${ACT_RUNNER_VERSION} (${RUNNER_ARCH})..."
    wget -O "${ACT_RUNNER_INSTALL_DIR}/act_runner" "https://dl.gitea.com/act_runner/${ACT_RUNNER_VERSION}/act_runner-${ACT_RUNNER_VERSION}-${RUNNER_ARCH}"

    # 设置权限
    chmod +x "${ACT_RUNNER_INSTALL_DIR}/act_runner"
    chown -R git:git "${ACT_RUNNER_INSTALL_DIR}"
    chown -R git:git "${ACT_RUNNER_DATA_DIR}"

    # 安装 nvm 到 /opt/nvm
    print_info "安装 nvm 到 /opt/nvm..."
    if [[ ! -d "/opt/nvm" ]]; then
        mkdir -p /opt/nvm
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash -s -- --no-install
        cp -r "$HOME/.nvm/"* "/opt/nvm/"
        chown -R git:git /opt/nvm
        chmod -R 755 /opt/nvm
        print_success "nvm 安装到 /opt/nvm 成功"
    else
        print_info "nvm 已安装在 /opt/nvm"
    fi

    # 确保 git 用户配置了 nvm
    print_info "确保 git 用户配置了 nvm..."
    if [[ -f "/home/git/.bashrc" ]]; then
        if ! grep -q "nvm.sh" "/home/git/.bashrc"; then
            print_info "为 git 用户添加 nvm 配置..."
            echo "" >> /home/git/.bashrc
            echo "# Load NVM" >> /home/git/.bashrc
            echo "export NVM_DIR=\"/opt/nvm\"" >> /home/git/.bashrc
            echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"  # This loads nvm" >> /home/git/.bashrc
            echo "[ -s \"\$NVM_DIR/bash_completion\" ] && \. \"\$NVM_DIR/bash_completion\"  # This loads nvm bash_completion" >> /home/git/.bashrc
            chown git:git /home/git/.bashrc
        fi
    fi

    # 安装 Node.js 24
    print_info "安装 Node.js 24..."
    sudo -u git bash -c 'source /opt/nvm/nvm.sh && nvm install 24 && nvm use 24 && nvm alias default 24'

    # 创建 Node.js 符号链接到系统路径
    print_info "创建 Node.js 符号链接..."
    if [[ -f "/opt/nvm/versions/node/v24.14.0/bin/node" ]]; then
        ln -sf /opt/nvm/versions/node/v24.14.0/bin/node /usr/local/bin/node
        ln -sf /opt/nvm/versions/node/v24.14.0/bin/npm /usr/local/bin/npm
        ln -sf /opt/nvm/versions/node/v24.14.0/bin/npx /usr/local/bin/npx
        chmod +x /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx
        print_success "Node.js 符号链接创建成功"
    else
        print_warning "Node.js 可执行文件未找到，跳过创建符号链接"
    fi

    # 验证安装
    if "${ACT_RUNNER_INSTALL_DIR}/act_runner" --version &> /dev/null; then
        print_success "Act Runner 安装成功: $(${ACT_RUNNER_INSTALL_DIR}/act_runner --version)"
    else
        print_error "Act Runner 安装失败"
        return 1
    fi

    # 生成配置文件
    print_info "生成 Act Runner 配置文件..."
    "${ACT_RUNNER_INSTALL_DIR}/act_runner" generate-config > "${ACT_RUNNER_DATA_DIR}/config.yaml"

    # 修复配置文件，使用主机模式运行
    print_info "配置 Act Runner 使用主机模式..."
    # 先删除可能存在的错误配置
    sed -i '/labels:\s*\[\]/d' "${ACT_RUNNER_DATA_DIR}/config.yaml"
    # 确保 labels 配置格式正确
    if ! grep -q "labels:" "${ACT_RUNNER_DATA_DIR}/config.yaml"; then
        sed -i '/fetch_interval: 2s/a \  labels:' "${ACT_RUNNER_DATA_DIR}/config.yaml"
    fi
    # 添加主机模式标签
    if ! grep -q "linux_amd64:host" "${ACT_RUNNER_DATA_DIR}/config.yaml"; then
        sed -i '/labels:/a \    - linux_amd64:host' "${ACT_RUNNER_DATA_DIR}/config.yaml"
    fi
    # 注释 container 配置
    sed -i 's|^container:|# container:|g' "${ACT_RUNNER_DATA_DIR}/config.yaml"

    # 创建 Systemd 服务文件
    cat > /etc/systemd/system/act-runner.service << EOF
[Unit]
Description=Gitea Actions Runner
After=network.target

[Service]
User=git
Group=git
WorkingDirectory=${ACT_RUNNER_DATA_DIR}
Environment=HOME=/home/git
Environment=NODE_VERSION=24
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=${ACT_RUNNER_INSTALL_DIR}/act_runner daemon --config ${ACT_RUNNER_DATA_DIR}/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    print_success "Act Runner 服务文件创建成功"

    # 重载 systemd
    systemctl daemon-reload

    # 启用开机自启
    systemctl enable act-runner

    print_success "Act Runner 安装完成"
    echo ""
    print_info "下一步操作:"
    echo "1. 登录 Gitea 管理界面"
    echo "2. 进入 '站点管理' > 'Actions' > '运行器'"
    echo "3. 获取注册令牌"
    echo ""
    
    # 交互式注册
    if confirm "是否现在注册 Act Runner" "Y"; then
        print_info "请输入 Gitea 实例 URL (例如: https://git.13aq.com):"
        local instance_url
        read -rp "实例 URL: " instance_url
        
        print_info "请输入从 Gitea 管理界面获取的注册令牌:"
        local token
        read -rp "注册令牌: " token
        
        print_info "请输入运行器名称 (默认: Gitea Runner):"
        local runner_name
        read -rp "运行器名称: " runner_name
        runner_name=${runner_name:-"Gitea Runner"}
        
        print_info "正在注册 Act Runner..."
        sudo -u git bash -c "cd ${ACT_RUNNER_DATA_DIR} && ${ACT_RUNNER_INSTALL_DIR}/act_runner register --no-interactive --instance '$instance_url' --token '$token' --name '$runner_name' --labels 'linux_amd64:host'"
        
        if [ $? -eq 0 ]; then
            print_success "Act Runner 注册成功"
            
            # 启动服务
            if confirm "是否立即启动 Act Runner 服务" "Y"; then
                systemctl start act-runner
                sleep 2
                if systemctl is-active --quiet act-runner; then
                    print_success "Act Runner 服务启动成功"
                else
                    print_error "Act Runner 服务启动失败"
                    print_info "查看日志: journalctl -u act-runner -n 50"
                fi
            fi
        else
            print_error "Act Runner 注册失败"
            print_info "请手动运行注册命令: sudo -u git ${ACT_RUNNER_INSTALL_DIR}/act_runner register"
        fi
    else
        print_info "您可以稍后手动注册: sudo -u git ${ACT_RUNNER_INSTALL_DIR}/act_runner register"
    fi
    
    echo ""
    print_info "注意: 已配置为在主机上直接运行，不使用 Docker"
    echo ""
    read -p "按回车键继续..."
}

# 删除 Act Runner (工作流)
delete_act_runner() {
    print_header "删除 Act Runner (Gitea Actions)"

    # 检查 Act Runner 是否安装
    if [[ ! -f "${ACT_RUNNER_INSTALL_DIR}/act_runner" ]]; then
        print_error "Act Runner 未安装"
        echo ""
        read -p "按回车键继续..."
        return 1
    fi

    # 停止服务
    if systemctl is-active --quiet act-runner; then
        print_info "正在停止 Act Runner 服务..."
        systemctl stop act-runner
        if systemctl is-active --quiet act-runner; then
            print_error "Act Runner 服务停止失败"
            echo ""
            read -p "按回车键继续..."
            return 1
        fi
        print_success "Act Runner 服务已停止"
    fi

    # 禁用服务
    if systemctl is-enabled --quiet act-runner; then
        print_info "正在禁用 Act Runner 服务..."
        systemctl disable act-runner
        print_success "Act Runner 服务已禁用"
    fi

    # 删除服务文件
    if [[ -f "/etc/systemd/system/act-runner.service" ]]; then
        print_info "正在删除 Act Runner 服务文件..."
        rm -f "/etc/systemd/system/act-runner.service"
        print_success "Act Runner 服务文件已删除"
    fi

    # 重载 systemd
    print_info "正在重载 systemd 配置..."
    systemctl daemon-reload
    print_success "systemd 配置已重载"

    # 删除安装目录
    if [[ -d "${ACT_RUNNER_INSTALL_DIR}" ]]; then
        print_info "正在删除 Act Runner 安装目录..."
        rm -rf "${ACT_RUNNER_INSTALL_DIR}"
        print_success "Act Runner 安装目录已删除"
    fi

    # 删除数据目录
    if [[ -d "${ACT_RUNNER_DATA_DIR}" ]]; then
        print_info "正在删除 Act Runner 数据目录..."
        rm -rf "${ACT_RUNNER_DATA_DIR}"
        print_success "Act Runner 数据目录已删除"
    fi

    print_success "Act Runner 已成功删除"
    echo ""
    read -p "按回车键继续..."
}

# 修改端口号配置
modify_port_config() {
    print_header "修改端口号配置"

    # 检查配置文件是否存在
    if [[ ! -f /etc/gitea/app.ini ]]; then
        print_error "Gitea 配置文件不存在，请先部署 Gitea"
        echo ""
        read -p "按回车键继续..."
        return 1
    fi

    # 读取当前配置
    if [[ -f /etc/gitea/app.ini ]]; then
        # 读取当前 SSH 端口
        current_ssh_port=$(grep "^SSH_PORT" /etc/gitea/app.ini | cut -d'=' -f2 | tr -d ' ')
        # 读取当前 HTTP 端口
        current_http_port=$(grep "^HTTP_PORT" /etc/gitea/app.ini | cut -d'=' -f2 | tr -d ' ')
        
        # 如果配置文件中没有这些值，使用默认值
        current_ssh_port=${current_ssh_port:-"${GITEA_SSH_PORT}"}
        current_http_port=${current_http_port:-"${GITEA_HTTP_PORT}"}
    fi

    echo "当前配置:"
    echo "  - SSH 端口: ${current_ssh_port}"
    echo "  - HTTP 端口: ${current_http_port}"
    echo ""

    # 获取用户输入
    local new_ssh_port
    new_ssh_port=$(get_input "请输入新的 SSH 端口" "${current_ssh_port}")
    
    local new_http_port
    new_http_port=$(get_input "请输入新的 HTTP 端口" "${current_http_port}")

    echo ""
    print_info "新配置:"
    echo "  - SSH 端口: ${new_ssh_port}"
    echo "  - HTTP 端口: ${new_http_port}"
    echo ""

    if ! confirm "确认修改端口配置" "Y"; then
        print_info "配置修改已取消"
        echo ""
        read -p "按回车键继续..."
        return 0
    fi

    # 备份原配置文件
    cp /etc/gitea/app.ini /etc/gitea/app.ini.bak.$(date +%Y%m%d_%H%M%S)
    print_info "原配置文件已备份"

    # 更新配置文件
    sed -i "s|^SSH_PORT.*|SSH_PORT = ${new_ssh_port}|" /etc/gitea/app.ini
    sed -i "s|^HTTP_PORT.*|HTTP_PORT = ${new_http_port}|" /etc/gitea/app.ini

    # 更新脚本中的全局变量
    GITEA_SSH_PORT="${new_ssh_port}"
    GITEA_HTTP_PORT="${new_http_port}"

    print_success "端口配置已更新"

    # 重启 Gitea 服务
    if systemctl is-active --quiet gitea; then
        print_info "重启 Gitea 服务..."
        systemctl restart gitea
        sleep 2
        if systemctl is-active --quiet gitea; then
            print_success "Gitea 服务重启成功"
        else
            print_error "Gitea 服务重启失败"
            print_info "查看日志: journalctl -u gitea -n 50"
        fi
    else
        print_warning "Gitea 服务未运行，请手动启动服务"
    fi

    echo ""
    print_info "注意: 如果修改了 SSH 端口为 22，请确保该端口未被其他服务占用"
    echo ""
    read -p "按回车键继续..."
}

# 完整部署（一键安装，含HTTPS）
full_deployment() {
    print_header "完整部署 Gitea（含 HTTPS）"

    if ! configure_interactive; then
        return
    fi

    check_environment
    create_git_user
    install_gitea
    configure_systemd
    configure_nginx
    
    # 询问是否申请 SSL 证书
    echo ""
    print_info "基础部署完成，接下来申请 SSL 证书..."
    echo ""
    
    if confirm "是否立即申请 SSL 证书（推荐）" "Y"; then
        apply_ssl_certificate
    else
        print_warning "跳过 SSL 证书申请"
        print_info "您可以稍后使用菜单选项 9 申请证书"
    fi
    
    print_header "部署完成"
    show_deployment_info
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 主函数
main() {
    check_root

    while true; do
        show_menu
        local choice
        read -rp "$(echo -e "${YELLOW}请选择操作 (0-11): ${NC}")" choice

        case $choice in
            1)
                full_deployment
                ;;
            2)
                check_environment
                ;;
            3)
                create_git_user
                ;;
            4)
                install_gitea
                ;;
            5)
                configure_systemd
                ;;
            6)
                configure_nginx
                ;;
            7)
                fix_permissions
                ;;
            8)
                show_deployment_info
                ;;
            9)
                apply_ssl_certificate
                ;;
            10)
                restart_gitea_service
                ;;
            11)
                view_gitea_logs
                ;;
            12)
                install_act_runner
                ;;
            13)
                delete_act_runner
                ;;
            14)
                modify_port_config
                ;;
            0)
                print_info "感谢使用，再见！"
                exit 0
                ;; 

            *)
                print_warning "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 执行主函数
main "$@"
