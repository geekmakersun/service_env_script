# 服务脚本库

这是一个包含各种服务部署和管理脚本的仓库，旨在简化服务器配置和管理流程。

## 目录结构

```
服务脚本库/
├── 执行脚本/          # 主要脚本文件
├── 文档/             # 相关文档
└── snippets/         # 代码片段
```

## 主要脚本

### 1. Gitea部署脚本.sh
- 功能：部署 Gitea Git 服务
- 支持：完整部署、环境检查、创建 Git 用户、安装 Gitea、配置 Systemd 服务、配置 Nginx 反向代理、申请 SSL 证书等
- 特点：交互式部署，支持分步骤执行

### 3. Nginx站点管理工具.sh
- 功能：管理 Nginx 站点配置
- 支持：创建新站点、删除站点、列出所有站点、查看站点配置、申请 SSL 证书、检测 PHP 版本等
- 特点：支持多种应用类型的伪静态规则，支持多版本 PHP 自动检测

### 4. SSL证书申请脚本.sh
- 功能：申请 SSL 证书
- 支持：Let's Encrypt、ZeroSSL、Buypass 等证书提供商
- 特点：自动检测速率限制，尝试备用提供商

### 5. 其他脚本
- 开发环境更新.sh：更新开发环境
- 配置DBeaver连接数据库.sh：配置 DBeaver 数据库连接
- 配置Git.sh：配置 Git 和编译升级 OpenSSL
- 清理垃圾.sh：清理系统垃圾
- 设置Swap交换空间.sh：设置 Swap 交换空间
- 修改主机名.sh：修改服务器主机名
- 中文环境设置脚本.sh：设置中文环境
- Gitea卸载清理脚本.sh：卸载和清理 Gitea
- Gitea-ModSecurity规则调整.sh：调整 Gitea 的 ModSecurity 规则
- MariaDB安装脚本.sh：安装 MariaDB 数据库
- Nginx+ModSecurity安装脚本.sh：安装 Nginx 和 ModSecurity
- Nginx+ModSecurity卸载清理脚本.sh：卸载和清理 Nginx 和 ModSecurity
- PHP84-FPM安装脚本.sh：安装 PHP 8.4-FPM
- Trae综合管理脚本.sh：Trae 综合管理工具

## 使用说明

### 1. 配置 SSL 证书相关的 API 密钥

对于需要使用 DNS 验证方式申请 SSL 证书的脚本，需要配置 API 密钥：

1. 创建配置目录：
   ```bash
   sudo mkdir -p /etc/ssl-config
   sudo chmod 700 /etc/ssl-config
   ```

2. 阿里云 DNS 验证：创建 `/etc/ssl-config/aliyunak.conf` 文件，内容如下：
   ```
   # Aliyun DNS API credentials
   Ali_Key = 你的阿里云 AccessKey ID
   Ali_Secret = 你的阿里云 AccessKey Secret
   ```

3. Cloudflare DNS 验证：创建 `/etc/ssl-config/cloudflare.conf` 文件，内容如下：
   ```
   # Cloudflare API token
   CF_Token = 你的 Cloudflare API Token
   ```

4. 设置文件权限：
   ```bash
   sudo chmod 600 /etc/ssl-config/*.conf
   ```

### 2. 运行脚本

所有脚本都需要以 root 权限运行：

```bash
sudo bash /path/to/脚本文件.sh
```

### 3. 注意事项

- 脚本默认适用于 Ubuntu 22.04 LTS 系统
- 部分脚本需要联网下载软件包
- 申请 SSL 证书需要域名已正确解析到服务器 IP
- 使用 DNS 验证方式申请证书时，需要确保 API 密钥配置正确

## 开源说明

本仓库已开源，所有私有配置已修改为通用路径，并且对脚本进行了全面优化：

### 配置优化
- 配置目录：`/etc/ssl-config`（替代原 `/root/密钥配置`）
- 所有脚本均已移除硬编码的私有信息
- 提供了详细的使用说明和配置指南

### 代码优化
- **错误处理**：完善了错误处理机制，添加了更详细的错误信息和错误处理逻辑
- **参数验证**：增加了参数验证，确保用户输入的有效性
- **兼容性**：增强了脚本的兼容性，支持多种 Linux 发行版和包管理器
- **安全性**：添加了下载验证、超时重试等安全机制
- **用户体验**：改善了用户界面，添加了颜色输出和更友好的交互方式

### 功能增强
- **系统检测**：自动检测系统类型和架构
- **包管理器支持**：支持 apt、yum 和 dnf 包管理器
- **网络可靠性**：添加了下载超时和重试机制
- **文件验证**：验证下载文件的有效性
- **环境检查**：在执行操作前检查必要的环境和依赖

### 文档完善
- 提供了详细的 README.md 文档
- 完善了脚本的注释和文档

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这些脚本！

## 许可证

MIT License
