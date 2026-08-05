# WireGuard

[WireGuard](https://www.wireguard.com) —— 现代、高性能的 VPN 隧道协议，配置简洁、加密先进。Linux + macOS。

## 支持平台

| 平台 | 安装方式 | 服务管理 |
|------|----------|----------|
| Linux (apt/yum/dnf) | `wireguard-tools` 包 | systemd `wg-quick@wg0` |
| macOS | Homebrew `wireguard-tools` | launchd / 手动 |

## 安装

```bash
chmod +x wireguard/install.sh
./wireguard/install.sh            # 安装 WireGuard 工具（默认动作）
./wireguard/install.sh install    # 显式安装
```

安装完成后，需配置 `/etc/wireguard/wg0.conf`（Linux）或 `/usr/local/etc/wireguard/wg0.conf`（macOS）。

## 配置开机自启

```bash
./wireguard/install.sh configure_service    # 配置 wg0 接口开机自启
```

脚本会自动创建 systemd（Linux）或 launchd（macOS）服务。若配置文件不存在，会提示创建占位文件。

## 状态与卸载

```bash
./wireguard/install.sh status      # 查看安装与运行状态
./wireguard/install.sh uninstall   # 卸载服务并可选删除 .conf 配置
```

## 常用命令

```bash
sudo wg show                       # 查看当前 WireGuard 接口状态
sudo wg-quick up wg0               # 手动启动 wg0
sudo wg-quick down wg0             # 手动停止 wg0

# Linux
sudo systemctl status wg-quick@wg0
sudo journalctl -u wg-quick@wg0 -f
```

## 说明

- 本脚本仅安装 `wireguard-tools`（用户态工具），内核模块在 Linux 5.6+ 已内置。
- macOS 通过 Homebrew 安装的 wireguard-tools 包含 `wg` 和 `wg-quick`。
- 卸载服务后，如需完全移除 wireguard-tools，请使用包管理器手动操作。
- 官方文档：https://www.wireguard.com/quickstart/
