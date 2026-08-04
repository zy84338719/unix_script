# Grafana 一键安装

[Grafana](https://github.com/grafana/grafana) 是开源的数据可视化与监控平台，支持多种数据源（Prometheus、InfluxDB、Elasticsearch 等），提供丰富的仪表盘和告警功能。

## 安装

```bash
chmod +x grafana/install.sh
./grafana/install.sh            # 安装（默认动作）
./grafana/install.sh install    # 显式安装
```

### Linux（APT / DNF / YUM）

脚本会自动添加 Grafana 官方仓库并安装：
- APT（Debian/Ubuntu）：添加 GPG 密钥 + 仓库，`apt-get install grafana`
- DNF/YUM（RHEL/CentOS/Fedora）：添加仓库，`dnf install grafana`

### macOS（Homebrew）

```bash
brew install grafana
brew services start grafana
```

## 访问

安装完成后，浏览器打开 `http://your-ip:3000`。

默认登录凭据：
- 用户名：`admin`
- 密码：`admin`
- 首次登录后会提示修改密码

## 添加 Prometheus 数据源

1. 登录 Grafana 后，进入 **Configuration** -> **Data Sources**
2. 点击 **"Add data source"**，选择 **Prometheus**
3. URL 填写：`http://localhost:9090`
4. 点击 **"Save & Test"** 验证连接

推荐安装的仪表盘（Grafana Dashboard ID）：
- **1860**：Node Exporter Full（系统监控）
- **3662**：Prometheus 2.0 Overview

## 常用命令

```bash
# Linux
sudo systemctl status grafana-server
sudo systemctl restart grafana-server
sudo journalctl -u grafana-server -f

# macOS
brew services info grafana
brew services restart grafana
brew services log grafana
```

## 卸载

```bash
./grafana/install.sh uninstall
```

卸载时会询问是否删除数据目录 `/var/lib/grafana`（仪表盘和数据源配置将丢失）。

## 文件位置

| 文件 | Linux 路径 | macOS 路径 |
|------|-----------|-----------|
| 配置 | `/etc/grafana/grafana.ini` | `/usr/local/etc/grafana/grafana.ini` |
| 数据 | `/var/lib/grafana` | `/usr/local/var/lib/grafana` |
| 日志 | `/var/log/grafana` | `/usr/local/var/log/grafana` |
| 服务 | `grafana-server.service` | `brew services` 管理 |
