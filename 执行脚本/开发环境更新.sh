#!/bin/bash

# 开发环境更新脚本 - 更新 git 客户端和 TLS 库

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "错误: 请使用 sudo 运行此脚本"
    exit 1
fi

echo "=== 开始更新开发环境 ==="
echo "当前时间: $(date)"
echo "用户: $(whoami)"
echo "系统: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"

echo -e "\n1. 更新系统包列表..."
apt update

if [ $? -ne 0 ]; then
    echo "错误: 无法更新包列表"
    exit 1
fi

echo -e "\n检查可升级的软件包..."
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c "\[upgradable" | tr -d '[:space:]')
UPGRADABLE_COUNT=${UPGRADABLE_COUNT:-0}
echo "发现 $UPGRADABLE_COUNT 个软件包可以升级"

if [ "$UPGRADABLE_COUNT" -gt 0 ]; then
    echo -e "\n可升级的软件包列表（前20个）:"
    apt list --upgradable 2>/dev/null | head -20
    echo -e "\n正在升级所有可升级的软件包..."
    apt upgrade -y
    if [ $? -eq 0 ]; then
        echo "系统软件包升级完成！"
    else
        echo "警告: 部分软件包升级可能失败"
    fi
else
    echo "所有软件包已是最新版本"
fi

echo "
2. 升级 git 客户端到最新版本..."
echo "添加 Git 官方 PPA 仓库..."
add-apt-repository -y ppa:git-core/ppa
echo "更新包列表（添加 PPA 后）..."
apt update
echo "安装最新版本的 Git..."
apt install -y git

if [ $? -ne 0 ]; then
    echo "错误: 无法升级 git"
    exit 1
fi

echo -e "\n配置 Git 全局参数..."
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global core.compression 0
echo "Git 全局配置完成"

echo -e "\n3. 升级 TLS 相关库..."
apt install -y openssl libssl-dev gnutls-bin

if [ $? -ne 0 ]; then
    echo "错误: 无法升级 TLS 库"
    exit 1
fi

echo -e "\n4. 升级 OpenSSL 到最新版本..."
echo "当前 OpenSSL 版本: $(openssl version | awk '{print $2}')"
echo "检查可用的 OpenSSL 更新..."
apt list --upgradable 2>/dev/null | grep -i openssl || echo "OpenSSL 已是最新版本"

echo "执行 OpenSSL 安全更新..."
apt upgrade -y openssl libssl-dev

if [ $? -eq 0 ]; then
    echo "OpenSSL 升级完成！"
    echo "升级后版本: $(openssl version | awk '{print $2}')"
else
    echo "警告: OpenSSL 升级可能失败，继续使用当前版本"
fi

echo -e "\n5. 优化 OpenSSL 配置..."
echo "OpenSSL 配置信息:"
openssl version -a | grep "OPENSSLDIR"
echo "测试 TLS 连接..."
timeout 5 curl -I https://github.com 2>/dev/null || echo "注意: GitHub 连接测试超时或失败（可能是网络问题）"

echo -e "\n6. 安装开发组件包..."
apt install -y build-essential gcc g++ make cmake autoconf automake libtool pkg-config

if [ $? -ne 0 ]; then
    echo "错误: 无法安装开发组件包"
    exit 1
fi

echo -e "\n7. 验证更新结果..."
echo "Git 版本:"
git --version
echo -e "\nOpenSSL 版本:"
openssl version
echo -e "\nOpenSSL 详细信息:"
openssl version -a | grep -E "(OPENSSLDIR|ENGINESDIR|OPENSSL_VERSION)"
echo -e "\nGnuTLS 版本:"
gnutls-cli --version 2>/dev/null | head -1 || echo "gnutls-cli 未安装"
echo -e "\n开发组件版本:"
gcc --version | head -1
g++ --version | head -1
make --version | head -1
cmake --version | head -1

echo -e "\n8. 清理系统..."
echo "移除不再需要的依赖包..."
apt autoremove -y
echo "清理包缓存..."
apt autoclean
echo "清理完成！"

echo "
=== 更新完成 ==="
echo "OpenSSL 版本: $(openssl version | awk '{print $2}')"
echo "如需手动测试 TLS 连接，可运行: curl -I https://github.com"
echo "
建议: 更新完成后重新启动终端或执行 source ~/.bashrc 以应用更改"
 