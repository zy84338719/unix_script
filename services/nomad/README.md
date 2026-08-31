# nomad

HashiCorp 工作负载编排——单二进制统一调度容器与非容器任务。Linux 走 GitHub release
zip 安装 `/usr/local/bin/nomad`；macOS 走 brew（dev agent 可用）。

```bash
./install.sh nomad           # 安装
nomad agent -dev             # 一键 dev 体验
```

运行容器任务需要 docker 或 podman：`./install.sh docker`
