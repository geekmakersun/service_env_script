#!/bin/bash

# ===========================================
# Gitea ModSecurity 规则调整脚本
# 用途: 为 Gitea 应用添加 ModSecurity 例外规则
# 适配: Ubuntu 22.04.5 LTS
# ===========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# 检查 ModSecurity 是否安装
check_modsecurity() {
    print_info "检查 ModSecurity 配置..."
    
    if [[ ! -d "/etc/nginx/modsecurity" ]]; then
        print_error "ModSecurity 未安装或配置目录不存在"
        print_info "请先运行 Nginx+ModSecurity 安装脚本"
        exit 1
    fi
    
    if [[ ! -f "/etc/nginx/modsecurity/modsec.conf" ]]; then
        print_error "ModSecurity 主配置文件不存在"
        exit 1
    fi
    
    print_success "ModSecurity 配置检查完成"
}

# 创建 Gitea 例外规则
create_gitea_exceptions() {
    print_header "创建 Gitea ModSecurity 例外规则"
    
    # 创建自定义规则目录
    mkdir -p /etc/nginx/modsecurity/custom-rules
    
    # 创建 Gitea 例外规则文件
    local rules_file="/etc/nginx/modsecurity/custom-rules/gitea-exceptions.conf"
    
    cat > "$rules_file" << 'EOF'
# Gitea ModSecurity 例外规则
# 为 Gitea 应用添加必要的安全例外

# 仓库迁移功能
SecRule REQUEST_URI "@contains /repo/migrate" "id:1000001,phase:1,allow,log,msg:'Gitea migration exception'"

# API 接口
SecRule REQUEST_URI "@contains /api" "id:1000002,phase:1,allow,log,msg:'Gitea API exception'"

# 仓库操作
SecRule REQUEST_URI "@contains /repo/" "id:1000003,phase:1,allow,log,msg:'Gitea repo operations exception'"

# 推送操作
SecRule REQUEST_URI "@contains /git/" "id:1000004,phase:1,allow,log,msg:'Gitea git operations exception'"

# WebHook 操作
SecRule REQUEST_URI "@contains /hook/" "id:1000005,phase:1,allow,log,msg:'Gitea webhook exception'"

# 避免对 Gitea 路径的 SQL 注入误报
SecRule REQUEST_URI "@contains /gitea/" "id:1000006,phase:2,pass,nolog,ctl:ruleRemoveById=941000-944999"

# 避免对 Gitea 路径的 XSS 误报
SecRule REQUEST_URI "@contains /gitea/" "id:1000007,phase:2,pass,nolog,ctl:ruleRemoveById=941000-944999"

# 避免对 Gitea 路径的命令注入误报
SecRule REQUEST_URI "@contains /gitea/" "id:1000008,phase:2,pass,nolog,ctl:ruleRemoveById=932000-932999"

# 避免对 Gitea 路径的路径遍历误报
SecRule REQUEST_URI "@contains /gitea/" "id:1000009,phase:2,pass,nolog,ctl:ruleRemoveById=930000-931999"
EOF
    
    # 设置权限
    chown www-data:www-data "$rules_file"
    chmod 644 "$rules_file"
    
    print_success "Gitea 例外规则文件创建完成"
}

# 检查并更新 ModSecurity 主配置
update_modsecurity_config() {
    print_header "更新 ModSecurity 主配置"
    
    local modsec_conf="/etc/nginx/modsecurity/modsec.conf"
    
    # 检查是否已包含自定义规则
    if grep -q "custom-rules/gitea-exceptions.conf" "$modsec_conf"; then
        print_info "Gitea 例外规则已在配置中"
    else
        # 在配置文件末尾添加包含语句
        echo "" >> "$modsec_conf"
        echo "# Gitea 例外规则" >> "$modsec_conf"
        echo "Include /etc/nginx/modsecurity/custom-rules/gitea-exceptions.conf" >> "$modsec_conf"
        print_success "已添加 Gitea 例外规则到 ModSecurity 配置"
    fi
}

# 测试 Nginx 配置
test_nginx_config() {
    print_header "测试 Nginx 配置"
    
    if nginx -t &> /dev/null; then
        print_success "Nginx 配置测试通过"
    else
        print_error "Nginx 配置测试失败"
        nginx -t
        print_warning "请检查配置文件是否正确"
        return 1
    fi
}

# 重启服务
restart_services() {
    print_header "重启服务"
    
    print_info "重启 Nginx 服务..."
    systemctl restart nginx
    
    if systemctl is-active --quiet nginx; then
        print_success "Nginx 服务重启成功"
    else
        print_error "Nginx 服务重启失败"
        return 1
    fi
    
    print_info "重启 Gitea 服务..."
    systemctl restart gitea
    
    if systemctl is-active --quiet gitea; then
        print_success "Gitea 服务重启成功"
    else
        print_error "Gitea 服务重启失败"
        return 1
    fi
}

# 显示使用说明
show_usage() {
    print_header "使用说明"
    
    echo "此脚本为 Gitea 应用添加 ModSecurity 例外规则，解决以下问题："
    echo "1. 仓库迁移时触发安全规则导致 403 错误"
    echo "2. API 调用被误判为攻击"
    echo "3. 常规操作被安全规则拦截"
    echo ""
    echo "添加的例外规则包括："
    echo "- 仓库迁移功能 (/repo/migrate)"
    echo "- API 接口 (/api)"
    echo "- 仓库操作 (/repo/)"
    echo "- Git 操作 (/git/)"
    echo "- WebHook 操作 (/hook/)"
    echo "- 避免 SQL 注入、XSS、命令注入、路径遍历等误报"
    echo ""
    print_info "规则文件位置: /etc/nginx/modsecurity/custom-rules/gitea-exceptions.conf"
    echo ""
    print_success "配置完成！现在可以尝试使用 Gitea 迁移功能了"
}

# 主函数
main() {
    print_header "Gitea ModSecurity 规则调整"
    
    check_root
    check_modsecurity
    create_gitea_exceptions
    update_modsecurity_config
    test_nginx_config
    restart_services
    show_usage
    
    echo ""
    print_color "$GREEN" "==========================================="
    print_color "$GREEN" "  操作完成！"
    print_color "$GREEN" "==========================================="
    echo ""
}

# 执行主函数
main