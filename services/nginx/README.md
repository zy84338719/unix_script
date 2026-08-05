# Nginx 一键安装

封装 Nginx Web 服务器的安装、卸载与状态检查。

## 支持平台

| 平台 | 包名 | 服务管理 |
|------|------|----------|
| Debian/Ubuntu | `apt: nginx` | systemd `nginx` |
| CentOS/RHEL/Fedora | `dnf/yum: nginx` | systemd `nginx` |
| macOS | `brew: nginx` | `brew services` / launchd |

## 安装

```bash
chmod +x nginx/install.sh
./nginx/install.sh            # 安装（默认动作）
./nginx/install.sh install    # 显式安装
```

## 验证

```bash
nginx -v                              # 查看版本
curl -I http://localhost               # 测试默认站点
sudo nginx -t                          # 测试配置语法
```

## 常用命令

```bash
sudo nginx -t                          # 测试配置语法
sudo nginx -s reload                   # 重载配置（不中断连接）
sudo nginx -s stop                     # 停止服务
sudo systemctl status nginx            # 查看服务状态（Linux）
sudo systemctl restart nginx           # 重启服务（Linux）
sudo brew services restart nginx       # 重启服务（macOS）
```

## 配置文件

- Linux: `/etc/nginx/`
- macOS (brew): `$(brew --prefix)/etc/nginx/`

## 卸载

```bash
./nginx/install.sh uninstall
```

卸载时会询问是否同时删除配置文件目录和默认网站目录。

## 端口

- Linux: 默认监听 80 和 443
- macOS (brew): 默认监听 8080
