# DDNS-GO

[DDNS-GO](https://github.com/jeessy2/ddns-go) —— 自动获得你的公网 IP 并解析到 DNS 服务商，支持阿里云、腾讯云、Cloudflare 等。Linux + macOS。

## 支持平台

| 平台 | 安装方式 | 服务管理 |
|------|----------|----------|
| Linux (x86_64 / ARM64 / ARMv7) | GitHub 二进制 | systemd `ddns-go` |
| macOS (Intel / Apple Silicon) | GitHub 二进制 | launchd `jeessy.ddns-go` |

## 安装

```bash
chmod +x ddns-go/install.sh
./ddns-go/install.sh            # 安装（默认动作）
./ddns-go/install.sh install    # 显式安装
```

安装位置：`/opt/ddns-go`，服务端口：`9876`。

安装完成后浏览器访问 `http://<本机 IP>:9876`，在 Web 界面中配置 DNS 服务商信息和要更新的域名。

## 状态与卸载

```bash
./ddns-go/install.sh status      # 查看安装与运行状态
./ddns-go/install.sh uninstall   # 卸载（停止服务 + 删除 /opt/ddns-go）
```

## 常用命令

```bash
# Linux
sudo systemctl status ddns-go       # 服务状态
sudo journalctl -u ddns-go -f       # 查看日志

# macOS
sudo launchctl list | grep ddns-go  # 服务状态
```

## 说明

- 二进制从 [jeessy2/ddns-go](https://github.com/jeessy2/ddns-go/releases) 最新 Release 下载。
- 配置文件在首次通过 Web 界面访问后自动创建于 `/opt/ddns-go/.ddns_go_config.yaml`。
- 支持设置 `GH_TOKEN` 或 `GITHUB_TOKEN` 环境变量以提高 GitHub API 速率限制。
- 官方文档：https://github.com/jeessy2/ddns-go
