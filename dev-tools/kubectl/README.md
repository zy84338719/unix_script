# kubectl

Kubernetes 命令行客户端。Linux 安装 dl.k8s.io 官方稳定版二进制到 `/usr/local/bin`；
macOS 走 Homebrew。卸载默认保留 `~/.kube` 集群配置（删除需二次确认）。

```bash
./install.sh kubectl            # 安装
./install.sh kubectl status     # 状态（机器模式：UXS_STATUS_MODE=machine）
```

本地集群推荐配套 minikube：`./install.sh minikube`
