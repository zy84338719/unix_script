# Prometheus 一键安装

[Prometheus](https://github.com/prometheus/prometheus) 是开源的监控与告警系统，广泛用于云原生环境。通过 pull 模型采集指标数据，内置强大的 PromQL 查询语言和时序数据库。

## 安装

```bash
chmod +x prometheus/install.sh
./prometheus/install.sh            # 安装（默认动作）
./prometheus/install.sh install    # 显式安装
```

脚本会自动：
- 从 GitHub Releases 下载最新版本二进制文件
- 安装 `prometheus` 和 `promtool` 到 `/usr/local/bin`
- Linux：创建 `prometheus` 系统用户、systemd 服务
- macOS：创建 LaunchDaemon 服务
- 创建默认配置 `/etc/prometheus/prometheus.yml`（采集 localhost:9090 和 localhost:9100）

### 支持的架构

| 系统 | 架构 |
|------|------|
| Linux | amd64, arm64, armv7 |
| macOS | amd64 (Intel), arm64 (Apple Silicon) |

## 访问

安装完成后，浏览器打开 `http://your-ip:9090` 即可访问 Prometheus Web UI。

默认配置了两个采集任务：
- `prometheus`：采集自身指标（localhost:9090）
- `node_exporter`：采集系统指标（localhost:9100）

## 常用命令

```bash
# 服务管理（Linux）
sudo systemctl status prometheus
sudo systemctl restart prometheus
sudo journalctl -u prometheus -f

# 服务管理（macOS）
sudo launchctl list | grep prometheus
sudo launchctl kickstart -k system/io.prometheus.prometheus
tail -f /var/log/prometheus.log

# 配置检查
promtool check config /etc/prometheus/prometheus.yml

# 查询示例
curl http://localhost:9090/api/v1/query?query=up
```

## 配置文件

默认配置位于 `/etc/prometheus/prometheus.yml`：

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
```

修改配置后，执行 `sudo systemctl restart prometheus` 或调用热重载 API：

```bash
curl -X POST http://localhost:9090/-/reload
```

## 卸载

```bash
./prometheus/install.sh uninstall
```

卸载时会询问是否删除配置目录 `/etc/prometheus` 和数据目录 `/var/lib/prometheus`。

## 文件位置

| 文件 | 路径 |
|------|------|
| 二进制 | `/usr/local/bin/prometheus`, `/usr/local/bin/promtool` |
| 配置 | `/etc/prometheus/prometheus.yml` |
| 数据 | `/var/lib/prometheus` |
| systemd 服务 | `/etc/systemd/system/prometheus.service` |
| launchd 服务 | `/Library/LaunchDaemons/io.prometheus.prometheus.plist` |
