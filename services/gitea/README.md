# Gitea 自托管 Git 服务

基于 [Gitea](https://gitea.io/) 封装，提供安装、卸载、状态检查。

## 支持平台

| 平台 | 方式 | 服务管理 |
|------|------|----------|
| macOS | Homebrew `gitea` 或 GitHub 二进制 | `brew services` / launchd |
| Linux (amd64) | GitHub 二进制下载 | systemd `gitea` |
| Linux (arm64/armv7) | GitHub 二进制下载 | systemd `gitea` |

## 安装

```bash
chmod +x gitea/install.sh
./gitea/install.sh            # 安装（默认动作）
./gitea/install.sh install    # 显式安装
```

安装完成后首次访问 `http://<server-ip>:3000` 完成初始安装向导。

## 安装信息

| 项目 | 路径/值 |
|------|---------|
| 二进制文件 | `/usr/local/bin/gitea` |
| 配置文件 | `/etc/gitea/app.ini` |
| 数据目录 | `/var/lib/gitea` |
| Web 端口 | 3000 |
| SSH 端口 | 2222 |
| 系统用户 | `git` |

## 常用命令

```bash
gitea --version                        # 查看版本

# Linux
sudo systemctl status gitea
sudo systemctl restart gitea
sudo journalctl -u gitea -f

# macOS (launchd)
sudo launchctl list | grep gitea
sudo launchctl kickstart -k system/io.gitea.web
tail -f /var/log/gitea.log

# 管理命令
gitea admin user create --admin --username admin --password <pass> --email admin@example.com
```

## 卸载

```bash
./gitea/install.sh uninstall
```

卸载时会询问是否删除数据目录（`/var/lib/gitea`），默认保留。

## 说明

- 首次访问需完成 Web 安装向导（数据库、管理员账号等配置）。
- 默认使用 SQLite，生产环境建议切换为 PostgreSQL 或 MySQL。
- SSH 端口默认为 2222（避免与系统 sshd 冲突），可在 app.ini 中修改。
- 官方文档：https://docs.gitea.io/
