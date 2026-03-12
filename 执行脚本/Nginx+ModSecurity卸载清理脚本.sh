#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NGINX_VERSION="${NGINX_VERSION:-1.25.4}"
MODSECURITY_VERSION="${MODSECURITY_VERSION:-3.0.12}"
MODSECURITY_NGINX_VERSION="${MODSECURITY_NGINX_VERSION:-1.0.3}"

INSTALL_PREFIX="${INSTALL_PREFIX:-/etc/nginx}"
SRC_DIR="/usr/local/src"
MODSECURITY_PREFIX="/usr/local/modsecurity"
MODSECURITY_CONFIG="${INSTALL_PREFIX}/modsecurity/modsec.conf"
LOG_DIR="/var/log/nginx"
MODSECURITY_LOG_DIR="/var/log/nginx/modsecurity"
WWW_ROOT="/var/www"
NGINX_SBIN_PATH="/usr/sbin"
NGINX_CACHE_DIR="/var/cache/nginx"
SYSTEMD_UNIT_DIR="/etc/systemd/system"
SERVICE_DIR="/service/nginx"
BACKUP_DIR="/service/nginx/backup"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm() {
    read -p "$1 [y/n]: " choice
    case "$choice" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

stop_nginx() {
    log_info "停止 Nginx 服务..."
    if systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl stop nginx
        log_info "Nginx 已停止"
    fi
    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        systemctl disable nginx
        log_info "Nginx 已禁用开机自启"
    fi
}

remove_nginx_service() {
    log_info "移除 Nginx systemd 服务..."
    if [ -f "${SYSTEMD_UNIT_DIR}/nginx.service" ]; then
        rm -f "${SYSTEMD_UNIT_DIR}/nginx.service"
        systemctl daemon-reload
        log_info "Nginx 服务文件已删除"
    fi
}

remove_nginx_binary() {
    log_info "移除 Nginx 二进制文件..."
    if [ -f "${NGINX_SBIN_PATH}/nginx" ]; then
        rm -f "${NGINX_SBIN_PATH}/nginx"
        log_info "Nginx 二进制文件已删除"
    fi
    if [ -f "${NGINX_SBIN_PATH}/nginx-debug" ]; then
        rm -f "${NGINX_SBIN_PATH}/nginx-debug"
    fi
}

remove_modsecurity() {
    log_info "移除 ModSecurity..."
    if [ -d "${MODSECURITY_PREFIX}" ]; then
        rm -rf "${MODSECURITY_PREFIX}"
        log_info "ModSecurity 安装目录已删除"
    fi

    if [ -d "${SRC_DIR}/modsecurity-v${MODSECURITY_VERSION}" ]; then
        rm -rf "${SRC_DIR}/modsecurity-v${MODSECURITY_VERSION}"
        log_info "ModSecurity 源码已删除"
    fi

    if [ -d "${SRC_DIR}/modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}" ]; then
        rm -rf "${SRC_DIR}/modsecurity-nginx-v${MODSECURITY_NGINX_VERSION}"
        log_info "ModSecurity-Nginx 连接器源码已删除"
    fi

    if [ -d "${SRC_DIR}/nginx-${NGINX_VERSION}" ]; then
        rm -rf "${SRC_DIR}/nginx-${NGINX_VERSION}"
        log_info "Nginx 源码已删除"
    fi
}

remove_nginx_config() {
    log_info "移除 Nginx 配置目录..."
    if [ -d "${INSTALL_PREFIX}" ]; then
        rm -rf "${INSTALL_PREFIX}"
        log_info "Nginx 配置目录已删除"
    fi
}

remove_service_dir() {
    log_info "移除服务目录..."
    if [ -d "${SERVICE_DIR}" ]; then
        rm -rf "${SERVICE_DIR}"
        log_info "服务目录已删除"
    fi

    if [ -d "${BACKUP_DIR}" ]; then
        rm -rf "${BACKUP_DIR}"
        log_info "备份目录已删除"
    fi
}

remove_source_dir() {
    log_info "移除源码目录..."
    if [ -d "${SRC_DIR}" ]; then
        rm -rf "${SRC_DIR}"
        log_info "源码目录已删除"
    fi
}

remove_logs() {
    log_info "移除日志目录..."
    if [ -d "${LOG_DIR}" ]; then
        rm -rf "${LOG_DIR}"/*
        log_info "Nginx 日志已清除"
    fi

    if [ -d "${MODSECURITY_LOG_DIR}" ]; then
        rm -rf "${MODSECURITY_LOG_DIR}"/*
        log_info "ModSecurity 日志已清除"
    fi
}

remove_cache() {
    log_info "移除缓存目录..."
    if [ -d "${NGINX_CACHE_DIR}" ]; then
        rm -rf "${NGINX_CACHE_DIR}"/*
        log_info "Nginx 缓存已清除"
    fi
}

remove_www_data() {
    log_info "检查 www-data 用户/组..."
    if id -u www-data &>/dev/null; then
        if confirm "是否删除 www-data 用户和组"; then
            userdel www-data 2>/dev/null || true
            groupdel www-data 2>/dev/null || true
            log_info "www-data 用户和组已删除"
        fi
    fi
}

remove_dependencies() {
    log_info "检查编译依赖包..."
    if confirm "是否删除编译依赖包 (build-essential, gcc, g++, make 等)"; then
        log_warn "此操作可能影响其他需要编译的工具"
        if confirm "确认删除"; then
            apt-get remove -y --purge \
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
                libyajl-dev \
                libpcre2-dev \
                flex \
                bison 2>/dev/null || true
            apt-get autoremove -y
            log_info "编译依赖已删除"
        fi
    fi
}

remove_web_root() {
    log_info "检查网站根目录..."
    if [ -d "${WWW_ROOT}/html" ]; then
        if confirm "是否删除 ${WWW_ROOT}/html 目录"; then
            rm -rf "${WWW_ROOT}/html"
            log_info "网站根目录已删除"
        fi
    fi
}

verify_removal() {
    log_info "验证清理结果..."
    local errors=0

    if [ -f "${NGINX_SBIN_PATH}/nginx" ]; then
        log_error "Nginx 二进制文件仍然存在"
        ((errors++))
    fi

    if [ -d "${INSTALL_PREFIX}" ]; then
        log_error "Nginx 配置目录仍然存在"
        ((errors++))
    fi

    if [ -d "${MODSECURITY_PREFIX}" ]; then
        log_error "ModSecurity 目录仍然存在"
        ((errors++))
    fi

    if [ -d "${SERVICE_DIR}" ]; then
        log_error "服务目录仍然存在"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        log_info "所有组件已成功卸载"
    else
        log_error "发现 $errors 个问题，请手动检查"
    fi
}

show_menu() {
    echo ""
    echo "=========================================="
    echo "  Nginx + ModSecurity 深度卸载清理脚本"
    echo "=========================================="
    echo ""
    echo "1. 停止 Nginx 服务"
    echo "2. 移除 Nginx systemd 服务"
    echo "3. 移除 Nginx 二进制文件"
    echo "4. 移除 ModSecurity"
    echo "5. 移除 Nginx 配置"
    echo "6. 移除服务目录 (/service/nginx)"
    echo "7. 移除源码目录 (/usr/local/src)"
    echo "8. 移除日志文件"
    echo "9. 移除缓存文件"
    echo "10. 移除 www-data 用户/组"
    echo "11. 移除网站根目录"
    echo "12. 移除编译依赖包"
    echo ""
    echo "a. 执行全部清理"
    echo "v. 验证清理结果"
    echo "q. 退出"
    echo ""
}

main() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi

    log_info "Nginx + ModSecurity 深度卸载清理脚本"
    log_info "版本: Nginx ${NGINX_VERSION}, ModSecurity ${MODSECURITY_VERSION}"
    echo ""

    if ! confirm "确定要执行卸载清理吗？此操作不可恢复"; then
        log_info "已取消"
        exit 0
    fi

    while true; do
        show_menu
        read -p "请选择操作: " choice

        case "$choice" in
            1) stop_nginx ;;
            2) remove_nginx_service ;;
            3) remove_nginx_binary ;;
            4) remove_modsecurity ;;
            5) remove_nginx_config ;;
            6) remove_service_dir ;;
            7) remove_source_dir ;;
            8) remove_logs ;;
            9) remove_cache ;;
            10) remove_www_data ;;
            11) remove_web_root ;;
            12) remove_dependencies ;;
            a|A)
                log_info "开始执行全部清理..."
                stop_nginx
                remove_nginx_service
                remove_nginx_binary
                remove_modsecurity
                remove_nginx_config
                remove_service_dir
                remove_source_dir
                remove_logs
                remove_cache
                remove_www_data
                remove_web_root
                log_info "全部清理完成"
                ;;
            v|V) verify_removal ;;
            q|Q) exit 0 ;;
            *) log_error "无效选择" ;;
        esac
    done
}

main "$@"
