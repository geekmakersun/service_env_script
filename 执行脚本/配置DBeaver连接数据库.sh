#!/bin/bash

# 配置 DBeaver 连接到本地 Ubuntu 数据库（使用 root 用户）
echo "========================================"
echo "配置 DBeaver 连接到本地 Ubuntu 数据库"
echo "========================================"

# 检查是否安装了 MariaDB
echo "\n1. 检查数据库服务状态..."
if command -v mysql &> /dev/null; then
    echo "✓ MariaDB 客户端已安装"
else
    echo "✗ MariaDB 客户端未安装，正在安装..."
    apt update && apt install -y mariadb-client
fi

# 检查数据库服务是否运行
echo "\n2. 检查数据库服务运行状态..."
systemctl status mariadb > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ MariaDB 服务正在运行"
else
    echo "✗ MariaDB 服务未运行，正在启动..."
    systemctl start mariadb
    systemctl enable mariadb
fi

# 安全初始化
echo "\n3. 运行安全初始化..."
echo "正在执行 mysql_secure_installation..."
mysql_secure_installation

# 获取本地 IP 地址
echo "\n4. 获取本地连接信息..."
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo "本地 IP 地址: $LOCAL_IP"
echo "默认端口: 3306"
echo "默认用户: root"

# 检查 root 用户是否可以远程连接
echo "\n5. 检查 root 用户远程连接权限..."

# 尝试无密码连接（socket 认证）
mysql -u root -e "SELECT user,host FROM mysql.user WHERE user='root';" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ 可以通过 socket 认证连接到 MariaDB"
    # 检查 root 用户的主机权限
    ROOT_HOSTS=$(mysql -u root -e "SELECT host FROM mysql.user WHERE user='root';" | grep -v host)
    echo "root 用户允许的主机: $ROOT_HOSTS"
    
    # 如果没有 '%' 主机权限，添加远程连接权限
    if [[ ! "$ROOT_HOSTS" =~ "%" ]]; then
        echo "\n5. 正在配置 root 用户远程连接权限..."
        # 创建远程 root 用户并设置密码
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'your_password';"
        mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
        mysql -u root -e "FLUSH PRIVILEGES;"
        echo "✓ 已配置 root 用户远程连接权限"
    fi
else
    # 尝试密码连接
    echo "尝试使用密码连接..."
    read -s -p "请输入 MariaDB root 密码: " ROOT_PASSWORD
    echo
    
    mysql -u root -p"$ROOT_PASSWORD" -e "SELECT user,host FROM mysql.user WHERE user='root';" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ 可以通过密码连接到 MariaDB"
        # 检查 root 用户的主机权限
        ROOT_HOSTS=$(mysql -u root -p"$ROOT_PASSWORD" -e "SELECT host FROM mysql.user WHERE user='root';" | grep -v host)
        echo "root 用户允许的主机: $ROOT_HOSTS"
        
        # 如果没有 '%' 主机权限，添加远程连接权限
        if [[ ! "$ROOT_HOSTS" =~ "%" ]]; then
            echo "\n5. 正在配置 root 用户远程连接权限..."
            # 创建远程 root 用户并设置密码
            mysql -u root -p"$ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$ROOT_PASSWORD';"
            mysql -u root -p"$ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
            mysql -u root -p"$ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
            echo "✓ 已配置 root 用户远程连接权限"
        fi
    else
        echo "✗ 无法连接到 MariaDB，请检查 root 密码"
        echo "请先设置 root 密码: 运行 /root/服务环境脚本库/环境脚本/2. MariaDB安装脚本.sh"
        exit 1
    fi
fi

# 检查防火墙设置
echo "\n6. 检查防火墙设置..."
if command -v ufw &> /dev/null; then
    ufw status | grep -q "3306"
    if [ $? -eq 0 ]; then
        echo "✓ 防火墙已允许 3306 端口"
    else
        echo "✗ 防火墙未允许 3306 端口，正在配置..."
        ufw allow 3306/tcp
        echo "✓ 已允许 3306 端口"
    fi
else
    echo "✓ 未检测到 ufw 防火墙"
fi

# 显示 DBeaver 连接配置步骤
echo "\n========================================"
echo "DBeaver 连接配置步骤"
echo "========================================"
echo "1. 打开 DBeaver"
echo "2. 点击 '数据库' -> '新建连接'"
echo "3. 选择 'MariaDB'"
echo "4. 填写连接信息:"
echo "   - 主机: $LOCAL_IP"
echo "   - 端口: 3306"
echo "   - 用户名: root"
echo "   - 密码: [你的 root 密码]"
echo "5. 点击 '测试连接' 验证连接"
echo "6. 点击 '完成' 保存连接"

echo "\n========================================"
echo "配置完成！"
echo "========================================"
echo "提示: 请确保替换 'your_password' 为实际的 root 密码"
echo "如果需要修改 MariaDB 配置，编辑 /etc/mysql/mariadb.conf.d/50-server.cnf 文件"
echo "将 bind-address 改为 0.0.0.0 以允许远程连接"
