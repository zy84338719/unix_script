# Caddy Web 服务器

基于 [Caddy](https://caddyserver.com/) 封装，提供安装、卸载、状态检查。

## 支持平台

| 平台 | 方式 | 服务管理 |
|------|------|----------|
| macOS | Homebrew `caddy` | `brew services` |
| Debian/Ubuntu | 官方 APT 仓库 | systemd `caddy` |
| RHEL/CentOS/Fedora | 官方 COPR 仓库 | systemd `caddy` |

## 安装

```bash
chmod +x caddy/install.sh
./caddy/install.sh            # 安装（默认动作）
./caddy/install.sh install    # 显式安装
```

安装完成后 Caddy 会自动启动，监听 80/443 端口。

## 配置

Caddyfile 位置：
- Linux: `/etc/caddy/Caddyfile`
- macOS (brew): `/usr/local/etc/Caddyfile`

### 示例配置

```caddyfile
# 静态文件服务
example.com {
    root * /var/www/html
    file_server
}

# 反向代理
example.com {
    reverse_proxy localhost:8080
}

# PHP (FastCGI)
example.com {
    root * /var/www/html
    php_fastcgi unix//run/php/php-fpm.sock
    file_server
}
```

## 常用命令

```bash
caddy version                                    # 查看版本
sudo caddy reload --config /etc/caddy/Caddyfile  # 重载配置

# Linux
sudo systemctl status caddy
sudo systemctl restart caddy
sudo journalctl -u caddy -f

# macOS
brew services info caddy
brew services restart caddy
brew services log caddy
```

## 卸载

```bash
./caddy/install.sh uninstall
```

## 说明

- Caddy 默认启用自动 HTTPS（自动申请和续签 Let's Encrypt 证书）。
- 需要域名解析到服务器 IP 才能自动申请证书。
- 官方文档：https://caddyserver.com/docs/
