#!/bin/bash
#
# PHP 8.4 FPM 自动化安装脚本
# 用途: 无需交互的自动化编译安装 PHP 8.4 FPM
# 适配: Ubuntu 22.04.5 LTS
#

set -e  # 遇到错误立即退出
set -u  # 使用未定义变量时报错

# ========== 配置变量 ==========
# 可自定义的变量（可通过环境变量覆盖）
# PHP 版本
PHP_VERSION="${PHP_VERSION:-8.4.18}"
# 安装路径
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/php84}"

# 日志文件
LOG_FILE="/var/log/php_install.log"

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    
    # 检查内存
    MEM_MB=$(free -m | awk '/^Mem:/{print int($2)}')
    MEM_GB=$(free -m | awk '/^Mem:/{print int($2/1024)}')
    if [[ $MEM_MB -lt 1024 ]]; then
        log_warn "内存不足 1GB，当前 ${MEM_MB}MB，编译可能失败"
    elif [[ $MEM_GB -lt 2 ]]; then
        log_warn "内存不足 2GB，当前 ${MEM_GB}GB，编译可能失败"
    fi
    
    # 检查磁盘空间
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ -z "$DISK_GB" ]]; then
        log_warn "无法获取磁盘空间信息"
    elif [[ $DISK_GB -lt 20 ]]; then
        log_warn "磁盘空间不足 20GB，当前 ${DISK_GB}GB"
    fi
    
    log_success "系统检查完成"
}

# ========== 安装依赖 ==========
install_dependencies() {
    log_info "安装编译依赖..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    apt-get update -qq
    apt-get upgrade -y -qq
    
    # 基础编译工具
    apt-get install -y -qq build-essential autoconf bison re2c libtool pkg-config
    
    # PHP 核心依赖
    apt-get install -y -qq libxml2-dev libssl-dev libsqlite3-dev zlib1g-dev libcurl4-openssl-dev
    
    # WordPress 必需扩展依赖
    apt-get install -y -qq libpng-dev libjpeg-dev libwebp-dev libfreetype-dev libxpm-dev  # GD
    apt-get install -y -qq libonig-dev           # mbstring
    apt-get install -y -qq libzip-dev            # zip
    apt-get install -y -qq libicu-dev            # intl
    apt-get install -y -qq libpq-dev             # pdo_pgsql (可选)
    apt-get install -y -qq libmysqlclient-dev    # mysqli/pdo_mysql
    
    # ImageMagick 扩展依赖（WordPress 图片处理推荐）
    apt-get install -y -qq libmagickwand-dev imagemagick
    
    # Redis 扩展依赖（WordPress 缓存推荐）
    apt-get install -y -qq libhiredis-dev
    
    # 其他有用扩展依赖
    apt-get install -y -qq libgmp-dev            # gmp
    apt-get install -y -qq libldb-dev libldap2-dev  # ldap
    apt-get install -y -qq libsodium-dev         # sodium
    apt-get install -y -qq libargon2-dev         # password_argon2
    apt-get install -y -qq libreadline-dev       # readline
    apt-get install -y -qq libtidy-dev           # tidy
    apt-get install -y -qq libxslt1-dev          # xsl
    apt-get install -y -qq libbz2-dev            # bz2
    apt-get install -y -qq libenchant-2-dev      # enchant
    apt-get install -y -qq libffi-dev            # ffi
    
    # systemd 集成依赖（PHP-FPM 服务管理）
    apt-get install -y -qq libsystemd-dev
    
    # 处理已知依赖问题
    # 修复 GMP 库路径
    ln -sf /usr/include/x86_64-linux-gnu/gmp.h /usr/include/gmp.h 2>/dev/null || true
    
    # 修复 OpenLDAP 库路径
    ln -sf /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so 2>/dev/null || true
    ln -sf /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so 2>/dev/null || true
    
    log_success "依赖安装完成"
}

# ========== 创建目录结构 ==========
setup_directories() {
    log_info "创建目录结构..."
    
    # 创建源码和编译目录
    mkdir -p /service/php/{src,build}
    
    # 创建 PHP 运行目录
    mkdir -p /usr/local/php84/etc/php-fpm.d
    mkdir -p /usr/local/php84/var/run
    mkdir -p /usr/local/php84/var/log
    mkdir -p /usr/local/php84/tmp
    
    # 创建 PHP-FPM 运行目录（与 Nginx 配合）
    mkdir -p /var/run/php-fpm
    mkdir -p /var/log/php-fpm
    
    # 创建 www-data 用户（如果不存在）
    if ! id -u www-data &>/dev/null; then
        groupadd -r www-data 2>/dev/null || true
        useradd -r -g www-data -s /bin/false -d /var/www -M www-data 2>/dev/null || true
    fi
    
    # 配置目录权限
    chown -R www-data:www-data /usr/local/php84/var
    chown -R www-data:www-data /var/run/php-fpm
    chown -R www-data:www-data /var/log/php-fpm
    chmod -R 755 /service/php
    chmod -R 755 /usr/local/php84
    chmod 1777 /usr/local/php84/tmp
    
    # 配置 tmpfiles.d 确保重启后目录自动创建
    tee /etc/tmpfiles.d/php-fpm.conf > /dev/null << 'EOF'
d /var/run/php-fpm 0755 www-data www-data -
d /var/log/php-fpm 0755 www-data www-data -
EOF
    
    log_success "目录结构创建完成"
}

# ========== 下载 PHP 源码 ==========
download_source() {
    log_info "下载 PHP ${PHP_VERSION} 源码..."
    
    cd /service/php/src
    
    local download_url="https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz"
    log_info "从官方源下载..."
    
    wget -c "${download_url}"
    
    if [ $? -ne 0 ]; then
        log_error "下载失败"
        exit 1
    fi
    
    tar -zxvf php-${PHP_VERSION}.tar.gz
    
    log_success "PHP 源码下载完成"
}

# ========== 编译安装 PHP ==========
compile_install() {
    log_info "编译安装 PHP ${PHP_VERSION}..."
    
    cd /service/php/src/php-${PHP_VERSION}
    
    # 配置编译参数
    ./configure \
    --prefix=/usr/local/php84 \
    --exec-prefix=/usr/local/php84 \
    --bindir=/usr/local/php84/bin \
    --sbindir=/usr/local/php84/sbin \
    --includedir=/usr/local/php84/include \
    --libdir=/usr/local/php84/lib/php \
    --mandir=/usr/local/php84/php/man \
    --with-config-file-path=/usr/local/php84/etc \
    --with-config-file-scan-dir=/usr/local/php84/etc/php.d \
    --enable-fpm \
    --with-fpm-user=www-data \
    --with-fpm-group=www-data \
    --with-fpm-systemd \
    --with-fpm-acl \
    --enable-mysqlnd \
    --with-mysqli=mysqlnd \
    --with-pdo-mysql=mysqlnd \
    --enable-bcmath \
    --with-curl \
    --with-openssl \
    --with-zlib \
    --with-zip \
    --enable-gd \
    --with-webp \
    --with-jpeg \
    --with-freetype \
    --with-xpm \
    --enable-gd-jis-conv \
    --enable-intl \
    --enable-mbstring \
    --enable-pcntl \
    --enable-shmop \
    --enable-soap \
    --enable-sockets \
    --enable-sysvmsg \
    --enable-sysvsem \
    --enable-sysvshm \
    --with-bz2 \
    --enable-calendar \
    --enable-dba \
    --enable-exif \
    --enable-ftp \
    --with-gettext \
    --with-gmp \
    --with-mhash \
    --enable-opcache \
    --with-password-argon2 \
    --with-sodium \
    --enable-mysqlnd-compression-support \
    --with-pear \
    --enable-xml \
    --with-xsl \
    --enable-simplexml \
    --enable-dom \
    --enable-xmlreader \
    --enable-xmlwriter \
    --with-tidy \
    --with-readline \
    --enable-phpdbg \
    --enable-filter \
    --enable-hash \
    --enable-json \
    --enable-libxml \
    --enable-session \
    --enable-tokenizer \
    --with-libxml \
    --with-sqlite3 \
    --with-pdo-sqlite \
    --enable-fileinfo \
    --with-ffi
    
    # 多核编译
    make -j$(nproc)
    
    # 安装 PHP
    make install
    
    # 配置系统环境
    # 创建软链接，使 PHP 命令全局可用
    ln -sf /usr/local/php84/bin/php /usr/local/bin/php 2>/dev/null || true
    ln -sf /usr/local/php84/bin/phpize /usr/local/bin/phpize 2>/dev/null || true
    ln -sf /usr/local/php84/bin/php-config /usr/local/bin/php-config 2>/dev/null || true
    ln -sf /usr/local/php84/sbin/php-fpm /usr/local/sbin/php-fpm 2>/dev/null || true
    
    # 配置系统库路径
    tee /etc/ld.so.conf.d/php84.conf <<EOF
/usr/local/php84/lib/php
EOF
    ldconfig
    
    # 验证安装
    if php -v 2>&1 | grep -q "PHP ${PHP_VERSION}"; then
        log_success "PHP 安装成功"
    else
        log_error "PHP 安装失败"
        exit 1
    fi
    
    log_success "PHP 编译安装完成"
}

# ========== 复制配置文件 ==========
copy_config_files() {
    log_info "复制配置文件..."
    
    # 创建 php.d 扫描目录
    mkdir -p /usr/local/php84/etc/php.d
    
    # 复制 php.ini 配置文件
    cp /service/php/src/php-${PHP_VERSION}/php.ini-production /usr/local/php84/etc/php.ini
    
    # 复制 php-fpm 配置文件
    cp /usr/local/php84/etc/php-fpm.conf.default /usr/local/php84/etc/php-fpm.conf
    cp /usr/local/php84/etc/php-fpm.d/www.conf.default /usr/local/php84/etc/php-fpm.d/www.conf
    
    # 配置文件权限
    chown -R www-data:www-data /usr/local/php84/etc
    chmod 644 /usr/local/php84/etc/php.ini
    chmod 644 /usr/local/php84/etc/php-fpm.conf
    chmod 644 /usr/local/php84/etc/php-fpm.d/www.conf
    
    log_success "配置文件复制完成"
}

# ========== 安装 PECL 扩展 ==========
install_pecl_extensions() {
    log_info "安装 PECL 扩展..."

    # 检查并安装 ImageMagick 扩展
    if ! php -m | grep -q "imagick"; then
        log_info "安装 imagick 扩展..."
        /usr/local/php84/bin/pecl install imagick || true
    else
        log_info "imagick 扩展已安装，跳过"
    fi

    # 检查并安装 Redis 扩展
    if ! php -m | grep -q "redis"; then
        log_info "安装 redis 扩展..."
        printf "no\nno\nno\nno\nno\n" | /usr/local/php84/bin/pecl install redis || true
    else
        log_info "redis 扩展已安装，跳过"
    fi

    # 创建扩展配置文件（确保文件存在）
    tee /usr/local/php84/etc/php.d/imagick.ini <<EOF
extension=imagick.so
EOF

    tee /usr/local/php84/etc/php.d/redis.ini <<EOF
extension=redis.so
EOF

    # 验证扩展安装
    if php -m | grep -E "imagick|redis"; then
        log_success "PECL 扩展安装成功"
    else
        log_warn "PECL 扩展安装可能失败"
    fi

    log_success "PECL 扩展安装完成"
}

# ========== 配置 PHP-FPM ==========
configure_php_fpm() {
    log_info "配置 PHP-FPM..."
    
    # 配置 php.ini
    tee /usr/local/php84/etc/php.ini << 'EOF'
[PHP]
; ========== 基础配置 ==========
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = -1

; ========== 文件上传配置（WordPress 优化） ==========
file_uploads = On
upload_max_filesize = 64M
post_max_size = 128M
max_file_uploads = 20

; ========== 内存与执行时间配置 ==========
memory_limit = 256M
max_execution_time = 300
max_input_time = 300
max_input_vars = 3000

; ========== 错误处理 ==========
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 4096
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On

; ========== 错误日志路径 ==========
error_log = /var/log/php-fpm/php-error.log

; ========== 临时目录 ==========
sys_temp_dir = /usr/local/php84/tmp
upload_tmp_dir = /usr/local/php84/tmp

; ========== 安全配置 ==========
expose_php = Off
allow_url_fopen = On
allow_url_include = Off

; ========== 时区配置 ==========
date.timezone = Asia/Shanghai

; ========== Session 配置 ==========
session.save_handler = files
session.save_path = /usr/local/php84/tmp
session.use_strict_mode = 1
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.cookie_httponly = 1
session.cookie_secure = 0
session.cookie_samesite = Strict
session.gc_maxlifetime = 1440

; ========== OPcache 配置（性能优化） ==========
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.max_wasted_percentage = 10
opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
opcache.save_comments = 1
opcache.enable_file_override = 1

; ========== 字符集配置 ==========
default_charset = "UTF-8"

[CLI Server]
cli_server.color = On

[Date]
date.timezone = Asia/Shanghai

[Pdo_mysql]
pdo_mysql.default_socket = /var/run/mysqld/mysqld.sock

[mail function]
SMTP = localhost
smtp_port = 25
mail.add_x_header = Off

[ODBC]
odbc.allow_persistent = On
odbc.check_persistent = On
odbc.max_persistent = -1
odbc.max_links = -1
odbc.defaultlrl = 4096
odbc.defaultbinmode = 1

[MySQLi]
mysqli.max_persistent = -1
mysqli.allow_persistent = On
mysqli.max_links = -1
mysqli.default_port = 3306
mysqli.default_socket = /var/run/mysqld/mysqld.sock
mysqli.default_host =
mysqli.default_user =
mysqli.default_pw =
mysqli.reconnect = Off

[mysqlnd]
mysqlnd.collect_statistics = On
mysqlnd.collect_memory_statistics = Off

[PostgreSQL]
pgsql.allow_persistent = On
pgsql.auto_reset_persistent = Off
pgsql.max_persistent = -1
pgsql.max_links = -1
pgsql.ignore_notice = 0
pgsql.log_notice = 0

[bcmath]
bcmath.scale = 0

[Session]
session.save_handler = files
session.save_path = /usr/local/php84/tmp
session.use_strict_mode = 1

[ldap]
ldap.max_links = -1

[opcache]
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
EOF
    
    # 配置 php-fpm.conf
    tee /usr/local/php84/etc/php-fpm.conf << 'EOF'
;;;;;;;;;;;;;;;;;;;;;
; FPM Configuration ;
;;;;;;;;;;;;;;;;;;;;;

[global]
; PID 文件路径
pid = /usr/local/php84/var/run/php-fpm.pid

; 错误日志路径
error_log = /var/log/php-fpm/php-fpm-error.log

; 日志级别: alert, error, warning, notice, debug
log_level = notice

; 日志格式
log_limit = 4096

; 紧急重启阈值
emergency_restart_threshold = 10
emergency_restart_interval = 1m

; 进程控制超时
process_control_timeout = 10s

; 守护进程模式
daemonize = yes

; 加载池配置
include = /usr/local/php84/etc/php-fpm.d/*.conf
EOF
    
    # 配置 www.conf（PHP-FPM 池）
    tee /usr/local/php84/etc/php-fpm.d/www.conf << 'EOF'
; ========== WordPress 专用 PHP-FPM 池配置 ==========

[www]
; 池名称
prefix = /usr/local/php84/var

; 运行用户和组
user = www-data
group = www-data

; 监听方式：Unix Socket（推荐，性能更好）
listen = /var/run/php-fpm/php84-fpm.sock

; Socket 权限
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

; 允许监听的客户端（仅本地）
listen.allowed_clients = 127.0.0.1

; ========== 进程管理配置 ==========
; 进程管理方式: static, dynamic, ondemand
pm = dynamic

; 最大子进程数（根据服务器内存调整，约 1 个进程 50-80MB 内存）
pm.max_children = 30

; 空闲时最小进程数
pm.min_spare_servers = 5

; 空闲时最大进程数
pm.max_spare_servers = 15

; 启动时创建的进程数
pm.start_servers = 8

; 每个进程最大处理请求数（防止内存泄漏）
pm.max_requests = 1000

; 慢请求日志（性能排查用）
slowlog = /var/log/php-fpm/www-slow.log
request_slowlog_timeout = 10s
request_slowlog_trace_depth = 20

; ========== 状态监控 ==========
; 启用状态页面（配合 Nginx 访问控制）
pm.status_path = /php-fpm-status

; 启用 ping 页面
ping.path = /php-fpm-ping
ping.response = pong

; ========== 环境变量 ==========
clear_env = no

; ========== PHP 配置覆盖 ==========
php_admin_value[error_log] = /var/log/php-fpm/www-error.log
php_admin_flag[log_errors] = on

; ========== 安全配置 ==========
; 捕获工作进程输出
catch_workers_output = yes
decorate_workers_output = no

; 禁用的 PHP 函数（安全加固）
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,symlink,dl

; 可根据 WordPress 实际需求调整禁用列表，部分插件可能需要 exec 权限
EOF
    
    # 配置目录权限
    chown -R www-data:www-data /usr/local/php84/etc
    chown -R www-data:www-data /usr/local/php84/var
    chown -R www-data:www-data /var/run/php-fpm
    chown -R www-data:www-data /var/log/php-fpm
    chmod 1777 /usr/local/php84/tmp
    
    log_success "PHP-FPM 配置完成"
}

# ========== 配置 Systemd 服务 ==========
create_systemd_service() {
    log_info "创建 Systemd 服务..."
    
    tee /etc/systemd/system/php84-fpm.service << 'EOF'
[Unit]
Description=PHP 8.4 FastCGI 进程管理器
Documentation=https://www.php.net/manual/en/install.fpm.php
After=network.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=notify
PIDFile=/usr/local/php84/var/run/php-fpm.pid
ExecStart=/usr/local/php84/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php84/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 $MAINPID
ExecStop=/bin/kill -SIGQUIT $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd 配置
    systemctl daemon-reload
    
    # 启用开机自启
    systemctl enable php84-fpm
    
    # 启动 PHP-FPM
    systemctl start php84-fpm
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet php84-fpm; then
        log_success "PHP-FPM 服务启动成功"
    else
        log_error "PHP-FPM 服务启动失败"
        journalctl -u php84-fpm --no-pager -n 50 | tee -a "$LOG_FILE"
        exit 1
    fi
    
    log_success "Systemd 服务配置完成"
}

# ========== 启用 Nginx PHP 支持 ==========
enable_nginx_php() {
    log_info "启用 Nginx PHP 支持..."
    
    # 检查 Nginx 是否安装
    if ! command -v nginx &> /dev/null; then
        log_warn "未检测到 Nginx，跳过 PHP 配置"
        return 0
    fi
    
    # 检查 Nginx 配置文件
    local nginx_common_conf="/etc/nginx/snippets/common.conf"
    if [ ! -f "$nginx_common_conf" ]; then
        log_warn "未找到 Nginx 共用配置文件 $nginx_common_conf"
        return 0
    fi
    
    # 创建 fastcgi-php.conf 配置文件（如果不存在）
    local fastcgi_php_conf="/etc/nginx/snippets/fastcgi-php.conf"
    if [ ! -f "$fastcgi_php_conf" ]; then
        log_info "创建 fastcgi-php.conf 配置文件..."
        cat > "$fastcgi_php_conf" << 'EOF'
# regex to split $uri to $fastcgi_script_name and $fastcgi_path
fastcgi_split_path_info ^(.+?\.php)(/.*)$;

# Check that the PHP script exists before passing it
try_files $fastcgi_script_name =404;

# Bypass the fact that try_files resets $fastcgi_path_info
# see: http://trac.nginx.org/nginx/ticket/321
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;

fastcgi_index index.php;

include fastcgi_params;

fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
fastcgi_param PHP_VALUE "open_basedir=$document_root/:/tmp/";
EOF
    fi
    
    # 备份原配置文件
    cp "$nginx_common_conf" "${nginx_common_conf}.bak"
    
    # 启用 PHP 处理配置 - 使用更可靠的方法
    # 替换整个 PHP 配置块而不是逐行取消注释
    sed -i '/# ---------- PHP 处理配置/,/# }/c\
# ---------- PHP 处理配置（需要安装 PHP-FPM 后启用） ----------\
location ~ \.php$ {\
    include snippets/fastcgi-php.conf;\
    fastcgi_pass unix:/var/run/php-fpm/php84-fpm.sock;\
    fastcgi_connect_timeout 300s;\
    fastcgi_send_timeout 300s;\
    fastcgi_read_timeout 300s;\
}' "$nginx_common_conf"
    
    # 测试 Nginx 配置
    if nginx -t 2>&1 | grep -q "successful"; then
        # 重启 Nginx
        systemctl reload nginx
        log_success "Nginx PHP 支持已启用"
    else
        log_warn "Nginx 配置测试失败，已恢复备份"
        cp "${nginx_common_conf}.bak" "$nginx_common_conf"
        return 1
    fi
}

# ========== 写入探针文件 ==========
create_probe_file() {
    log_info "创建 PHP 探针文件..."
    
    # 创建网站根目录
    mkdir -p /var/www/html
    
    # 设置目录权限
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html
    
    # 创建 PHP 探针文件
    tee /var/www/html/probe.php << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP 8.4 环境探针</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; color: white; margin-bottom: 30px; }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.2); }
        .header p { opacity: 0.9; font-size: 1.1em; }
        .card {
            background: white; border-radius: 12px; padding: 25px;
            margin-bottom: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }
        .card h2 {
            color: #333; margin-bottom: 20px; padding-bottom: 10px;
            border-bottom: 2px solid #667eea; display: flex; align-items: center; gap: 10px;
        }
        .card h2::before { content: ''; width: 4px; height: 24px; background: #667eea; border-radius: 2px; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 15px; }
        .info-item {
            display: flex; justify-content: space-between; padding: 12px 15px;
            background: #f8f9fa; border-radius: 8px; border-left: 3px solid #667eea;
        }
        .info-item label { color: #666; font-weight: 500; }
        .info-item value { color: #333; font-weight: 600; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; }
        .status-item {
            display: flex; align-items: center; gap: 8px; padding: 10px 15px;
            border-radius: 8px; font-size: 0.95em;
        }
        .status-item.installed { background: #d4edda; color: #155724; }
        .status-item.missing { background: #f8d7da; color: #721c24; }
        .status-icon {
            width: 20px; height: 20px; border-radius: 50%; display: flex;
            align-items: center; justify-content: center; font-weight: bold; font-size: 12px;
        }
        .status-item.installed .status-icon { background: #28a745; color: white; }
        .status-item.missing .status-icon { background: #dc3545; color: white; }
        .section-title {
            color: #555; font-size: 1.1em; margin: 20px 0 15px 0;
            padding-left: 10px; border-left: 3px solid #764ba2;
        }
        .footer { text-align: center; color: white; opacity: 0.8; margin-top: 30px; font-size: 0.9em; }
        @media (max-width: 768px) {
            .header h1 { font-size: 1.8em; }
            .card { padding: 20px; }
            .info-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 PHP 8.4 环境探针</h1>
            <p>WordPress 运行环境检测与性能分析</p>
        </div>
        <div class="card">
            <h2>服务器基本信息</h2>
            <div class="info-grid">
                <div class="info-item"><label>服务器系统</label><value><?php echo php_uname('s') . ' ' . php_uname('r'); ?></value></div>
                <div class="info-item"><label>服务器软件</label><value><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></value></div>
                <div class="info-item"><label>PHP 版本</label><value><?php echo PHP_VERSION; ?></value></div>
                <div class="info-item"><label>PHP 运行方式</label><value><?php echo php_sapi_name(); ?></value></div>
                <div class="info-item"><label>当前时间</label><value><?php echo date('Y-m-d H:i:s'); ?></value></div>
            </div>
        </div>
        <div class="card">
            <h2>PHP 核心配置</h2>
            <div class="info-grid">
                <div class="info-item"><label>内存限制</label><value><?php echo ini_get('memory_limit'); ?></value></div>
                <div class="info-item"><label>上传限制</label><value><?php echo ini_get('upload_max_filesize'); ?></value></div>
                <div class="info-item"><label>POST 限制</label><value><?php echo ini_get('post_max_size'); ?></value></div>
                <div class="info-item"><label>最大执行时间</label><value><?php echo ini_get('max_execution_time'); ?> 秒</value></div>
                <div class="info-item"><label>时区设置</label><value><?php echo ini_get('date.timezone') ?: '未设置'; ?></value></div>
            </div>
        </div>
        <div class="card">
            <h2>WordPress 必需扩展</h2>
            <?php $required = ['curl'=>'HTTP请求','dom'=>'XML处理','exif'=>'图片元数据','fileinfo'=>'文件类型检测','gd'=>'图像处理','iconv'=>'字符编码','intl'=>'国际化','json'=>'JSON处理','mbstring'=>'多字节字符串','mysqli'=>'MySQL连接','openssl'=>'SSL加密','pcre'=>'正则表达式','pdo_mysql'=>'PDO MySQL','xml'=>'XML解析','zip'=>'压缩文件','zlib'=>'数据压缩']; ?>
            <div class="status-grid">
                <?php foreach ($required as $ext => $desc): ?>
                <div class="status-item <?php echo extension_loaded($ext) ? 'installed' : 'missing'; ?>">
                    <span class="status-icon"><?php echo extension_loaded($ext) ? '✓' : '✗'; ?></span>
                    <span><?php echo $ext; ?> <small>(<?php echo $desc; ?>)</small></span>
                </div>
                <?php endforeach; ?>
            </div>
        </div>
        <div class="footer"><p>PHP 8.4 FPM 编译安装部署指南 | 探针页面</p></div>
    </div>
</body>
</html>
EOF
    
    chown www-data:www-data /var/www/html/probe.php
    chmod 644 /var/www/html/probe.php
    
    log_success "PHP 探针文件创建完成"
}

# ========== 安装 WP-CLI ==========
install_wp_cli() {
    log_info "安装 WP-CLI..."
    
    # 下载 WP-CLI
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    
    # 验证是否正常工作
    php wp-cli.phar --info
    
    # 添加执行权限
    chmod +x wp-cli.phar
    
    # 移动到全局路径
    mv wp-cli.phar /usr/local/bin/wp
    
    # 验证安装
    if wp --info 2>&1 | grep -q "WP-CLI"; then
        log_success "WP-CLI 安装成功"
    else
        log_warn "WP-CLI 安装可能失败"
    fi
    
    # 配置 WP-CLI Tab 补全
    wget -O /etc/bash_completion.d/wp-cli https://raw.githubusercontent.com/wp-cli/wp-cli/master/utils/wp-completion.bash 2>/dev/null || true
    
    log_success "WP-CLI 安装完成"
}

# ========== 验证安装 ==========
verify_installation() {
    log_info "验证安装..."
    
    # 查看 PHP 版本
    VERSION=$(php -v 2>&1)
    log_info "PHP 版本: $VERSION"
    
    # 查看已安装扩展
    log_info "已安装扩展:"
    php -m | grep -E "curl|dom|exif|fileinfo|gd|iconv|intl|json|mbstring|mysqli|openssl|pdo_mysql|xml|zip|imagick|redis"
    
    # 查看 PHP 配置信息
    log_info "PHP 配置信息:"
    php -i | head -50
    
    # 验证 PHP-FPM 运行状态
    if systemctl is-active --quiet php84-fpm; then
        log_success "PHP-FPM 服务运行正常"
    else
        log_error "PHP-FPM 服务运行异常"
        exit 1
    fi
    
    # 查看 PHP-FPM 进程
    ps aux | grep php-fpm | grep -v grep
    
    # 查看监听 Socket
    ls -la /var/run/php-fpm/
    
    log_success "安装验证完成"
}

# ========== 保存安装信息 ==========
save_install_info() {
    log_info "保存安装信息..."
    
    INFO_FILE="/root/.php_install_info"
    cat > ${INFO_FILE} << EOF
# PHP 安装信息
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 版本信息
PHP_VERSION="${PHP_VERSION}"

# 路径信息
INSTALL_PREFIX="${INSTALL_PREFIX}"
CONFIG_FILE="/usr/local/php84/etc/php.ini"
FPM_CONFIG_FILE="/usr/local/php84/etc/php-fpm.conf"

# 服务管理
# 启动: systemctl start php84-fpm
# 停止: systemctl stop php84-fpm
# 重启: systemctl restart php84-fpm
# 状态: systemctl status php84-fpm

# 日志目录
LOG_DIR="/var/log/php-fpm"
EOF

    chmod 600 ${INFO_FILE}
    log_info "安装信息已保存到: ${INFO_FILE}"
}

# ========== 显示安装信息 ==========
show_summary() {
    echo ""
    echo "========================================"
    echo "    PHP 8.4 FPM 安装完成"
    echo "========================================"
    echo ""
    echo "版本: ${PHP_VERSION}"
    echo "安装路径: ${INSTALL_PREFIX}"
    echo "配置文件: /usr/local/php84/etc/php.ini"
    echo "PHP-FPM 配置: /usr/local/php84/etc/php-fpm.conf"
    echo ""
    echo "服务管理:"
    echo "  systemctl start|stop|restart|status php84-fpm"
    echo ""
    echo "PHP 探针: http://localhost/probe.php"
    echo "安装信息: /root/.php_install_info"
    echo "日志文件: ${LOG_FILE}"
    echo "========================================"
}

# ========== 清理函数 ==========
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "安装过程中出现错误，请查看日志: ${LOG_FILE}"
    fi
}

trap cleanup EXIT

# ========== 主函数 ==========
main() {
    echo "========================================"
    echo "  PHP ${PHP_VERSION} FPM 自动化安装脚本"
    echo "========================================"
    echo ""
    
    check_root
    check_system
    
    install_dependencies
    setup_directories
    download_source
    compile_install
    copy_config_files
    install_pecl_extensions
    configure_php_fpm
    create_systemd_service
    create_probe_file
    install_wp_cli
    verify_installation
    save_install_info
    
    show_summary
    
    log_success "PHP 8.4 FPM 安装全部完成！"
    log_info "提示: 运行 '4. Nginx站点管理工具.sh' 创建 PHP 站点"
}

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi