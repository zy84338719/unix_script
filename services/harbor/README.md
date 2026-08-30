# Harbor

CNCF 毕业级自托管 Docker 镜像仓库（goharbor）。offline installer 安装到 `/opt/harbor`，
默认 **http 模式**（hostname 取本机主 IP），admin 密码安装时设置（非交互随机生成、
一次性回显）。仅 Linux，依赖 docker（框架自动先装）。

- 纯 http 时客户端需在 `/etc/docker/daemon.json` 的 `insecure-registries` 加仓库地址
- 数据在 `/data`（数据库/镜像/证书），卸载默认保留、删除二次确认
- 生产建议配 https 与独立域名后重装

```bash
./install.sh harbor           # 安装（下载 600MB+，耐心等待）
./install.sh harbor status    # 状态
```
