# Tailscale 一键安装

基于 [Tailscale](https://tailscale.com/) 官方安装脚本封装，提供安装、卸载、状态检查。

## 支持平台

| 平台 | 方式 | 服务管理 |
|------|------|----------|
| Linux (apt/yum/dnf) | 官方 `https://tailscale.com/install.sh` | systemd `tailscaled` |
| macOS | Homebrew `tailscale` | `brew services` |

## 安装

```bash
chmod +x tailscale/install.sh
./tailscale/install.sh            # 安装（默认动作）
./tailscale/install.sh install    # 显式安装
```

安装完成后登录：

```bash
sudo tailscale up
```

## 常用命令

```bash
tailscale status          # 节点与连接状态
tailscale ip              # 本机 Tailscale IP
sudo tailscale down       # 断开
sudo tailscale up         # 重新连接 / 登录

# Linux 日志
sudo journalctl -u tailscaled -f
```

## 卸载

```bash
./tailscale/install.sh uninstall
```

## 说明

- Linux 上由官方脚本处理多发行版包仓库注册，本脚本仅做封装、服务启停与卸载。
- macOS 需要 [Homebrew](https://brew.sh/)。
- Tailscale 账户需在 https://login.tailscale.com/ 注册。
