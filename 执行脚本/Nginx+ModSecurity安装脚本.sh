#!/bin/bash
#
# Nginx 1.25.4 + ModSecurity 3.0.12 源码编译安装脚本
# 用途: 从源码编译安装 Nginx + ModSecurity v3
# 适配: Ubuntu 22.04.5 LTS
#

set -e # 遇到错误立即退出
set -u # 使用未定义变量时报错

# ========== 配置变量 ==========
# 可自定义的变量（可通过环境变量覆盖）
NGINX_VERSION="${NGINX_VERSION:-1.25.4}"
MODSECURITY_VERSION="${MODSECURITY_VERSION:-3.0.12}"
MODSECURITY_NGINX_VERSION="${MODSECURITY_NGINX_VERSION:-1.0.3}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/etc/nginx}"
SRC_DIR="/usr/local/src"

# 日志文件
LOG_FILE="/var/log/nginx_install.log"
BACKUP_DIR="/service/nginx/backup"

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========== 进度条定义 ==========
TOTAL_STEPS=14
CURRENT_STEP=0

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local message="$3"

    local color
    if [[ $current -lt 5 ]]; then
        color="${RED}"
    elif [[ $current -lt 10 ]]; then
        color="${YELLOW}"
    else
        color="${GREEN}"
    fi

    printf "\r${CYAN}[进度]${NC} ${color}第${current}步/${total}步${NC} - ${CYAN}%s${NC}" "$message"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# 增加进度
next_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
}

# ========== 日志函数 ==========
log_info() {
    echo -e "${BLUE}[信息]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[警告]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[错误]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# ========== 检查函数 ==========
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

check_system() {
    log_info "检查系统环境..."

    # 检查操作系统
    if ! grep -q "Ubuntu 22.04" /etc/os-release 2>/dev/null; then
        log_warn "未检测到 Ubuntu 22.04，脚本可能不兼容"
    fi

    # 检查磁盘空间
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ -z "$DISK_GB" ]]; then
        log_warn "无法获取磁盘空间信息"
    elif [[ $DISK_GB -lt 10 ]]; then
        if [[ $DISK_GB -eq 0 ]]; then
            DISK_MB=$(df -BM / | awk 'NR==2{print $4}' | sed 's/M//')
            log_warn "磁盘空间不足 10GB，当前 ${DISK_MB}MB"
        else
            log_warn "磁盘空间不足 10GB，当前 ${DISK_GB}GB"
        fi
    fi

    log_success "系统检查完成"
}

# ========== 安装编译依赖 ==========
install_dependencies() {
    log_info "安装编译依赖..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get upgrade -y -qq

    # 安装编译工具和依赖库
    apt-get install -y -qq \
        build-essential \
        gcc \
        g++ \
        make \
        libtool \
        autoconf \
        automake \
        libpcre3 \
        libpcre3-dev \
        libssl-dev \
        zlib1g \
        zlib1g-dev \
        libxml2 \
        libxml2-dev \
        libxslt1-dev \
        libcurl4-openssl-dev \
        liblua5.3-dev \
        liblmdb-dev \
        libyaml-dev \
        libapr1-dev \
        libaprutil1-dev \
        libcurl4-openssl-dev \
        libyajl-dev \
        libpcre2-dev \
        git \
        curl \
        wget \
        unzip \
        pkg-config \
        ca-certificates \
        flex \
        bison

    log_success "编译依赖安装完成"
}

# ========== 创建目录结构 ==========
setup_directories() {
    log_info "创建目录结构..."

    # 创建核心目录结构
    mkdir -p /service/nginx/{build,src}
    mkdir -p /etc/nginx/{conf.d,disabled,ssl,modsecurity/{rules,custom-rules,logs,tmp},snippets}
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /var/log/nginx/{site,modsecurity}
    mkdir -p /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}
    mkdir -p /var/www/html
    mkdir -p ${SRC_DIR}

    # 创建 www-data 用户（如果不存在）
    if ! id -u www-data &>/dev/null; then
        groupadd -r www-data 2>/dev/null || true
        useradd -r -g www-data -s /bin/false -d /var/www -M www-data 2>/dev/null || true
    fi

    # 设置权限
    chown -R www-data:www-data /etc/nginx /var/log/nginx /var/www/html /var/cache/nginx
    chmod -R 755 /service/nginx /etc/nginx /var/www/html /var/cache/nginx
    chmod -R 700 /etc/nginx/ssl /etc/nginx/modsecurity/tmp

    log_success "目录结构创建完成"
}

# ========== 下载源码 ==========
download_sources() {
    log_info "下载源码..."

    cd ${SRC_DIR}

    # 下载 ModSecurity v3
    if [[ ! -d "modsecurity-v${MODSECURITY_VERSION}/.git" ]]; then
        rm -rf "modsecurity-v${MODSECURITY_VERSION}"
        log_info "下载 ModSecurity ${MODSECURITY_VERSION}..."
        git clone --tags https://github.com/geekmakersun/ModSecurity.git "modsecurity-v${MODSECURITY_VERSION}" || {
            log_error "ModSecurity 下载失败"
            exit 1
        }
    fi

    # 下载 ModSecurity-Nginx 连接器
    if [[ ! -d "modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}/.git" ]]; then
        rm -rf "modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}"
        log_info "下载 ModSecurity-Nginx 连接器 ${MODSECURITY_NGINX_VERSION}..."
        git clone https://github.com/geekmakersun/ModSecurity-nginx.git "modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}" || {
            log_error "ModSecurity-Nginx 连接器下载失败"
            exit 1
        }
    fi

    # 下载 Nginx
    if [[ ! -d "nginx-${NGINX_VERSION}/.git" ]]; then
        rm -rf "nginx-${NGINX_VERSION}"
        log_info "下载 Nginx ${NGINX_VERSION}..."
        git clone https://github.com/geekmakersun/nginx.git "nginx-${NGINX_VERSION}" || {
            log_error "Nginx 下载失败"
            exit 1
        }
    fi

    log_success "源码下载完成"
}

# ========== 编译安装 ModSecurity ==========
compile_modsecurity() {
    log_info "编译安装 ModSecurity..."

    cd "${SRC_DIR}/modsecurity-v${MODSECURITY_VERSION}"

    # 清理之前的编译
    git submodule update --init --recursive 2>/dev/null || true

    # 配置编译
    ./build.sh
    ./configure \
        --prefix=/usr/local/modsecurity \
        --with-yajl \
        --with-lmdb \
        --with-lua \
        --with-curl \
        --with-pcre2 \
        --enable-parser-generation \
        --enable-mutex-on-pm

    # 编译安装
    make -j$(nproc)
    make install

    # 更新动态链接库缓存
    echo "/usr/local/modsecurity/lib" > /etc/ld.so.conf.d/modsecurity.conf
    ldconfig

    log_success "ModSecurity 编译安装完成"
}

# ========== 编译安装 Nginx ==========
compile_nginx() {
    log_info "编译安装 Nginx..."

    cd "${SRC_DIR}/nginx-${NGINX_VERSION}"

    # 配置编译参数
    auto/configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=www-data \
        --group=www-data \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --add-module="${SRC_DIR}/modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}" \
        --with-cc-opt="-I/usr/local/modsecurity/include -O2 -fstack-protector-strong -Wformat -Werror=format-security" \
        --with-ld-opt="-L/usr/local/modsecurity/lib -Wl,-rpath,/usr/local/modsecurity/lib"

    # 编译安装
    make -j$(nproc)
    make install

    log_success "Nginx 编译安装完成"
}

# ========== 下载 CRS 规则 ==========
download_crs() {
    log_info "下载 OWASP CRS 规则集..."

    if [[ ! -d /usr/share/modsecurity-crs ]]; then
        cd /usr/share
        git clone --depth 1 git@github.com:geekmakersun/coreruleset.git modsecurity-crs || {
            log_warn "CRS 规则集下载失败，将使用基础规则"
            mkdir -p /usr/share/modsecurity-crs/rules
        }
    fi

    # 创建 CRS 设置文件
    if [[ -f /usr/share/modsecurity-crs/crs-setup.conf.example ]]; then
        cp /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
    fi

    log_success "CRS 规则集下载完成"
}

# ========== 配置 ModSecurity ==========
configure_modsecurity() {
    log_info "配置 ModSecurity..."

    # 备份旧配置文件
    mkdir -p "${BACKUP_DIR}/modsecurity"
    for f in /etc/nginx/modsecurity/modsec.conf /etc/nginx/modsecurity/custom.conf; do
        if [[ -f "$f" ]]; then
            cp "$f" "${BACKUP_DIR}/modsecurity/$(basename "$f").bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        fi
    done

    # 创建 ModSecurity 主配置文件
    cat > /etc/nginx/modsecurity/modsec.conf << 'EOF'
# ModSecurity 核心配置
SecRuleEngine On
SecRequestBodyAccess On
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml application/json

# 临时文件目录
SecDataDir /etc/nginx/modsecurity/tmp
SecTmpDir /etc/nginx/modsecurity/tmp

# 日志配置
SecDebugLog /var/log/nginx/modsecurity/debug.log
SecDebugLogLevel 0
SecAuditLog /var/log/nginx/modsecurity/audit.log
SecAuditLogFormat JSON
SecAuditLogType Serial
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"

# 请求限制
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecResponseBodyLimit 524288

# 文件上传
SecUploadDir /etc/nginx/modsecurity/tmp
SecUploadKeepFiles Off

# 加载 CRS 规则
Include /usr/share/modsecurity-crs/crs-setup.conf
Include /usr/share/modsecurity-crs/rules/*.conf

# 加载自定义规则
Include /etc/nginx/modsecurity/custom.conf
EOF

    # 创建自定义安全规则
    cat > /etc/nginx/modsecurity/custom.conf << 'EOF'
# ===========================================
# ModSecurity 自定义安全规则
# 规则 ID 范围: 100000-199999
# ===========================================

# ---------- XSS 攻击检测 (规则 ID: 100001-100099) ----------
SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx <script[\s\S]*?>|javascript:|on\w+\s*=" \
    "id:100001,phase:2,deny,status:403,log,msg:'检测到 XSS 攻击',setenv:MODSEC_ATTACK_TYPE=xss"

SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx <iframe|<object|<embed|<svg[\s\S]*?onload" \
    "id:100002,phase:2,deny,status:403,log,msg:'检测到 XSS 攻击 (iframe/object/embed)',setenv:MODSEC_ATTACK_TYPE=xss"

# ---------- SQL 注入检测 (规则 ID: 100100-100199) ----------
SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx (?i)(union\s+select|select\s+from|insert\s+into|delete\s+from|drop\s+table|update\s+\w+\s+set)" \
    "id:100100,phase:2,deny,status:403,log,msg:'检测到 SQL 注入攻击',setenv:MODSEC_ATTACK_TYPE=sql_injection"

SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx (?i)(or\s+1\s*=\s*1|and\s+1\s*=\s*1|'\s*or\s+'|\"\s*or\s+\")" \
    "id:100101,phase:2,deny,status:403,log,msg:'检测到 SQL 注入攻击 (布尔型)',setenv:MODSEC_ATTACK_TYPE=sql_injection"

# ---------- 命令注入检测 (规则 ID: 100200-100299) ----------
SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx (?i)(;|\||`|\$\(|\$\{)\s*(ls|cat|pwd|whoami|id|uname|wget|curl|nc|bash|sh|python|perl|ruby|php)" \
    "id:100200,phase:2,deny,status:403,log,msg:'检测到命令注入攻击',setenv:MODSEC_ATTACK_TYPE=command_injection"

# ---------- 文件包含攻击检测 (规则 ID: 100300-100399) ----------
SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx (?i)(php://|file://|expect://|data://|zip://|phar://)" \
    "id:100300,phase:2,deny,status:403,log,msg:'检测到文件包含攻击 (协议包装器)',setenv:MODSEC_ATTACK_TYPE=file_inclusion"

# ---------- 路径遍历攻击检测 (规则 ID: 100400-100499) ----------
SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx \.\./|\.\.\\\\" \
    "id:100400,phase:2,deny,status:403,log,msg:'检测到路径遍历攻击',setenv:MODSEC_ATTACK_TYPE=path_traversal"

# ---------- 敏感文件访问检测 (规则 ID: 100500-100599) ----------
SecRule REQUEST_URI "@rx (?i)\.(env|git|svn|bak|backup|sql|conf|config|ini|log|sh|py|pl|rb)$" \
    "id:100500,phase:2,deny,status:403,log,msg:'检测到敏感文件访问',setenv:MODSEC_ATTACK_TYPE=sensitive_file"

# ---------- 敏感路径访问检测 (规则 ID: 100600-100699) ----------
SecRule REQUEST_URI "@rx (?i)^/(admin|manager|phpmyadmin|mysql|backup|config|test|tmp|debug)" \
    "id:100600,phase:2,deny,status:403,log,msg:'检测到敏感路径访问',setenv:MODSEC_ATTACK_TYPE=sensitive_path"

# ---------- 恶意编码检测 (规则 ID: 100700-100799) ----------
SecRule REQUEST_URI|REQUEST_BODY|ARGS "@rx (?i)(%3Cscript|%3C/script|%3Ciframe|%3Cobject|%3Cembed|%253C)" \
    "id:100700,phase:2,deny,status:403,log,msg:'检测到恶意编码攻击',setenv:MODSEC_ATTACK_TYPE=malicious_encoding"
EOF

    # 配置文件权限
    chown -R www-data:www-data /etc/nginx/modsecurity
    chmod 640 /etc/nginx/modsecurity/modsec.conf
    chmod 640 /etc/nginx/modsecurity/custom.conf

    log_success "ModSecurity 配置完成"
}

# ========== 配置 Nginx ==========
configure_nginx() {
    log_info "配置 Nginx..."

    # 备份旧配置文件
    mkdir -p "${BACKUP_DIR}/nginx" "${BACKUP_DIR}/snippets"
    if [[ -f /etc/nginx/nginx.conf ]]; then
        cp /etc/nginx/nginx.conf "${BACKUP_DIR}/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    for f in /etc/nginx/snippets/*.conf; do
        if [[ -f "$f" ]]; then
            cp "$f" "${BACKUP_DIR}/snippets/$(basename "$f").bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        fi
    done

    # 创建 Nginx 主配置文件
    cat > /etc/nginx/nginx.conf << 'EOF'
# Nginx 主配置文件
user  www-data;
worker_processes  auto;
error_log  /var/log/nginx/global.error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/global.access.log  main;

    # 性能优化配置
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    server_tokens off;

    # ModSecurity 配置
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsecurity/modsec.conf;

    # 错误页面配置
    include /etc/nginx/snippets/error-pages.conf;

    # 多站点管理
    include /etc/nginx/sites-enabled/*.conf;

    # SSL/TLS 基础配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
}
EOF

    # 创建共用配置片段
    cat > /etc/nginx/snippets/common.conf << 'EOF'
# Nginx 共用配置片段

location / {
    try_files $uri $uri/ =404;
}

location ~ /\.ht {
    deny all;
}

location ~ /\. {
    deny all;
}

location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
}
EOF

    # 创建错误页面处理配置
    cat > /etc/nginx/snippets/error-pages.conf << 'EOF'
error_page 400 /error/400_错误请求.html;
error_page 401 /error/401_未授权.html;
error_page 403 /error/403_通用安全威胁.html;
error_page 404 /error/404_资源未找到.html;
error_page 500 /error/500_服务器错误.html;
error_page 502 /error/502_错误网关.html;
error_page 503 /error/503_服务不可用.html;
error_page 504 /error/504_网关超时.html;
EOF

    # 创建安全设置
    cat > /etc/nginx/snippets/security.conf << 'EOF'
# 安全设置
if ($request_uri ~* "\.\.\./") {
    return 403;
}

if ($request_method !~ ^(GET|HEAD|POST)$) {
    return 405;
}

add_header X-Content-Type-Options nosniff;
add_header X-Frame-Options SAMEORIGIN;
add_header X-XSS-Protection "1; mode=block";
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';";
EOF

    # 创建默认站点
    cat > /etc/nginx/sites-enabled/default.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.html index.htm;

    access_log /var/log/nginx/site/default.access.log main;
    error_log /var/log/nginx/site/default.error.log warn;

    location /error/ {
        alias /var/www/error/;
        internal;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

    # 创建默认首页
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>默认站点 | Nginx + ModSecurity</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .info { background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .success { color: green; }
    </style>
</head>
<body>
    <h1>默认站点已启用</h1>
    <div class="info">
        <p><strong>Nginx:</strong> <span id="nginx-version">编译安装版本</span></p>
        <p><strong>ModSecurity:</strong> <span class="success">已启用</span></p>
        <p><strong>WAF 状态:</strong> <span class="success">运行中</span></p>
    </div>
    <p>ModSecurity Web 应用防火墙正在保护此站点。</p>
</body>
</html>
EOF

    # 配置文件权限
    chown -R www-data:www-data /etc/nginx /var/www/html
    chmod -R 644 /etc/nginx/nginx.conf /etc/nginx/snippets/*.conf /etc/nginx/sites-enabled/default.conf

    log_success "Nginx 配置完成"
}

# ========== 安装错误页面 ==========
install_error_pages() {
    log_info "安装错误页面..."

    mkdir -p /var/www/error

    # 从 git 仓库拉取错误页面
    if [[ ! -d "/var/www/error/.git" ]]; then
        rm -rf /var/www/error/*
        git clone https://github.com/geekmakersun/error-html.git /tmp/error-html-tmp || {
            log_warn "错误页面仓库拉取失败，使用默认页面"
            # 创建基础错误页面
            for code in 400 401 403 404 500 502 503 504; do
                cat > "/var/www/error/${code}_error.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Error ${code}</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #e74c3c; }
        .code { font-size: 72px; color: #3498db; }
    </style>
</head>
<body>
    <div class="code">${code}</div>
    <h1>Error ${code}</h1>
    <p>An error occurred while processing your request.</p>
    <p><small>Protected by ModSecurity WAF</small></p>
</body>
</html>
EOF
            done
        }
        if [[ -d "/tmp/error-html-tmp" ]]; then
            cp -r /tmp/error-html-tmp/* /var/www/error/
            rm -rf /tmp/error-html-tmp
        fi
    fi

    chown -R www-data:www-data /var/www/error
    chmod -R 644 /var/www/error/*.html 2>/dev/null || true

    log_success "错误页面安装完成"
}

# ========== 创建 Systemd 服务 ==========
create_systemd_service() {
    log_info "配置 Systemd 服务..."

    cat > /etc/systemd/system/nginx.service << 'EOF'
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /var/run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx

    log_success "Systemd 服务配置完成"
}

# ========== 配置日志轮转 ==========
configure_logrotate() {
    log_info "配置日志轮转..."

    cat > /etc/logrotate.d/nginx << 'EOF'
/var/log/nginx/*.log
/var/log/nginx/site/*.log
/var/log/nginx/modsecurity/*.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
    endscript
}
EOF

    log_success "日志轮转配置完成"
}

# ========== 验证安装 ==========
verify_installation() {
    log_info "验证安装..."

    # 检查 Nginx 版本
    local version
    version=$(nginx -v 2>&1)
    log_info "Nginx 版本: $version"

    # 检查是否包含 ModSecurity 模块
    if nginx -V 2>&1 | grep -q "modsecurity"; then
        log_success "ModSecurity 模块已编译进 Nginx"
    else
        log_error "ModSecurity 模块未找到"
        exit 1
    fi

    # 测试配置语法
    if nginx -t 2>&1 | grep -q "successful"; then
        log_success "Nginx 配置语法正确"
    else
        log_error "Nginx 配置语法错误"
        nginx -t
        exit 1
    fi

    # 检查 ModSecurity 库
    if ldconfig -p | grep -q modsecurity; then
        log_success "ModSecurity 库已加载"
    else
        log_warn "ModSecurity 库可能未正确加载"
    fi

    log_success "安装验证完成"
}

# ========== 启动服务 ==========
start_services() {
    log_info "启动 Nginx 服务..."

    # 停止可能存在的旧服务
    systemctl stop nginx 2>/dev/null || true
    pkill nginx 2>/dev/null || true
    sleep 1

    # 启动新服务
    systemctl start nginx

    # 等待服务启动
    sleep 2

    # 检查状态
    if systemctl is-active --quiet nginx; then
        log_success "Nginx 服务启动成功"
    else
        log_error "Nginx 服务启动失败"
        journalctl -u nginx --no-pager -n 50 | tee -a "$LOG_FILE"
        exit 1
    fi
}

# ========== 测试 ModSecurity ==========
test_modsecurity() {
    log_info "测试 ModSecurity..."

    sleep 2

    # 测试正常请求
    log_info "测试正常请求..."
    if curl -s http://localhost/ > /dev/null 2>&1; then
        log_success "正常请求测试通过"
    else
        log_warn "正常请求测试失败"
    fi

    # 测试 XSS 攻击检测
    log_info "测试 XSS 攻击检测..."
    local xss_response
    xss_response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/?test=<script>alert(1)</script>")
    if [[ "$xss_response" == "403" ]]; then
        log_success "XSS 攻击检测正常 (返回 403)"
    else
        log_warn "XSS 攻击检测可能未生效 (返回 $xss_response)"
    fi

    # 测试 SQL 注入检测
    log_info "测试 SQL 注入检测..."
    local sql_response
    sql_response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/?id=1%20OR%201=1")
    if [[ "$sql_response" == "403" ]]; then
        log_success "SQL 注入检测正常 (返回 403)"
    else
        log_warn "SQL 注入检测可能未生效 (返回 $sql_response)"
    fi

    log_success "ModSecurity 测试完成"
}

# ========== 保存安装信息 ==========
save_install_info() {
    log_info "保存安装信息..."

    local NGINX_ACTUAL_VERSION
    NGINX_ACTUAL_VERSION=$(nginx -v 2>&1 | awk '{print $3}' | sed 's/\///')

    local INFO_FILE="/root/.nginx_modsecurity_install_info"
    cat > "${INFO_FILE}" << EOF
# Nginx + ModSecurity 安装信息
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 版本信息
NGINX_VERSION="${NGINX_ACTUAL_VERSION}"
MODSECURITY_VERSION="${MODSECURITY_VERSION}"
MODSECURITY_NGINX_VERSION="${MODSECURITY_NGINX_VERSION}"

# 路径信息
INSTALL_PREFIX="${INSTALL_PREFIX}"
CONFIG_FILE="/etc/nginx/nginx.conf"
MODSECURITY_CONFIG="/etc/nginx/modsecurity/modsec.conf"

# 服务管理
# 启动: systemctl start nginx
# 停止: systemctl stop nginx
# 重启: systemctl restart nginx
# 重载: systemctl reload nginx
# 状态: systemctl status nginx

# 日志目录
LOG_DIR="/var/log/nginx"
MODSECURITY_LOG_DIR="/var/log/nginx/modsecurity"

# 测试命令
# 正常请求: curl http://localhost/
# XSS 测试: curl 'http://localhost/?test=<script>alert(1)</script>'
# SQL 注入测试: curl 'http://localhost/?id=1 OR 1=1'
EOF

    chmod 600 "${INFO_FILE}"
    log_info "安装信息已保存到: ${INFO_FILE}"
}

# ========== 显示安装信息 ==========
show_summary() {
    local NGINX_ACTUAL_VERSION
    NGINX_ACTUAL_VERSION=$(nginx -v 2>&1 | awk '{print $3}' | sed 's/\///')

    echo ""
    echo "========================================"
    echo "    Nginx + ModSecurity 安装完成"
    echo "========================================"
    echo ""
    echo "版本:"
    echo "  Nginx: ${NGINX_ACTUAL_VERSION}"
    echo "  ModSecurity: ${MODSECURITY_VERSION}"
    echo "  ModSecurity-Nginx: ${MODSECURITY_NGINX_VERSION}"
    echo ""
    echo "配置文件:"
    echo "  Nginx: /etc/nginx/nginx.conf"
    echo "  ModSecurity: /etc/nginx/modsecurity/modsec.conf"
    echo "  自定义规则: /etc/nginx/modsecurity/custom.conf"
    echo ""
    echo "默认站点: http://localhost"
    echo ""
    echo "服务管理:"
    echo "  systemctl start|stop|restart|reload|status nginx"
    echo ""
    echo "日志文件:"
    echo "  Nginx: /var/log/nginx/"
    echo "  ModSecurity: /var/log/nginx/modsecurity/"
    echo "  安装日志: ${LOG_FILE}"
    echo ""
    echo "安装信息: /root/.nginx_modsecurity_install_info"
    echo ""
    echo "测试命令:"
    echo "  # 正常请求"
    echo "  curl http://localhost/"
    echo ""
    echo "  # XSS 攻击测试 (应返回 403)"
    echo "  curl 'http://localhost/?test=<script>alert(1)</script>'"
    echo ""
    echo "  # SQL 注入测试 (应返回 403)"
    echo "  curl 'http://localhost/?id=1 OR 1=1'"
    echo "========================================"
}

# ========== 清理函数 ==========
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "安装过程中出现错误，请查看日志: ${LOG_FILE}"
        log_info "你可以从备份恢复配置: ${BACKUP_DIR}"
    fi
}

trap cleanup EXIT

# ========== 主函数 ==========
main() {
    echo "========================================"
    echo "  Nginx ${NGINX_VERSION} + ModSecurity ${MODSECURITY_VERSION}"
    echo "  源码编译安装脚本"
    echo "========================================"
    echo ""

    # 初始化日志
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "# Nginx + ModSecurity 安装日志" > "$LOG_FILE"
    echo "# 开始时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    check_root
    next_step "检查 root 权限"

    check_system
    next_step "检查系统环境"

    install_dependencies
    next_step "安装编译依赖"

    setup_directories
    next_step "创建目录结构"

    download_sources
    next_step "下载源码"

    compile_modsecurity
    next_step "编译安装 ModSecurity"

    compile_nginx
    next_step "编译安装 Nginx"

    download_crs
    next_step "下载 CRS 规则集"

    configure_modsecurity
    next_step "配置 ModSecurity"

    configure_nginx
    next_step "配置 Nginx"

    install_error_pages
    next_step "安装错误页面"

    create_systemd_service
    next_step "创建 Systemd 服务"

    configure_logrotate
    next_step "配置日志轮转"

    verify_installation
    next_step "验证安装"

    start_services
    next_step "启动服务"

    test_modsecurity
    next_step "测试 ModSecurity"

    save_install_info

    show_summary

    log_success "Nginx + ModSecurity 安装全部完成！"
}

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
