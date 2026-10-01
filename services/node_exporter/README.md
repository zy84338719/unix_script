# Node Exporter

[Node Exporter](https://github.com/prometheus/node_exporter) —— Prometheus 系统指标采集器，暴露 CPU、内存、磁盘、网络等硬件与 OS 指标。Linux + macOS。

## 支持平台

| 平台 | 安装方式 | 服务管理 |
|------|----------|----------|
| Linux (x86_64 / ARM64 / ARMv7) | GitHub 二进制 | systemd `node_exporter` |
| macOS (Intel / Apple Silicon) | GitHub 二进制 | launchd（root LaunchDaemon） |

## 安装

```bash
chmod +x node_exporter/install.sh
./node_exporter/install.sh            # 安装（默认动作）
./node_exporter/install.sh install    # 显式安装
```

安装位置：`/usr/local/bin/node_exporter`，监听端口：`9100`。

Linux 从 GitHub 下载二进制并创建专用系统用户 `node_exporter`；macOS 装为 root LaunchDaemon，开机自启、不依赖用户登录。

**版本策略**：所有平台统一安装 **GitHub 官方 release 的最新 tag**，脚本运行时不查表、不硬编码版本号。上游 node_exporter 发布新版本后，直接重跑 `install` 即可升级，本仓库无需改动。

macOS 即使装了 Homebrew 也**不走 brew**——Homebrew Core 同步上游有延迟，装到的未必是官方最新版。只有官方二进制下载失败（网络受限）时，才回退到 brew 兜底，并会显式告警版本可能落后。

> 若本机此前用 brew 装过 node_exporter，脚本会先停掉它的服务以免争抢 9100，但**不会自动卸载**（`brew uninstall` 的 autoremove 可能连带删掉无关 formulae）。需要清理请手动执行 `brew uninstall node_exporter`。

重复执行 `install` 即为升级：脚本会停掉旧服务、装上官方最新 tag、重启服务并打印实际装上的版本。

## 验证

```bash
curl http://localhost:9100/metrics     # 查看采集的指标
curl http://localhost:9100/            # 状态页面
```

## 状态与卸载

```bash
./node_exporter/install.sh status      # 查看安装与运行状态
./node_exporter/install.sh uninstall   # 卸载（停止服务 + 删除二进制 + 删除用户）
```

## 常用命令

```bash
# Linux
sudo systemctl status node_exporter       # 服务状态
sudo journalctl -u node_exporter -f       # 查看日志
sudo systemctl restart node_exporter      # 重启服务

# macOS（brew 安装时）
brew services info node_exporter
```

## 说明

- 安装后在 Prometheus 配置中添加 `<本机 IP>:9100` 作为 scrape target 即可接入监控。
- Linux 安装会自动创建 `node_exporter` 系统用户（无登录 shell、无 home 目录）。
- 官方文档：https://prometheus.io/docs/guides/node-exporter/
