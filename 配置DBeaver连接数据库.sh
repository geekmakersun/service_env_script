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

# 获取连接信息和 SSH 端口
echo "\n4. 获取连接信息..."
echo "默认端口: 3306"
echo "默认用户: root"

# 检测 SSH 端口
echo "\n4.1 检测 SSH 服务状态..."
if command -v ss &> /dev/null; then
    SSH_PORT=$(ss -tuln | grep ssh | awk '{print $4}' | awk -F':' '{print $2}' | head -n 1)
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
    fi
elif command -v netstat &> /dev/null; then
    SSH_PORT=$(netstat -tuln | grep ssh | awk '{print $4}' | awk -F':' '{print $2}' | head -n 1)
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
    fi
else
    SSH_PORT=22
fi
echo "SSH 端口: $SSH_PORT"

# 检查 root 用户连接权限
echo "\n5. 检查 root 用户连接权限..."

# 尝试无密码连接（socket 认证）
mysql -u root -e "SELECT user,host FROM mysql.user WHERE user='root';" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ 可以通过 socket 认证连接到 MariaDB"
    # 检查 root 用户的主机权限
    ROOT_HOSTS=$(mysql -u root -e "SELECT host FROM mysql.user WHERE user='root';" | grep -v host)
    echo "root 用户允许的主机: $ROOT_HOSTS"
    
    # 删除所有远程数据库用户
    echo "\n5.1 删除远程数据库用户..."
    REMOTE_USERS=$(mysql -u root -e "SELECT user,host FROM mysql.user WHERE host != 'localhost' AND host != '127.0.0.1' AND host != '::1';" | grep -v "user")
    if [ -n "$REMOTE_USERS" ]; then
        echo "发现远程用户:"
        echo "$REMOTE_USERS"
        echo "正在删除远程用户..."
        mysql -u root -e "DELETE FROM mysql.user WHERE host != 'localhost' AND host != '127.0.0.1' AND host != '::1';"
        mysql -u root -e "FLUSH PRIVILEGES;"
        echo "✓ 已删除所有远程数据库用户"
    else
        echo "✓ 没有发现远程数据库用户"
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
        
        # 删除所有远程数据库用户
        echo "\n5.1 删除远程数据库用户..."
        REMOTE_USERS=$(mysql -u root -p"$ROOT_PASSWORD" -e "SELECT user,host FROM mysql.user WHERE host != 'localhost' AND host != '127.0.0.1' AND host != '::1';" | grep -v "user")
        if [ -n "$REMOTE_USERS" ]; then
            echo "发现远程用户:"
            echo "$REMOTE_USERS"
            echo "正在删除远程用户..."
            mysql -u root -p"$ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE host != 'localhost' AND host != '127.0.0.1' AND host != '::1';"
            mysql -u root -p"$ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
            echo "✓ 已删除所有远程数据库用户"
        else
            echo "✓ 没有发现远程数据库用户"
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
    # 检查 SSH 端口是否开放
    ufw status | grep -q "$SSH_PORT/tcp"
    if [ $? -eq 0 ]; then
        echo "✓ 防火墙已允许 SSH 端口 ($SSH_PORT)"
    else
        echo "✗ 防火墙未允许 SSH 端口 ($SSH_PORT)，正在配置..."
        ufw allow $SSH_PORT/tcp
        echo "✓ 已允许 SSH 端口 ($SSH_PORT) 外部访问"
    fi
    
    # 关闭所有数据库相关端口，取消远程访问
    echo "\n6.1 关闭数据库远程访问端口..."
    DATABASE_PORTS=(3306 3307 3308 5432 1521 27017)
    for port in "${DATABASE_PORTS[@]}"; do
        ufw status | grep -q "$port/tcp"
        if [ $? -eq 0 ]; then
            echo "✗ 防火墙已允许数据库端口 ($port)，正在关闭..."
            ufw deny $port/tcp
            echo "✓ 已禁止数据库端口 ($port) 外部访问"
        else
            echo "✓ 防火墙已禁止数据库端口 ($port) 外部访问"
        fi
    done
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
echo "4. 填写基本连接信息:"
echo "   - 主机: 127.0.0.1 (通过 SSH 隧道连接)"
echo "   - 端口: 3306"
echo "   - 用户名: root"
echo "   - 认证方式: 密码"
echo "   - 密码: [你的 root 密码]"
echo "5. 切换到 'SSH' 标签页，配置 SSH 隧道:"
echo "   - 主机/IP: 10.8.0.2"
echo "   - 端口: $SSH_PORT (当前服务器的 SSH 端口)"
echo "   - 用户名: [你的 SSH 用户名]"
echo "   - 认证方法: 公钥"
echo "   - 私钥: 选择你的 SSH 私钥文件 (如 id_rsa)"
echo "   - 口令: [如果私钥有密码，填写密码]"
echo "6. 点击 '测试连接' 验证连接"
echo "7. 点击 '完成' 保存连接"
echo ""
echo "提示: 确保 SSH 服务正在运行，并且你的私钥文件有正确的权限。"

echo "\n========================================"
echo "配置完成！"
echo "========================================"
echo "提示: 请确保替换 'your_password' 为实际的 root 密码"
echo "如果需要修改 MariaDB 配置，编辑 /etc/mysql/mariadb.conf.d/50-server.cnf 文件"
echo "保持 bind-address 为 127.0.0.1，确保数据库只监听本地连接"
echo "这样可以完全取消数据库的远程访问，只能通过 SSH 隧道连接"

