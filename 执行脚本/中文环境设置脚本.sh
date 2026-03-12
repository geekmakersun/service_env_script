#!/bin/bash

# 中文环境设置脚本
# 全自动将服务器配置为简体中文开发环境

set -e

echo "===================================="
echo "开始设置中文开发环境"
echo "===================================="

# 1. 安装中文语言包
echo "[1/5] 安装中文语言包..."
apt-get update && apt-get install -y --no-install-recommends \
    language-pack-zh-hans \
    language-pack-zh-hans-base \
    fonts-wqy-microhei \
    fonts-wqy-zenhei \
    xfonts-wqy

# 2. 清理并设置系统区域设置
echo "[2/5] 清理并配置系统区域设置..."
# 清理所有非中文语言设置
sed -i '/^[^#].*UTF-8/s/^/# /' /etc/locale.gen
# 确保只启用中文简体
sed -i '/zh_CN.UTF-8/s/^# //' /etc/locale.gen
# 如果不存在则添加
if ! grep -q "zh_CN.UTF-8" /etc/locale.gen; then
    echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
fi
# 生成locale
locale-gen
# 设置系统区域设置
update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN LC_ALL=zh_CN.UTF-8

# 3. 配置环境变量
echo "[3/5] 设置环境变量..."
cat > /etc/environment << 'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN
LC_ALL=zh_CN.UTF-8
EOF

# 4. 安装中文输入法支持（可选）
echo "[4/5] 安装中文输入法支持..."
apt-get install -y --no-install-recommends \
    fcitx \
    fcitx-googlepinyin \
    fcitx-config-gtk

# 配置fcitx环境变量
cat >> /etc/environment << 'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

echo "===================================="
echo "中文环境设置完成！"
echo "===================================="
echo "建议重启系统以应用所有设置：sudo reboot"
echo ""
echo "当前语言设置："
locale
echo ""
echo "中文环境已就绪，您可以开始使用简体中文开发环境了！"
