# helm

Kubernetes 包管理器。Linux 从 get.helm.sh 官方分发域下载 tarball（版本号经 GitHub API
获取，避开 raw.githubusercontent 脚本，国内可达）；macOS 走 Homebrew。

```bash
./install.sh helm           # 安装
./install.sh helm status    # 状态
```

本地集群推荐配套 minikube：`./install.sh minikube`
