# 系统诊断命令集（sys-cmd）

常用运维命令的快捷封装，一眼看清系统状态。纯函数，无需安装，Linux + macOS。

## 子命令

| 子命令 | 说明 | 替代的手动命令 |
|--------|------|---------------|
| `cpu` | CPU 占用 TOP10 进程 | `ps aux --sort=-%cpu \| head` |
| `mem` | 内存占用 TOP10 进程 | `ps aux --sort=-%mem \| head` |
| `port <端口>` | 占用指定端口的进程 | `lsof -i:8080` / `ss -tlnp sport=:8080` |
| `ports` | 所有监听端口一览 | `lsof -iTCP -sTCP:LISTEN` / `ss -tlnp` |
| `disk` | 磁盘空间使用 | `df -h` |
| `du` | 当前目录磁盘占用 TOP10 | `du -sh * \| sort -rh \| head` |
| `net` | 网络连接状态统计 | `ss -s` / `netstat -ant` |
| `top` | 系统概览快照 | `uptime` + `free -h` + `nproc` |
| `logs` | 系统日志入口提示 | journalctl / log show 使用指引 |
| `all` | 依次展示 top/cpu/mem/disk/net/ports | — |

## 用法

```bash
chmod +x sys-cmd/install.sh
./sys-cmd/install.sh cpu              # CPU 占用 TOP10
./sys-cmd/install.sh mem              # 内存占用 TOP10
./sys-cmd/install.sh port 8080        # 谁占了 8080 端口
./sys-cmd/install.sh ports            # 所有监听端口
./sys-cmd/install.sh disk             # 磁盘空间
./sys-cmd/install.sh du               # 目录占用 TOP10
./sys-cmd/install.sh net              # 网络连接统计
./sys-cmd/install.sh all              # 全部展示
```

## 说明
- 自动适配 Linux（ss/netstat/ps/free）与 macOS（lsof/ps/vm_stat/sysctl）
- 纯函数封装，不安装任何东西，随时可用
- `port` 在 macOS 上可能需要 sudo（lsof 权限）
- `du` 在当前目录运行，显示一级子目录占用
