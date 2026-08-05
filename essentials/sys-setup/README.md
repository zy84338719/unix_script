# 系统初始化配置（装机必设置）

装机后第一件事的系统配置集合，仅 Linux。每个子命令对应一项常用装机配置。

## 支持平台
仅 Linux（Debian/Ubuntu/CentOS 等）。

## 功能

| 子命令 | 功能 |
|--------|------|
| `mirror` | 更换软件源为国内镜像（清华 TUNA），原 sources.list 自动备份 |
| `timezone` | 设置时区 Asia/Shanghai 并启用 NTP 时间同步（timesyncd/chrony） |
| `optimize` | 系统参数优化：文件描述符上限 65536、TCP 复用、内核参数 |
| `ssh` | SSH 加固：禁用密码登录、禁用 root 直登（⚠️ 需先配好密钥） |
| `autoupdate` | 启用自动安全更新（unattended-upgrades / dnf-automatic） |
| `all` | 依次执行以上全部 |

## 用法

```bash
chmod +x sys-setup/install.sh
./sys-setup/install.sh all          # 全部执行（推荐装机后一次性配置）
./sys-setup/install.sh mirror       # 仅换源
./sys-setup/install.sh optimize     # 仅优化参数
./sys-setup/install.sh status       # 查看各项配置状态
```

## 说明
- **SSH 加固是敏感操作**：执行 `ssh` 前请确保已配置好 SSH 密钥登录，否则可能无法登录服务器。配置写入 `/etc/ssh/sshd_config.d/99-unix-script.conf`，用 `sshd_config.d` drop-in 方式，干净可回滚。
- 换源、优化、时区均会把原文件备份为 `.bak.<时间戳>` 或写入独立的 `/etc/sysctl.d`、`/etc/security/limits.d` 文件，不覆盖系统原有配置。
- 通过主菜单调用时统一以 `install` 触发，进入后可交互选择具体子项；命令行直接传子命令更直接。
