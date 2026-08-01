# 新服务器一键配置指南

拿到一台新 Linux 服务器（VPS/云主机/物理机）后，从零到可用的一键配置流程。使用 unix_script 工具库，全程命令行，支持 9 大发行版。

> 前提：有 sudo 权限的普通用户、网络可达 GitHub。

## 第一步：拉起工具库

```bash
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- cli
source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null
```

之后可在任意目录用 `uxs` 命令。或直接交互式菜单：

```bash
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash
```

## 第二步：系统初始化（装机必设置）

```bash
uxs sys-setup all          # 换国内源 + 时区 + 系统优化 + 自动安全更新（推荐一次性全做）
uxs essential-pkgs         # 装 curl/wget/git/vim/htop/tmux/jq 等必备工具
uxs swap install           # 创建 swap（小内存 VPS 必备）
uxs bbr enable             # 开启 BBR 网络加速
```

> SSH 加固（sys-setup ssh）需先配好密钥登录，谨慎使用。

## 第三步：安全防护

```bash
uxs fail2ban               # 安装 Fail2ban 防 SSH 暴力破解
uxs safe-rm                # 安装安全删除（rm 误删防护）
```

## 第四步：按需装服务

```bash
# 监控
uxs node_exporter          # Prometheus 监控指标
uxs uptime-kuma            # 自托管可用性监控面板（需 Docker）

# 网络
uxs tailscale              # 组网 VPN
uxs clash                  # 代理（含国内镜像加速）
uxs docker                 # Docker Engine

# 文件/网盘
uxs openlist               # 文件列表/网盘聚合

# Web 管理
uxs cockpit                # Linux Web 管理面板
```

## 第五步：开发环境（按需）

```bash
uxs zsh                    # Zsh + Oh My Zsh
uxs go                     # Go 语言
uxs nvm                    # Node 版本管理 → 然后 nvm install --lts
uxs bun                    # Bun 运行时
uxs deno                   # Deno 运行时
uxs pnpm                   # pnpm 包管理器
uxs dev-mirror             # npm/Go/Rust/Python 换国内源
```

## 日常维护

```bash
uxs --status               # 查看所有模块安装状态
uxs --list                 # 列出所有可用模块
uxs update                 # 更新 unix_script 自身到最新
uxs sys-setup status       # 查看系统配置状态
```

## 一行命令合集（CI/脚本友好）

```bash
# 最小化配置（换源+必备工具+BBR+Fail2ban）
curl -fsSL .../bootstrap.sh | bash -s -- sys-setup all
curl -fsSL .../bootstrap.sh | bash -s -- essential-pkgs
curl -fsSL .../bootstrap.sh | bash -s -- bbr enable
curl -fsSL .../bootstrap.sh | bash -s -- fail2ban

# 开发环境一键
curl -fsSL .../bootstrap.sh | bash -s -- go
curl -fsSL .../bootstrap.sh | bash -s -- nvm
```

## 支持的发行版

Ubuntu / Debian / CentOS / AlmaLinux / Rocky / Fedora / openSUSE / Arch / Alpine（均有 CI 实测保障）+ macOS。
