#!/bin/bash

# MariaDB APT 交互式安装脚本
# 基于 MariaDB-APT安装指南.md

set -e

echo "======================================="
echo "MariaDB APT 交互式安装脚本"
echo "======================================="

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：请以 root 权限运行此脚本"
    exit 1
fi

# 1. 彻底清理之前的安装
echo "\n1. 彻底清理之前的安装"
echo "----------------------------------------"

# 停止服务
echo "停止 MariaDB 服务..."
sudo systemctl stop mariadb 2>/dev/null || true

# 清理包
echo "清理 MariaDB 包..."
sudo apt purge -y mariadb-server mariadb-client mariadb-common mysql-common 2>/dev/null || true

# 清理配置和数据目录
echo "清理配置和数据目录..."
sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null || true

# 清理编译安装残留
echo "清理编译安装残留..."
sudo rm -rf /usr/local/mysql /usr/local/mariadb /opt/mysql /opt/mariadb 2>/dev/null || true

# 清理服务配置
echo "清理服务配置..."
sudo rm -rf /etc/systemd/system/mariadb.service /etc/systemd/system/multi-user.target.wants/mariadb.service /etc/ld.so.conf.d/mariadb10.conf 2>/dev/null || true
sudo find /etc/rc*.d -name "*mariadb*" -exec rm -f {} \; 2>/dev/null || true
sudo systemctl daemon-reload

# 2. 系统准备
echo "\n2. 系统准备"
echo "----------------------------------------"

# 检查系统编码
echo "检查系统编码..."
locale

# 配置 UTF-8 编码
echo "\n配置 UTF-8 编码..."
sudo apt install -y locales
sudo locale-gen zh_CN.UTF-8
sudo update-locale LC_ALL=zh_CN.UTF-8 LANG=zh_CN.UTF-8

# 检查系统资源
echo "\n检查系统资源..."
echo "内存情况："
free -h
echo "\n磁盘空间："
df -h
echo "\nCPU 核心数："
nproc

# 3. 安装 MariaDB
echo "\n3. 安装 MariaDB"
echo "----------------------------------------"

# 清理 APT 缓存并更新
echo "清理 APT 缓存并更新..."
sudo apt clean
sudo apt update

# 安装 MariaDB 服务器和客户端
echo "安装 MariaDB 服务器和客户端..."
sudo apt install -y mariadb-server mariadb-client

# 4. 安全初始化
echo "\n4. 安全初始化"
echo "----------------------------------------"

# 启动服务
echo "启动 MariaDB 服务..."
sudo systemctl start mariadb

# 交互式配置
echo "\n交互式配置"
echo "----------------------------------------"

# 提示用户设置 root 密码
read -s -p "请设置 MariaDB root 密码: " ROOT_PASSWORD
echo
read -s -p "请再次输入 root 密码: " ROOT_PASSWORD_CONFIRM
echo

# 验证密码是否一致
if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
    echo "错误: 两次输入的密码不一致!"
    exit 1
fi

# 检查密码长度
if [ ${#ROOT_PASSWORD} -lt 6 ]; then
    echo "错误: 密码长度至少为 6 个字符!"
    exit 1
fi

# 询问认证方式
echo "\n请选择 root 用户的认证方式:"
echo "1. 密码认证 (推荐，支持 SSH 远程连接)"
echo "2. Socket 认证 (仅本地免密登录)"
read -p "请输入选择 (1/2): " AUTH_METHOD

# 执行安全加固 SQL 命令
if [ "$AUTH_METHOD" = "1" ]; then
    echo "\n使用密码认证方式进行配置..."
    # 使用 -e 参数传递 SQL 命令，直接使用密码
    sudo mysql -u root -e "
    -- 删除匿名用户
    DELETE FROM mysql.user WHERE User='';
    
    -- 删除远程 root 访问
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    
    -- 删除测试数据库
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    
    -- 设置密码认证
    ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOT_PASSWORD';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
    
    -- 为 127.0.0.1 设置密码认证
    CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$ROOT_PASSWORD';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
    
    -- 为 ::1 设置密码认证
    CREATE USER IF NOT EXISTS 'root'@'::1' IDENTIFIED BY '$ROOT_PASSWORD';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'::1' WITH GRANT OPTION;
    
    -- 刷新权限
    FLUSH PRIVILEGES;
    "
    echo "安全加固完成！"
    echo "- 已删除匿名用户"
    echo "- 已禁止 root 远程登录"
    echo "- 已删除测试数据库"
    echo "- 所有本地 root 账户已配置为密码认证"
    echo "- 现在可以通过 SSH 远程连接 MariaDB 了"
else
    echo "\n使用 Socket 认证方式进行配置..."
    sudo mysql -u root -e "
    -- 删除匿名用户
    DELETE FROM mysql.user WHERE User='';
    
    -- 删除远程 root 访问
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    
    -- 删除测试数据库
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    
    -- 确保 localhost 使用 socket 认证
    ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
    
    -- 为 127.0.0.1 和 ::1 创建账户并使用 socket 认证
    CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED VIA unix_socket;
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
    
    CREATE USER IF NOT EXISTS 'root'@'::1' IDENTIFIED VIA unix_socket;
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'::1' WITH GRANT OPTION;
    
    -- 刷新权限
    FLUSH PRIVILEGES;
    "
    echo "安全加固完成！"
    echo "- 已删除匿名用户"
    echo "- 已禁止 root 远程登录"
    echo "- 已删除测试数据库"
    echo "- 所有本地 root 账户已配置为免密码登录（使用 socket 认证）"
fi

# 5. 服务管理
echo "\n5. 服务管理"
echo "----------------------------------------"

# 启用开机自启
echo "启用开机自启..."
sudo systemctl enable mariadb

# 验证自启动设置
echo "验证自启动设置..."
if systemctl is-enabled mariadb >/dev/null 2>/dev/null; then
    echo "✓ MariaDB 开机自启动已启用"
else
    echo "✗ MariaDB 开机自启动启用失败，请手动执行: sudo systemctl enable mariadb"
fi

# 检查服务状态
echo "检查服务状态..."
sudo systemctl status mariadb --no-pager

# 6. 验证安装
echo "\n6. 验证安装"
echo "----------------------------------------"

# 查看 MariaDB 版本
echo "MariaDB 版本："
mysql --version

# 测试连接
if [ "$AUTH_METHOD" = "1" ]; then
    echo "\n测试连接..."
    echo "使用密码登录测试 (localhost)..."
    mysql -u root -p"$ROOT_PASSWORD" -e "SELECT VERSION(); SHOW DATABASES;"
else
    echo "\n测试连接..."
    echo "使用本地免密登录测试 (localhost)..."
    mysql -u root -e "SELECT VERSION(); SHOW DATABASES;"
fi

echo "\n验证服务状态..."
sudo systemctl status mariadb --no-pager

# 7. 完成提示
echo "\n======================================="
echo "MariaDB 安装完成！"
echo "======================================="
echo ""
echo "常用命令："
echo "- 启动服务: sudo systemctl start mariadb"
echo "- 停止服务: sudo systemctl stop mariadb"
echo "- 重启服务: sudo systemctl restart mariadb"
echo "- 查看状态: sudo systemctl status mariadb"
if [ "$AUTH_METHOD" = "1" ]; then
    echo "- 登录数据库: mysql -u root -p"
else
    echo "- 登录数据库: mysql -u root"
fi
echo ""
echo "安装日志已保存到 /var/log/mariadb_install.log"

# 保存安装日志
echo "$(date) - MariaDB 安装完成" >> /var/log/mariadb_install.log

# 退出
exit 0