# 🚀 快速使用指南

## 立即开始使用新架构

### 基本使用

```bash
# 启动主程序（自动检测系统）
./main.sh

# 或使用快速启动
./quick.sh

# 进程管理工具
./pm.sh nginx          # 搜索 nginx 进程
./pm.sh -p 80          # 搜索监听 80 端口的进程
./pm.sh -k python      # 搜索并终止 python 进程
```

### 功能菜单对照

#### 主菜单选项
1. **Node Exporter** - Prometheus 系统监控
2. **DDNS-GO** - 动态域名解析服务  
3. **WireGuard** - VPN 隧道
4. **Zsh & Oh My Zsh** - Shell 环境配置
5. **Homebrew** - macOS 包管理器（仅 macOS）
6. **自动关机管理** - 定时关机工具
7. **进程管理工具** - 智能进程管理
8. **查看已安装状态** - 系统状态检查
9. **卸载服务/环境** - 清理工具

### 平台差异

#### Linux 系统
- 使用 systemd 管理服务
- 支持多种包管理器 (apt, yum, dnf, pacman, zypper)
- 自动配置防火墙 (ufw, firewalld)

#### macOS 系统  
- 使用 launchd 管理服务
- 集成 Homebrew 包管理器
- 支持 Apple Silicon (M1/M2) 和 Intel

### 新功能亮点

1. **自动平台检测** - 无需手动选择系统类型
2. **智能依赖检查** - 自动检测和安装依赖
3. **完善错误处理** - 友好的错误提示和恢复
4. **安全备份** - 自动备份重要配置文件
5. **服务验证** - 安装后自动验证功能

### 常见使用场景

#### 开发环境搭建
```bash
./main.sh
# 选择 4) Zsh & Oh My Zsh
# 选择 5) Homebrew (macOS)
```

#### 服务器监控
```bash
./main.sh  
# 选择 1) Node Exporter
# 选择 8) 查看已安装状态
```

#### 网络管理
```bash
./main.sh
# 选择 2) DDNS-GO
# 选择 3) WireGuard
```

#### 进程管理
```bash
./pm.sh -p 3000        # 查看 3000 端口进程
./pm.sh nginx          # 管理 nginx 进程
./pm.sh -k -f node     # 强制终止 node 进程
```

### 故障排除

#### 权限问题
```bash
# 确保脚本有执行权限
chmod +x main.sh quick.sh pm.sh
```

#### 依赖缺失
- Linux: 会自动安装 curl, tar, systemctl 等
- macOS: 需要 Xcode Command Line Tools

#### 网络问题
- 脚本会自动重试下载
- 支持代理环境变量

### 高级功能

#### 直接访问平台功能
```bash
# Linux 专用功能
cd linux && bash main.sh

# macOS 专用功能  
cd macos && bash main.sh

# 直接运行特定服务
cd linux/services && bash node_exporter.sh
```

#### 状态检查
```bash
# Linux 状态检查
cd linux/management && bash status_check.sh

# macOS 状态检查
cd macos/management && bash status_check.sh
```

### 配置文件位置

#### 服务配置
- **Node Exporter**: 服务文件在 `/etc/systemd/system/` (Linux) 或 `/Library/LaunchDaemons/` (macOS)
- **DDNS-GO**: 配置目录 `/opt/ddns-go/`
- **WireGuard**: 配置目录 `/etc/wireguard/` (Linux) 或 `/usr/local/etc/wireguard/` (macOS)

#### 环境配置  
- **Zsh**: `~/.zshrc` 和 `~/.oh-my-zsh/`
- **Homebrew**: 自动配置环境变量

### 获取帮助

```bash
# 查看主程序帮助
./main.sh --help

# 查看进程管理工具帮助  
./pm.sh --help

# 查看特定服务帮助
cd linux/services && bash node_exporter.sh --help
```

### 兼容性说明

- ✅ 新架构完全可用
- ✅ 原有脚本继续兼容
- ✅ 可以混合使用新旧版本
- ✅ 无需立即迁移

---

## 🎉 开始享受新的跨平台体验！

新架构提供了更好的用户体验、更强的功能和更好的维护性。立即运行 `./main.sh` 开始使用！
