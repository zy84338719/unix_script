# Fail2ban 一键安装（仅 Linux）

安装 Fail2ban 并写入一份保护 SSH（sshd）的默认配置。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (apt/yum/dnf) | ✅ |
| macOS | ❌（不适用，依赖 iptables/systemd） |

## 安装

```bash
chmod +x fail2ban/install.sh
./fail2ban/install.sh            # 安装（默认动作）
./fail2ban/install.sh install    # 显式安装
```

安装会：

1. 通过 `apt-get` / `dnf` / `yum`（含 EPEL）安装 fail2ban。
2. 写入 `/etc/fail2ban/jail.local`（已存在则备份为 `.bak.*`），保护 sshd。
3. `systemctl enable --now fail2ban`。

默认策略（可在安装后编辑 `jail.local` 调整）：

| 参数 | 默认值 |
|------|--------|
| `bantime` | 3600 秒（1 小时） |
| `findtime` | 600 秒 |
| `maxretry` | 5 次 |
| `ignoreip` | 本机 + RFC1918 内网 |

## 常用命令

```bash
sudo fail2ban-client status              # 总览
sudo fail2ban-client status sshd         # sshd jail 详情
sudo fail2ban-client set sshd unbanip <IP>   # 解封某 IP
sudo tail -f /var/log/fail2ban.log
```

修改 `/etc/fail2ban/jail.local` 后：

```bash
sudo systemctl restart fail2ban
```

## 卸载

```bash
./fail2ban/install.sh uninstall
```

卸载时会询问是否删除 `jail.local`（保留 `.bak.*` 备份）。

## 说明

- 默认 jail 使用 `backend = systemd`，从 journald 读取 SSH 登录失败，无需依赖 `/var/log/auth.log`。
- 如需更严格策略，请根据实际 SSH 端口与日志路径调整。
