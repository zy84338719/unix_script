# Uptime Kuma 一键安装（Docker）

[Uptime Kuma](https://github.com/louislam/uptime-kuma) 是一个自托管的功能丰富的可用性监控工具（类似 Uptime Robot），支持 HTTP(s)/TCP/Ping/DNS 等多种监控、告警通知与状态页。

## 前置要求
- 已安装 **Docker**（可用本项目的 `docker` 模块安装）。

## 安装

```bash
chmod +x uptime-kuma/install.sh
./uptime-kuma/install.sh            # 安装（默认动作）
./uptime-kuma/install.sh install    # 显式安装
```

通过 Docker 容器部署：
- 镜像：`louislam/uptime-kuma:1`
- 端口映射：宿主机 `3001` → 容器 `3001`
- 数据卷：`uptime-kuma-data` → `/app/data`
- `--restart=always` 随 Docker 自启

## 访问

浏览器打开 `http://your-ip:3001`，首次访问需创建管理员账号。

## 常用命令

```bash
sudo docker ps | grep uptime-kuma
sudo docker logs -f uptime-kuma
sudo docker restart uptime-kuma
```

## 卸载

```bash
./uptime-kuma/install.sh uninstall
```

卸载时会询问是否删除数据卷 `uptime-kuma-data`（监控历史数据将丢失）。

## 说明
- macOS 上需 Docker Desktop 运行中（CI 的 macOS runner 无嵌套虚拟化，故仅 Linux 可实装验证）。
