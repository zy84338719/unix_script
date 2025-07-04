# macOS/Linux 一键安装脚本集合

这是一个跨平台的服务安装脚本集合，支持在 macOS 和 Linux 系统上一键安装和配置各种常用服务。

## 🌟 特性

- **跨平台支持**：同时支持 macOS 和 Linux 系统
- **多架构兼容**：支持 x86_64、ARM64、ARMv7 等架构
- **智能检测**：自动检测操作系统和 CPU 架构
- **友好交互**：彩色输出和交互式安装过程
- **服务管理**：自动配置开机自启服务
- **错误处理**：完善的错误处理和回滚机制

## 📦 支持的服务

### 1. Node Exporter
Prometheus 系统监控数据收集器

- **支持平台**：Linux、macOS
- **支持架构**：x86_64、ARM64、ARMv7
- **默认端口**：9100
- **服务管理**：systemd (Linux) / launchd (macOS)

### 2. DDNS-GO
动态域名解析服务

- **支持平台**：Linux、macOS  
- **支持架构**：x86_64、ARM64、ARMv7
- **默认端口**：9876
- **Web 界面**：支持通过浏览器配置

## 🚀 快速开始

### 统一安装脚本

使用主安装脚本可以选择安装任何支持的服务：

```bash
# 克隆或下载项目
git clone <repository-url>
cd macos_script

# 给脚本执行权限
chmod +x install.sh

# 运行主安装脚本
./install.sh
```

### 单独安装

您也可以直接运行特定服务的安装脚本：

#### 安装 Node Exporter
```bash
chmod +x node_exporter/install.sh
./node_exporter/install.sh
```

#### 安装 DDNS-GO
```bash
chmod +x ddns-go/install.sh
./ddns-go/install.sh
```

## 💻 系统要求

### 基本要求
- **操作系统**：macOS 10.12+ 或 Linux (任意发行版)
- **权限**：需要 sudo 权限
- **网络**：需要互联网连接以下载软件包

### 依赖工具
脚本会自动检查以下必需工具：
- `curl` - 用于下载文件
- `tar` - 用于解压文件
- `systemctl` - Linux 系统服务管理 (仅 Linux)

## 📋 支持的平台和架构

| 操作系统 | 架构 | Node Exporter | DDNS-GO |
|---------|------|---------------|---------|
| Linux | x86_64 | ✅ | ✅ |
| Linux | ARM64 | ✅ | ✅ | 
| Linux | ARMv7 | ✅ | ✅ |
| macOS | x86_64 (Intel) | ✅ | ✅ |
| macOS | ARM64 (Apple Silicon) | ✅ | ✅ |

### 3. Zsh & Oh My Zsh
强大的 Shell 环境和配置管理工具

- **支持平台**：Linux、macOS
- **功能**：自动安装 Zsh、Oh My Zsh 及常用插件
- **插件**：`zsh-autosuggestions`、`zsh-syntax-highlighting`

## 🔧 安装后配置

### Node Exporter
安装完成后，Node Exporter 将在端口 9100 上运行：

- **状态页面**：`http://your-ip:9100`
- **指标数据**：`http://your-ip:9100/metrics`

#### Linux 服务管理
```bash
# 查看服务状态
sudo systemctl status node_exporter

# 查看日志
sudo journalctl -u node_exporter -f

# 启动/停止/重启服务
sudo systemctl start node_exporter
sudo systemctl stop node_exporter
sudo systemctl restart node_exporter
```

#### macOS 服务管理
```bash
# 查看服务状态
sudo launchctl list | grep node_exporter

# 查看日志
tail -f /var/log/node_exporter.log

# 启动服务
sudo launchctl bootstrap system /Library/LaunchDaemons/com.prometheus.node_exporter.plist

# 停止服务
sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist
```

### DDNS-GO
安装完成后，DDNS-GO 将在端口 9876 上运行：

- **Web 界面**：`http://your-ip:9876`

#### 首次配置
1. 打开浏览器访问 `http://your-ip:9876`
2. 设置管理员密码
3. 配置 DNS 服务商信息
4. 添加要更新的域名

### Zsh & Oh My Zsh
安装脚本会自动完成以下配置：
- 安装 Zsh 和 Oh My Zsh
- 下载 `zsh-autosuggestions` 和 `zsh-syntax-highlighting` 插件
- 在 `.zshrc` 文件中启用插件
- 提示您是否要将 Zsh 设置为默认 Shell

安装完成后，请**重启您的终端**以使所有更改生效。

#### Linux 服务管理
```bash
# 查看服务状态
sudo systemctl status zsh

# 查看日志
sudo journalctl -u zsh -f

# 启动/停止/重启服务
sudo systemctl start zsh
sudo systemctl stop zsh
sudo systemctl restart zsh
```

#### macOS 服务管理
```bash
# 查看服务状态
sudo launchctl list | grep zsh

# 查看日志
tail -f /var/log/zsh.log

# 启动服务
sudo launchctl bootstrap system /Library/LaunchDaemons/com.zsh.zsh.plist

# 停止服务
sudo launchctl bootout system /Library/LaunchDaemons/com.zsh.zsh.plist
```

## 🐛 故障排除

### 常见问题

#### 1. 权限错误
确保使用具有 sudo 权限的用户运行脚本：
```bash
sudo -v  # 测试 sudo 权限
```

#### 2. 网络连接问题
检查网络连接和 DNS 解析：
```bash
curl -I https://api.github.com
```

#### 3. 服务启动失败
查看详细错误日志：

**Linux:**
```bash
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -f
```

**macOS:**
```bash
sudo launchctl list | grep <service-name>
tail -f /var/log/<service-name>.log
```

#### 4. 端口冲突
检查端口是否被占用：
```bash
# Linux
sudo netstat -tlnp | grep :9100
sudo ss -tlnp | grep :9100

# macOS
sudo lsof -i :9100
```

#### 5. Zsh 安装后终端未变化
- **重启终端**：确保您已经关闭并重新打开了终端窗口。
- **切换默认 Shell**：如果您在脚本提示时没有自动切换，可以手动执行 `chsh -s $(which zsh)`，然后重新登录。

### 卸载服务

#### Node Exporter

**Linux:**
```bash
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter
sudo rm /etc/systemd/system/node_exporter.service
sudo rm /usr/local/bin/node_exporter
sudo userdel node_exporter
sudo systemctl daemon-reload
```

**macOS:**
```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist
sudo rm /Library/LaunchDaemons/com.prometheus.node_exporter.plist
sudo rm /usr/local/bin/node_exporter
```

#### DDNS-GO

**Linux:**
```bash
sudo systemctl stop ddns-go
sudo systemctl disable ddns-go
sudo rm -rf /opt/ddns-go
```

**macOS:**
```bash
sudo launchctl bootout system /Library/LaunchDaemons/jeessy.ddns-go.plist
sudo rm /Library/LaunchDaemons/jeessy.ddns-go.plist
sudo rm -rf /opt/ddns-go
```

#### Zsh & Oh My Zsh

卸载 Zsh 和 Oh My Zsh 是一个敏感操作，建议手动执行以避免风险。

1.  **卸载 Oh My Zsh**
    Oh My Zsh 官方提供了一个卸载脚本。在终端中运行以下命令：
    ```bash
    uninstall_oh_my_zsh
    ```

2.  **切换回默认 Shell**
    在卸载 Zsh 之前，**必须**将您的默认 Shell 切换回 `bash` 或其他 Shell。
    ```bash
    chsh -s /bin/bash
    ```
    执行后请注销并重新登录。

3.  **卸载 Zsh**
    使用系统的包管理器卸载 Zsh。

    - **Ubuntu/Debian**:
      ```bash
      sudo apt-get remove --purge zsh
      ```
    - **CentOS/RHEL**:
      ```bash
      sudo yum remove zsh
      ```
    - **macOS (Homebrew)**:
      ```bash
      brew uninstall zsh
      ```

4.  **清理配置文件**
    您可以选择性地删除 Zsh 的配置文件：
    ```bash
    rm ~/.zshrc
    rm ~/.zsh_history # (如果存在)
    ```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目！

### 添加新服务
1. 在项目根目录创建新的服务目录
2. 编写对应的 `install.sh` 脚本
3. 更新主安装脚本和文档

### 报告问题
请在 Issue 中包含：
- 操作系统和版本
- CPU 架构
- 错误信息
- 重现步骤

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

感谢以下开源项目：
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
- [DDNS-GO](https://github.com/jeessy2/ddns-go)
- [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)
- [zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
- [zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)

---

**注意**：这些脚本会修改系统配置和安装服务，请在生产环境使用前充分测试。
