#!/bin/bash

# Gitea 彻底卸载清理脚本
# 谨慎使用：此操作将删除所有 Gitea 相关数据和配置
# 适配环境: Ubuntu 22.04.5 LTS
# 版本: 2.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 打印标题
print_header() {
    echo ""
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}  Gitea 彻底卸载清理脚本${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo ""
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户执行此脚本"
        exit 1
    fi
}

# 确认操作
confirm_operation() {
    echo -e "${RED}警告：此操作将彻底删除以下内容:${NC}"
    echo ""
    echo "  1. Gitea 服务及 systemd 配置"
    echo "  2. Gitea 安装目录 (/service/gitea)"
    echo "  3. Gitea 工作目录 (/var/lib/gitea)"
    echo "  4. Gitea 配置目录 (/etc/gitea)"
    echo "  5. Git 用户及 home 目录 (/home/git)"
    echo "  6. Nginx 站点配置"
    echo "  7. SSL 证书 (如使用 Let's Encrypt)"
    echo "  8. Webroot 验证目录 (/var/www/git.*)"
    echo "  9. 数据库 (如使用 MySQL/MariaDB 且选择删除)"
    echo " 10. 续期钩子脚本"
    echo ""
    echo -e "${RED}所有数据将被永久删除，无法恢复！${NC}"
    echo ""

    read -p "确认继续卸载? (输入 'YES' 继续): " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "操作已取消"
        exit 0
    fi
}

# 停止并禁用 Gitea 服务
stop_gitea_service() {
    log_info "停止 Gitea 服务..."

    if systemctl is-active --quiet gitea 2>/dev/null; then
        systemctl stop gitea
        log_info "Gitea 服务已停止"
    else
        log_info "Gitea 服务未运行"
    fi

    if systemctl is-enabled --quiet gitea 2>/dev/null; then
        systemctl disable gitea
        log_info "Gitea 服务已禁用"
    fi
}

# 删除 systemd 服务文件
remove_systemd_service() {
    log_info "删除 systemd 服务文件..."

    if [ -f /etc/systemd/system/gitea.service ]; then
        rm -f /etc/systemd/system/gitea.service
        log_info "systemd 服务文件已删除"
    fi

    systemctl daemon-reload
    log_info "systemd 已重载"
}

# 删除 Gitea 安装目录
remove_gitea_installation() {
    log_info "删除 Gitea 安装目录..."

    if [ -d /service/gitea ]; then
        rm -rf /service/gitea
        log_info "安装目录 /service/gitea 已删除"
    fi
}

# 删除 Gitea 工作目录
remove_gitea_workdir() {
    log_info "删除 Gitea 工作目录..."

    if [ -d /var/lib/gitea ]; then
        rm -rf /var/lib/gitea
        log_info "工作目录 /var/lib/gitea 已删除"
    fi
}

# 删除 Gitea 配置目录
remove_gitea_config() {
    log_info "删除 Gitea 配置目录..."

    if [ -d /etc/gitea ]; then
        rm -rf /etc/gitea
        log_info "配置目录 /etc/gitea 已删除"
    fi
}

# 删除 Git 用户
remove_git_user() {
    log_info "删除 Git 用户..."

    if id "git" &>/dev/null; then
        userdel -r git 2>/dev/null || userdel git 2>/dev/null || true
        log_info "Git 用户已删除"
    else
        log_info "Git 用户不存在"
    fi
}

# 删除 Nginx 站点配置
remove_nginx_config() {
    log_info "删除 Nginx 站点配置..."

    if [ -d /etc/nginx/sites-enabled ]; then
        for conf in /etc/nginx/sites-enabled/git.*.conf; do
            if [ -L "$conf" ]; then
                rm -f "$conf"
                log_info "已删除软链接: $conf"
            fi
        done
    fi

    if [ -d /etc/nginx/sites-available ]; then
        for conf in /etc/nginx/sites-available/git.*.conf; do
            if [ -f "$conf" ]; then
                rm -f "$conf"
                log_info "已删除配置文件: $conf"
            fi
        done
    fi

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log_info "Nginx 配置已重载"
    else
        log_warn "Nginx 配置测试失败，跳过重载"
    fi
}

# 删除 SSL 证书
remove_ssl_certificates() {
    log_info "检查并删除 SSL 证书..."

    if [ -d /etc/letsencrypt/live ]; then
        local cert_found=false
        for cert_dir in /etc/letsencrypt/live/git.*; do
            if [ -d "$cert_dir" ]; then
                cert_found=true
                domain=$(basename "$cert_dir")
                log_info "发现证书: $domain"

                read -p "删除证书 $domain? (y/n): " confirm
                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                    rm -rf "$cert_dir"
                    rm -rf "/etc/letsencrypt/archive/$domain" 2>/dev/null
                    rm -f "/etc/letsencrypt/renewal/${domain}.conf" 2>/dev/null
                    rm -f "/etc/letsencrypt/renewal/${domain}-*.conf" 2>/dev/null
                    log_info "证书 $domain 已删除"
                fi
            fi
        done
        if [ "$cert_found" = false ]; then
            log_info "未发现 Gitea 相关证书"
        fi
    else
        log_info "Let's Encrypt 目录不存在"
    fi
}

# 删除 Webroot 验证目录
remove_webroot_dirs() {
    log_info "删除 Webroot 验证目录..."

    if [ -d /var/www ]; then
        local dir_found=false
        for webroot_dir in /var/www/git.*; do
            if [ -d "$webroot_dir" ]; then
                dir_found=true
                log_info "发现 Webroot 目录: $webroot_dir"
                rm -rf "$webroot_dir"
                log_info "已删除 Webroot 目录: $webroot_dir"
            fi
        done
        if [ "$dir_found" = false ]; then
            log_info "未发现 Gitea 相关 Webroot 目录"
        fi
    else
        log_info "/var/www 目录不存在"
    fi
}

# 删除续期钩子脚本
remove_renewal_hooks() {
    log_info "删除续期钩子脚本..."

    if [ -f /etc/letsencrypt/renewal-hooks/deploy/gitea-restart.sh ]; then
        rm -f /etc/letsencrypt/renewal-hooks/deploy/gitea-restart.sh
        log_info "续期钩子脚本已删除"
    else
        log_info "续期钩子脚本不存在"
    fi

    # 删除续期日志
    if [ -f /var/log/gitea-cert-renewal.log ]; then
        rm -f /var/log/gitea-cert-renewal.log
        log_info "续期日志已删除"
    fi
}

# 删除数据库
remove_database() {
    log_info "数据库处理..."

    echo ""
    echo "请选择数据库处理方式:"
    echo "  1. 保留数据库（推荐）"
    echo "  2. 删除 MySQL/MariaDB gitea 用户和数据库"
    echo ""

    read -p "请选择 (1-2): " db_choice

    case $db_choice in
        1)
            log_info "保留数据库"
            ;;
        2)
            log_info "删除 MySQL/MariaDB gitea 数据库和用户..."
            if command -v mysql &>/dev/null; then
                mysql -u root -e "DROP DATABASE IF EXISTS gitea;" 2>/dev/null || true
                mysql -u root -e "DROP USER IF EXISTS 'gitea'@'localhost';" 2>/dev/null || true
                mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
                log_info "数据库已删除"
            else
                log_warn "MySQL/MariaDB 未安装"
            fi
            ;;
        *)
            log_info "保留数据库"
            ;;
    esac
}

# 删除日志文件
remove_log_files() {
    log_info "删除日志文件..."

    if [ -d /var/log/nginx/site ]; then
        rm -f /var/log/nginx/site/git.*.log 2>/dev/null
        log_info "Nginx 日志已删除"
    fi
}

# 清理完成
show_cleanup_summary() {
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}  Gitea 卸载清理完成！${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    log_info "以下内容已清理:"
    echo "  - Gitea 服务及配置"
    echo "  - Gitea 安装目录"
    echo "  - Gitea 工作目录"
    echo "  - Gitea 配置目录"
    echo "  - Git 用户及主目录"
    echo "  - Nginx 站点配置"
    echo "  - SSL 证书（已确认的）"
    echo "  - Webroot 验证目录"
    echo "  - 续期钩子脚本"
    echo "  - 日志文件"
    echo ""
    log_info "如需重新部署，请运行: /root/服务脚本库/部署脚本/2..Gitea部署脚本.sh"
    echo ""
}

# 主函数
main() {
    print_header
    check_root
    confirm_operation

    echo ""
    log_info "开始卸载清理..."
    echo ""

    stop_gitea_service
    remove_systemd_service
    remove_gitea_installation
    remove_gitea_workdir
    remove_gitea_config
    remove_git_user
    remove_nginx_config
    remove_ssl_certificates
    remove_webroot_dirs
    remove_renewal_hooks
    remove_database
    remove_log_files

    show_cleanup_summary
}

main "$@"
