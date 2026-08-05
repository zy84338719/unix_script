# UFW 防火墙一键安装（仅 Linux）

安装 UFW（Uncomplicated Firewall）并配置安全的默认策略，放行 SSH 防止远程锁定。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (apt/yum/dnf) | 支持 |
| macOS | 不适用（macOS 自带应用程序防火墙） |

## 安装

```bash
chmod +x ufw/install.sh
./ufw/install.sh            # 安装（默认动作）
./ufw/install.sh install    # 显式安装
```

安装流程：

1. 通过 `apt-get` / `dnf` / `yum` 安装 ufw。
2. 设置默认策略：`deny incoming` / `allow outgoing`。
3. 放行 SSH（22 端口）—— 防止启用后无法远程连接。
4. 可选放行 HTTP（80）和 HTTPS（443）。
5. 执行 `ufw --force enable` 启用防火墙。

## 安全设计

| 配置项 | 值 | 说明 |
|--------|-----|------|
| 默认入站 | deny | 拒绝所有未明确放行的入站连接 |
| 默认出站 | allow | 允许所有出站连接 |
| SSH (22) | allow | **必须放行**，防止远程锁定 |
| HTTP (80) | 可选 | 安装时询问 |
| HTTPS (443) | 可选 | 安装时询问 |

> **警告**：启用防火墙前务必确保 SSH 已放行，否则远程服务器将无法连接。

## 常用命令

```bash
sudo ufw status                  # 查看状态
sudo ufw status verbose          # 详细状态（含策略）
sudo ufw allow 8080/tcp          # 放行端口
sudo ufw allow from 192.168.1.0/24  # 放行网段
sudo ufw delete allow 80/tcp     # 删除规则
sudo ufw reload                  # 重新加载规则
sudo ufw logging on              # 开启日志
```

## 卸载

```bash
./ufw/install.sh uninstall
```

卸载会先禁用防火墙，再移除 ufw 包。

## 说明

- UFW 是 iptables/nftables 的前端，语法简洁，适合日常使用。
- 如需更精细的规则（如限速、连接追踪），可直接编辑 `/etc/ufw/` 下的配置文件。
- 生产环境建议配合 fail2ban 使用，自动封禁恶意 IP。
