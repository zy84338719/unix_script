# Cockpit 一键安装（仅 Linux）

[Cockpit](https://cockpit-project.org/) 是 Linux 的 Web 服务器管理图形面板，通过浏览器管理系统（服务、日志、存储、网络、用户等）。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (apt/dnf/yum) | ✅ |
| macOS | ❌（不适用，依赖 systemd） |

## 安装

```bash
chmod +x cockpit/install.sh
./cockpit/install.sh            # 安装（默认动作）
./cockpit/install.sh install    # 显式安装
```

安装会：
1. 通过 `apt-get`/`dnf`/`yum` 安装 cockpit。
2. 启用并启动 `cockpit.socket`（按需激活的 socket，比常驻服务更安全）。
3. 若存在 `firewall-cmd`/`ufw`，自动放行 9090 端口。

## 访问

浏览器打开 `https://your-ip:9090`，使用**系统用户账号**登录（需有 sudo 权限以执行管理操作）。

## 常用命令

```bash
sudo systemctl status cockpit.socket
sudo systemctl restart cockpit.socket
sudo journalctl -u cockpit -f
```

## 卸载

```bash
./cockpit/install.sh uninstall
```

## 说明
- Cockpit 走 socket 激活模式：`cockpit.socket` 监听 9090，首次访问时才启动 `cockpit` 服务，资源占用低。
- 首次访问浏览器会提示证书不受信任（自签证书），可忽略或后续配置正式证书。
