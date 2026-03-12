#!/bin/bash

# Trae 资源优化脚本
# 版本：2.0
# 日期：2026-03-03
# 功能：资源限制配置、资源监控、进程管理

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/trae_monitor.log"
MAX_MEM_USAGE=1024  # MB
MAX_CPU_USAGE=50    # %

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 显示帮助信息
show_help() {
    echo "Trae 资源优化脚本"
    echo ""
    echo "用法: $0 [选项] [命令]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "命令:"
    echo "  setup               配置资源限制环境"
    echo "  add <PID>           将指定进程加入资源限制cgroup"
    echo "  monitor             启动资源监控"
    echo "  status              查看trae进程状态"
    echo "  clean               清理资源限制配置"
    echo ""
    echo "示例:"
    echo "  $0 setup                    # 配置资源限制环境"
    echo "  $0 add <PID>                # 将进程加入cgroup"
    echo "  $0 monitor                  # 启动监控"
    echo "  $0 status                   # 查看状态"
}

# 配置资源限制环境
setup_environment() {
    echo -e "${GREEN}开始配置Trae资源限制环境...${NC}"
    
    # 1. 安装必要的工具
    echo "安装必要的工具..."
    apt-get update && apt-get install -y cgroup-tools htop bc
    
    # 2. 创建cgroup目录结构
    echo "创建cgroup目录结构..."
    mkdir -p /sys/fs/cgroup/trae
    
    # 3. 配置CPU限制（限制为2个CPU核心）
    echo "配置CPU限制..."
    echo "200000 100000" > /sys/fs/cgroup/trae/cpu.max  # 200ms per 100ms period
    
    # 4. 配置内存限制（限制为1GB内存）
    echo "配置内存限制..."
    echo "1G" > /sys/fs/cgroup/trae/memory.max  # 1GB
    echo "512M" > /sys/fs/cgroup/trae/memory.low  # 512MB
    
    # 5. 配置系统级ulimit
    echo "配置系统级ulimit..."
    cat > /etc/security/limits.d/trae.conf << 'EOF'
# trae资源限制
* soft nofile 1024
* hard nofile 4096
* soft nproc 100
* hard nproc 200
* soft memlock 1048576
* hard memlock 2097152
EOF
    
    # 6. 配置systemd服务
    echo "配置systemd服务..."
    cat > /etc/systemd/system/trae-monitor.service << EOF
[Unit]
Description=Trae Resource Monitor
After=network.target

[Service]
Type=simple
ExecStart=$0 monitor
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # 7. 启用服务
    echo "启用监控服务..."
    systemctl daemon-reload
    systemctl enable trae-monitor.service
    
    # 8. 创建日志文件
    touch $LOG_FILE
    
    echo -e "${GREEN}资源限制环境配置完成！${NC}"
    echo ""
    echo "配置内容："
    echo "1. 创建了cgroup限制，CPU限制为2核心，内存限制为1GB"
    echo "2. 配置了系统ulimit，限制文件打开数和进程数"
    echo "3. 配置了systemd服务，确保监控持续运行"
    echo ""
    echo "使用建议："
    echo "- 使用 '$0 add <PID>' 将trae进程加入cgroup限制"
    echo "- 使用 '$0 monitor' 启动监控"
    echo "- 使用 'systemctl start trae-monitor.service' 启动监控服务"
    echo "- 查看监控日志：tail -f $LOG_FILE"
}

# 将进程加入cgroup
add_to_cgroup() {
    if [ -z "$1" ]; then
        echo -e "${RED}错误：请指定要加入cgroup的进程PID${NC}"
        echo "用法: $0 add <PID>"
        exit 1
    fi
    
    if ! ps -p $1 > /dev/null 2>&1; then
        echo -e "${RED}错误：进程 $1 不存在${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}将进程 $1 加入cgroup...${NC}"
    
    # 将进程加入cgroup v2
    echo $1 > /sys/fs/cgroup/trae/cgroup.procs
    
    echo -e "${GREEN}进程 $1 已加入cgroup并应用资源限制${NC}"
    echo "进程信息："
    ps -p $1 -o pid,ppid,cmd,%cpu,%mem
}

# 监控资源使用
monitor_resources() {
    echo -e "${GREEN}开始监控trae进程资源使用情况...${NC}"
    echo "日志文件: $LOG_FILE"
    
    # 确保日志文件存在
    touch $LOG_FILE
    
    echo "[$(date)] 开始监控trae进程..." >> $LOG_FILE
    
    while true; do
        # 查找trae相关进程
        TRAE_PROCS=$(ps aux | grep -i trae | grep -v grep | awk '{print $2 " " $3 " " $4 " " $11}')
        
        if [ ! -z "$TRAE_PROCS" ]; then
            echo "[$(date)] 发现trae进程:" >> $LOG_FILE
            echo "$TRAE_PROCS" >> $LOG_FILE
            
            # 检查每个进程的资源使用
            echo "$TRAE_PROCS" | while read PID CPU MEM CMD; do
                if (( $(echo "$MEM > $MAX_MEM_USAGE" | bc -l) )); then
                    echo -e "${YELLOW}[$(date)] 警告: 进程 $PID 使用内存过高: ${MEM}MB${NC}" | tee -a $LOG_FILE
                fi
                
                if (( $(echo "$CPU > $MAX_CPU_USAGE" | bc -l) )); then
                    echo -e "${YELLOW}[$(date)] 警告: 进程 $PID CPU使用率过高: ${CPU}%${NC}" | tee -a $LOG_FILE
                fi
            done
        else
            echo "[$(date)] 未发现trae进程" >> $LOG_FILE
        fi
        
        sleep 60  # 每分钟检查一次
    done
}

# 查看进程状态
show_status() {
    echo -e "${GREEN}Trae进程状态：${NC}"
    echo ""
    
    TRAE_PROCS=$(ps aux | grep -i trae | grep -v grep)
    
    if [ -z "$TRAE_PROCS" ]; then
        echo "未发现trae进程"
    else
        echo "PID    %CPU   %MEM   命令"
        echo "----------------------------------------"
        ps aux | grep -i trae | grep -v grep | awk '{printf "%-6s %-6s %-6s %s\n", $2, $3, $4, $11}'
    fi
    
    echo ""
    echo "Cgroup状态："
    if [ -f /sys/fs/cgroup/trae/cgroup.procs ]; then
        echo "cgroup进程数: $(wc -l < /sys/fs/cgroup/trae/cgroup.procs)"
        echo "CPU限制: $(cat /sys/fs/cgroup/trae/cpu.max)"
        echo "内存限制: $(cat /sys/fs/cgroup/trae/memory.max)"
    else
        echo "cgroup未配置"
    fi
    
    echo ""
    echo "监控服务状态："
    systemctl is-active trae-monitor.service 2>/dev/null || echo "监控服务未运行"
}

# 清理配置
clean_environment() {
    echo -e "${YELLOW}清理Trae资源限制配置...${NC}"
    
    # 停止监控服务
    systemctl stop trae-monitor.service 2>/dev/null
    systemctl disable trae-monitor.service 2>/dev/null
    
    # 删除systemd服务文件
    rm -f /etc/systemd/system/trae-monitor.service
    systemctl daemon-reload
    
    # 删除ulimit配置
    rm -f /etc/security/limits.d/trae.conf
    
    # 删除cgroup目录
    rmdir /sys/fs/cgroup/trae 2>/dev/null
    
    echo -e "${GREEN}清理完成${NC}"
}

# 主函数
main() {
    case "$1" in
        -h|--help)
            show_help
            ;;
        setup)
            setup_environment
            ;;
        add)
            add_to_cgroup "$2"
            ;;
        monitor)
            monitor_resources
            ;;
        status)
            show_status
            ;;
        clean)
            clean_environment
            ;;
        *)
            echo -e "${RED}错误：未知命令 '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
