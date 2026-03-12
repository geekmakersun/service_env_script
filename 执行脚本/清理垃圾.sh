#!/bin/bash

echo "========================================="
echo "   Ubuntu 系统激进垃圾清理脚本"
echo "========================================="
echo ""
echo "适用于：Ubuntu 18.04+"
echo ""

total_steps=30

# 1. 清理 apt 缓存
echo "[1/$total_steps] 清理 apt 缓存..."
sudo apt-get clean >/dev/null 2>&1
sudo apt-get autoremove -y >/dev/null 2>&1
sudo rm -rf /var/cache/apt/archives/* >/dev/null 2>&1
sudo rm -rf /var/lib/apt/lists/* >/dev/null 2>&1
echo "      ✅ 完成"

# 2. 清理系统日志
echo "[2/$total_steps] 清理系统日志..."
sudo find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null
sudo rm -rf /var/log/*.gz 2>/dev/null
sudo rm -rf /var/log/journal/* 2>/dev/null
sudo rm -rf /var/log/upstart/* 2>/dev/null
sudo rm -rf /var/log/syslog* 2>/dev/null
sudo rm -rf /var/log/auth.log* 2>/dev/null
echo "      ✅ 完成"

# 3. 清理临时文件
echo "[3/$total_steps] 清理临时文件..."
sudo rm -rf /tmp/* 2>/dev/null
sudo rm -rf /var/tmp/* 2>/dev/null
sudo rm -rf /var/lib/dhcp/* 2>/dev/null
echo "      ✅ 完成"

# 4. 清理系统旧内核
echo "[4/$total_steps] 清理系统旧内核..."
sudo apt-get autoremove --purge -y >/dev/null 2>&1
echo "      ✅ 完成"

# 5. 清理用户缓存 (npm/yarn/pip)
echo "[5/$total_steps] 清理用户缓存..."
rm -rf ~/.cache/npm 2>/dev/null
rm -rf ~/.cache/yarn 2>/dev/null
rm -rf ~/.cache/pip 2>/dev/null
rm -rf ~/.cache/pip3 2>/dev/null
rm -rf ~/.cache/composer 2>/dev/null
rm -rf ~/.cache/bower 2>/dev/null
echo "      ✅ 完成"

# 6. 清理 Docker (如果有)
echo "[6/$total_steps] 清理 Docker..."
docker system prune -af 2>/dev/null
docker volume prune -f 2>/dev/null
echo "      ✅ 完成"

# 7. 清理回收站
echo "[7/$total_steps] 清理回收站..."
rm -rf ~/.local/share/Trash/* 2>/dev/null
sudo rm -rf /root/.local/share/Trash/* 2>/dev/null
echo "      ✅ 完成"

# 8. 清理 Snap 包 (Ubuntu 特有)
echo "[8/$total_steps] 清理 Snap 包..."
sudo rm -rf /var/lib/snapd/cache/* 2>/dev/null
sudo rm -rf /var/lib/snapd/assertions/* 2>/dev/null
echo "      ✅ 完成"

# 9. 清理 Flatpak (如果有)
echo "[9/$total_steps] 清理 Flatpak..."
flatpak uninstall --unused -y 2>/dev/null
flatpak repair 2>/dev/null
flatpak --user uninstall --unused -y 2>/dev/null
echo "      ✅ 完成"

# 10. 清理浏览器缓存
echo "[10/$total_steps] 清理浏览器缓存..."
rm -rf ~/.mozilla/firefox/*/cache/* 2>/dev/null
rm -rf ~/.config/google-chrome/Default/Cache/* 2>/dev/null
rm -rf ~/.config/chromium/Default/Cache/* 2>/dev/null
rm -rf ~/.config/microsoft-edge/Default/Cache/* 2>/dev/null
rm -rf ~/.cache/chromium 2>/dev/null
echo "      ✅ 完成"

# 11. 清理系统备份
echo "[11/$total_steps] 清理系统备份..."
sudo rm -rf /var/backups/* 2>/dev/null
sudo rm -rf /var/lib/backups/* 2>/dev/null
echo "      ✅ 完成"

# 12. 清理字体和 man 缓存
echo "[12/$total_steps] 清理字体和 man 缓存..."
sudo rm -rf /var/cache/fontconfig/* 2>/dev/null
sudo rm -rf /var/cache/man/* 2>/dev/null
sudo rm -rf /var/cache/ldconfig/* 2>/dev/null
echo "      ✅ 完成"

# 13. 清理 Python 缓存
echo "[13/$total_steps] 清理 Python 缓存..."
find ~ -name "__pycache__" -type d -exec rm -rf {} \; 2>/dev/null
find ~ -name "*.pyc" -type f -exec rm -f {} \; 2>/dev/null
echo "      ✅ 完成"

# 14. 清理邮件缓存
echo "[14/$total_steps] 清理邮件缓存..."
sudo rm -rf /var/spool/mail/* 2>/dev/null
sudo rm -rf /var/spool/postfix/* 2>/dev/null
echo "      ✅ 完成"

# 15. 清理系统更新缓存
echo "[15/$total_steps] 清理系统更新缓存..."
sudo rm -rf /var/lib/update-notifier/package-data-downloads/* 2>/dev/null
sudo rm -rf /var/lib/update-manager/dpkg* 2>/dev/null
echo "      ✅ 完成"

# 16. 清理 APT 下载缓存
echo "[16/$total_steps] 清理 APT 下载缓存..."
sudo rm -rf /var/cache/apt/archives/partial/* 2>/dev/null
sudo rm -rf /var/cache/apt/pkgcache.bin 2>/dev/null
sudo rm -rf /var/cache/apt/srcpkgcache.bin 2>/dev/null
echo "      ✅ 完成"

# 17. 清理系统日志旋转文件
echo "[17/$total_steps] 清理系统日志旋转文件..."
sudo find /var/log -name "*.1" -o -name "*.2.gz" -o -name "*.3.gz" | xargs sudo rm -f 2>/dev/null
sudo find /var/log -name "*.old" -o -name "*~" | xargs sudo rm -f 2>/dev/null
echo "      ✅ 完成"

# 18. 清理旧的软件包配置
echo "[18/$total_steps] 清理旧的软件包配置..."
sudo dpkg --purge $(dpkg -l | grep '^rc' | awk '{print $2}') 2>/dev/null
echo "      ✅ 完成"

# 19. 清理 X11 缓存
echo "[19/$total_steps] 清理 X11 缓存..."
rm -rf ~/.cache/X11/* 2>/dev/null
rm -rf ~/.Xauthority* 2>/dev/null
echo "      ✅ 完成"

# 20. 清理 PulseAudio 缓存
echo "[20/$total_steps] 清理 PulseAudio 缓存..."
rm -rf ~/.config/pulse/* 2>/dev/null
rm -rf ~/.cache/pulse/* 2>/dev/null
echo "      ✅ 完成"

# 21. 清理 CUPS 打印缓存
echo "[21/$total_steps] 清理 CUPS 打印缓存..."
sudo rm -rf /var/spool/cups/* 2>/dev/null
sudo rm -rf /var/cache/cups/* 2>/dev/null
echo "      ✅ 完成"

# 22. 清理系统崩溃报告
echo "[22/$total_steps] 清理系统崩溃报告..."
sudo rm -rf /var/crash/* 2>/dev/null
sudo rm -rf /var/lib/apport/crash/* 2>/dev/null
echo "      ✅ 完成"

# 23. 清理网络缓存
echo "[23/$total_steps] 清理网络缓存..."
rm -rf ~/.cache/thumbnails/* 2>/dev/null
rm -rf ~/.cache/wget/* 2>/dev/null
rm -rf ~/.cache/curl/* 2>/dev/null
echo "      ✅ 完成"

# 24. 清理系统临时文件
echo "[24/$total_steps] 清理系统临时文件..."
sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null
sudo rm -rf /var/lib/udisks2/* 2>/dev/null
sudo rm -rf /var/lib/polkit-1/* 2>/dev/null
echo "      ✅ 完成"

# 25. 清理 apt 自动清理
echo "[25/$total_steps] 清理 apt 自动清理..."
sudo apt-get autoclean -y >/dev/null 2>&1
echo "      ✅ 完成"

# 26. 清理系统服务缓存
echo "[26/$total_steps] 清理系统服务缓存..."
sudo systemctl daemon-reload >/dev/null 2>&1
sudo journalctl --vacuum-time=1s >/dev/null 2>&1
echo "      ✅ 完成"

# 27. 清理应用程序缓存
echo "[27/$total_steps] 清理应用程序缓存..."
rm -rf ~/.cache/* 2>/dev/null
sudo rm -rf /var/cache/apt/* 2>/dev/null
sudo rm -rf /var/cache/fontconfig/* 2>/dev/null
sudo rm -rf /var/cache/man/* 2>/dev/null
sudo rm -rf /var/cache/ldconfig/* 2>/dev/null
echo "      ✅ 完成"

# 28. 清理系统库缓存
echo "[28/$total_steps] 清理系统库缓存..."
sudo ldconfig >/dev/null 2>&1
echo "      ✅ 完成"

# 29. 清理历史记录
echo "[29/$total_steps] 清理历史记录..."
> ~/.bash_history
> ~/.zsh_history 2>/dev/null
sudo > /root/.bash_history 2>/dev/null
echo "      ✅ 完成"

# 30. 最终清理
echo "[30/$total_steps] 最终清理..."
sudo sync
 echo "      ✅ 完成"

echo ""
echo "========================================="
echo "   清理完成！"
echo "========================================="
echo ""
echo "磁盘使用情况:"
df -h / | tail -1
echo ""
echo "清理已完成！"
