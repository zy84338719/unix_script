# Node Exporter

[Node Exporter](https://github.com/prometheus/node_exporter) —— Prometheus 系统指标采集器，暴露 CPU、内存、磁盘、网络等硬件与 OS 指标。Linux + macOS。

## 支持平台

| 平台 | 安装方式 | 服务管理 |
|------|----------|----------|
| Linux (x86_64 / ARM64 / ARMv7) | GitHub 二进制 | systemd `node_exporter` |
| macOS (Intel / Apple Silicon) | Homebrew（优先）或 GitHub 二进制 | brew services / launchd |

## 安装

```bash
chmod +x node_exporter/install.sh
./node_exporter/install.sh            # 安装（默认动作）
./node_exporter/install.sh install    # 显式安装
```

安装位置：`/usr/local/bin/node_exporter`，监听端口：`9100`。

macOS 上优先通过 Homebrew 安装（`brew services` 管理，开机登录自启）；没装 brew 的 macOS 与 Linux 走 GitHub 官方二进制，macOS 下装为 root LaunchDaemon、Linux 下建专用系统用户 `node_exporter`。

**版本策略**：两条路径的版本都是运行时动态取的，脚本不硬编码任何版本号——

- macOS 走 brew 时执行 `brew upgrade`（**不是** `brew install`，后者对已安装的 formula 是 no-op 且 exit 0）
- Linux 与无 brew 的 macOS 走 `github_latest_tag` 取 GitHub 最新 tag

上游 node_exporter 发布新版本后，直接重跑 `install` 即可升级，**本仓库无需改动**。

> brew 装的是 Homebrew Core 的版本，它同步上游有延迟，短时间内可能还拿不到官方最新 tag。这种情况脚本会在结尾显式告警并打出具体差距（`官方最新 vX / brew 当前提供 vY`），等 Homebrew 同步后重跑即可。

重复执行 `install` 即为升级：脚本会停掉旧服务、拉取最新版本、重启服务使新版本生效，并打印实际装上的版本。

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
