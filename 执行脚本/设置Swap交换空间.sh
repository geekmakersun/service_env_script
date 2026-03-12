#!/bin/bash

# 交换空间自动配置脚本
# 功能：检查内存使用情况，按需配置交换空间

echo "=== 服务器环境检查与交换空间配置 ==="

# 检查当前内存和交换空间状态
echo "1. 检查当前内存使用情况..."
free -h

# 检查是否已存在交换空间
echo -e "\n2. 检查现有交换空间..."
if swapon --show | grep -q .; then
    echo "交换空间已存在，跳过配置"
    swapon --show
    exit 0
else
    echo "未检测到交换空间，开始配置..."
fi

# 根据内存大小确定交换空间大小（推荐为内存的1-2倍）
TOTAL_MEM_GB=$(free -g | awk '/^(Mem:|内存:)/{print $2}')
SWAP_SIZE_GB=$((TOTAL_MEM_GB * 2))  # 设置为内存的2倍

# 转换为MB数量用于dd命令
SWAP_SIZE_MB=$((SWAP_SIZE_GB * 1024))

echo "3. 配置 ${SWAP_SIZE_GB}GB 交换空间..."

# 使用dd命令创建交换文件（兼容性更好）
sudo dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB}

# 设置权限
sudo chmod 600 /swapfile

# 设置为交换空间
sudo mkswap /swapfile

# 启用交换空间
sudo swapon /swapfile

# 设置开机自动挂载
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 验证配置
echo -e "\n4. 验证交换空间配置..."
swapon --show
free -h

echo -e "\n✅ 交换空间配置完成！"
echo "交换文件位置：/swapfile"
echo "交换空间大小：${SWAP_SIZE_GB}GB"
echo "已设置为开机自动挂载"