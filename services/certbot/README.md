# Certbot (Let's Encrypt) 一键安装

封装 Certbot 的安装、卸载与状态检查。Certbot 是 Let's Encrypt 官方客户端，用于自动申请和续期免费 SSL/TLS 证书。

## 支持平台

| 平台 | 包名 | 自动续期 |
|------|------|----------|
| Debian/Ubuntu | `apt: certbot` | systemd `certbot.timer` |
| CentOS/RHEL/Fedora | `dnf/yum: certbot` | systemd `certbot.timer` |
| macOS | `brew: certbot` | cron 定时任务 |

## 安装

```bash
chmod +x certbot/install.sh
./certbot/install.sh            # 安装（默认动作）
./certbot/install.sh install    # 显式安装
```

apt 系统安装时会检测 Nginx，若有则建议安装 `python3-certbot-nginx` 插件。

## 常用命令

```bash
# Nginx 插件模式（自动修改 nginx 配置）
sudo certbot --nginx -d example.com -d www.example.com

# Standalone 模式（临时监听 80 端口，需先停止 nginx）
sudo certbot certonly --standalone -d example.com

# Webroot 模式（配合现有 web 服务器）
sudo certbot certonly --webroot -w /var/www/html -d example.com

# 手动续期测试
sudo certbot renew --dry-run

# 查看已申请的证书
sudo certbot certificates

# 撤销证书
sudo certbot revoke --cert-name example.com
```

## 证书存放

```
/etc/letsencrypt/live/<domain>/
  fullchain.pem   # 完整证书链
  privkey.pem     # 私钥
  cert.pem        # 服务器证书
  chain.pem       # 中间证书
```

## 自动续期

- **Linux**: 通过 systemd `certbot.timer` 自动续期（安装时自动启用）
- **macOS**: 安装时可选配置 cron 任务（每天凌晨 2 点）

## 卸载

```bash
./certbot/install.sh uninstall
```

卸载时会询问是否同时删除所有证书（`/etc/letsencrypt`）。
