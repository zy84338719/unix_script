# k3s

轻量级 Kubernetes 发行版（Rancher 出品），面向边缘/服务器——单二进制、内嵌
containerd、SQLite 存储，1C1G 也能跑。仅 Linux。get.k3s.io 官方脚本安装，卸载用
官方 `k3s-uninstall.sh`。

```bash
./install.sh k3s                 # 安装
sudo k3s kubectl get node        # 验证
```

配套：终端面板 k9s、包管理 helm——`./install.sh k9s` / `./install.sh helm`
