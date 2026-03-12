#!/bin/bash

# 自动修改主机名脚本
# 使用方法: ./修改主机名.sh [新主机名]

set -e

echo "=== 自动修改主机名脚本 ==="

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请以root权限运行此脚本"
    exit 1
fi

# 获取新主机名
if [ $# -eq 1 ]; then
    NEW_HOSTNAME="$1"
else
    read -p "请输入新主机名: " NEW_HOSTNAME
    if [ -z "$NEW_HOSTNAME" ]; then
        echo "错误: 主机名不能为空"
        exit 1
    fi
fi

# 显示当前主机名
CURRENT_HOSTNAME=$(hostname)
echo "当前主机名: $CURRENT_HOSTNAME"
echo "新主机名: $NEW_HOSTNAME"

# 检查主机名格式
if ! [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}[a-zA-Z0-9]$ ]]; then
    echo "错误: 主机名格式不正确"
    echo "主机名只能包含字母、数字和连字符，且不能以连字符开头或结尾"
    exit 1
fi

# 临时设置主机名
echo "正在临时设置主机名..."
hostnamectl set-hostname "$NEW_HOSTNAME"

# 更新 /etc/hostname 文件
echo "正在更新 /etc/hostname 文件..."
echo "$NEW_HOSTNAME" > /etc/hostname

# 更新 /etc/hosts 文件
echo "正在更新 /etc/hosts 文件..."

# 备份原 hosts 文件
cp /etc/hosts /etc/hosts.bak

# 替换 hosts 文件中的主机名
if grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
    sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
else
    # 如果 hosts 文件中没有当前主机名，则添加
    echo "127.0.0.1   $NEW_HOSTNAME localhost localhost.localdomain"
    echo "::1         $NEW_HOSTNAME localhost localhost.localdomain"
fi

# 验证修改结果
echo "=== 修改结果 ==="
echo "新主机名: $(hostname)"
echo "/etc/hostname 内容:"
cat /etc/hostname
echo "/etc/hosts 内容:"
grep -E "127\.0\.0\.1|::1" /etc/hosts

echo "=== 操作完成 ==="
echo "主机名已成功修改为: $NEW_HOSTNAME"
echo "注意: 某些服务可能需要重启才能识别新主机名"
echo "建议重启系统以确保所有服务都能正确识别新主机名"
