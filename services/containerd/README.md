# containerd

容器运行时 containerd——`ctr` 是它自带的底层 CLI，装 containerd 即有 ctr；另附
nerdctl（containerd 官方的 Docker 兼容 CLI，让 ctr 好用的那一层）。

- Linux：系统仓库安装（Deb 系 `containerd`；部分 RHEL 系仅 docker 仓库的
  `containerd.io`，自动回退），服务 `enable-now`，nerdctl 走 GitHub release 二进制
- macOS：brew 安装 CLI；**宿主无法运行 Linux 容器**，ctr/nerdctl 仅作客户端连
  Linux VM/远程主机的 containerd socket。本机跑容器请用 docker / podman 模块

```bash
./install.sh containerd             # 安装
./install.sh containerd status      # 状态（服务运行态 / macOS cli-only）
```
