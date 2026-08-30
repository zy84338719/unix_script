# podman

无守护进程容器引擎，原生 rootless，CLI 与 docker 兼容。RHEL 系/麒麟/openEuler 等国产
服务器的默认容器引擎。Linux 走系统仓库（含 podman-compose，无则提示 pipx）；macOS 走
Homebrew，容器运行在 podman machine 虚拟机里。

- `mirror` / `unmirror`：docker.io 拉取走国内加速（写 containers 原生 registries 配置，
  非 docker daemon.json）
- 刻意不装 `podman-docker`：避免劫持 `docker` 命令与 docker 模块冲突

```bash
./install.sh podman             # 安装
./install.sh podman mirror      # docker.io 镜像加速
./install.sh podman status      # 状态（machine 状态 / rootless 模式）
```
