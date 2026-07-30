# Docker 一键安装

封装 Docker Engine 的安装、卸载与状态检查。

## 支持平台

| 平台 | 方式 | 服务管理 |
|------|------|----------|
| Linux (apt/yum/dnf) | 官方 `https://get.docker.com` | systemd `docker` |
| macOS | 引导安装 Docker Desktop（`brew --cask docker`） | Docker Desktop 应用 |

## 安装

```bash
chmod +x docker/install.sh
./docker/install.sh            # 安装（默认动作）
./docker/install.sh install    # 显式安装
```

Linux 安装时会询问是否将当前用户加入 `docker` 组（免 sudo 使用 docker，需重新登录生效）。安装过程中还会询问是否使用**国内镜像源**（linuxmirrors.cn，含镜像加速，国内网络推荐）。

## 🇨🇳 国内镜像源安装 / 换源（仅 Linux）

本模块集成了 [linuxmirrors.cn](https://linuxmirrors.cn/other/) 的 Docker 一键脚本，针对国内网络优化（安装走国内源、内置镜像加速器）。

### 安装/换源 Docker（含镜像加速）

```bash
./docker/install.sh mirror
```

等价于官方命令 `bash <(curl -sSL https://linuxmirrors.cn/docker.sh)`：安装 Docker Engine（如未安装）并配置国内镜像加速。

### 仅更换镜像加速器（不重装 Docker）

```bash
./docker/install.sh registry
```

等价于官方命令 `bash <(curl -sSL https://linuxmirrors.cn/docker.sh) --only-registry`：仅修改 `/etc/docker/daemon.json` 中的镜像加速地址，不改动 Docker 本身。换源后重启 Docker 生效：

```bash
sudo systemctl restart docker
```

> 说明：`mirror` / `registry` 子命令通过包装 linuxmirrors 官方远程脚本实现，跟随官方更新；执行时由官方脚本负责交互与镜像选择。

## 验证

```bash
docker --version
sudo systemctl status docker      # Linux
sudo docker run hello-world       # 测试运行
```

## 配置镜像加速（可选）

推荐使用上方的 `registry` 子命令一键换源。如需手动配置，编辑 `/etc/docker/daemon.json`（Linux）：

```json
{
  "registry-mirrors": ["https://<你的加速器地址>"]
}
```

然后：

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## 卸载

```bash
./docker/install.sh uninstall
```

卸载时会询问是否同时删除所有镜像/容器/卷（`/var/lib/docker`），默认保留。

## 说明

- 新版 Docker 已内置 `docker compose` 子命令（compose 插件）。
- macOS 推荐 Docker Desktop；本脚本在 macOS 上仅做检测与引导安装。
