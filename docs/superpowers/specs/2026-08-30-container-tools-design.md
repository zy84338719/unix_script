# 容器工具批次①：Podman / containerd / kubectl / k9s / Helm 设计

- 日期：2026-08-30
- 状态：已定稿（5 个模块），待实施（containerd/nerdctl 为定稿后按用户要求追加）
- 关联：`services/docker`（容器引擎模板 + mirror/registry 先例）、`dev-tools/minikube`、`sys-tools/dev-tui`

## 背景

库内容器生态已有 docker（Engine/Desktop 双平台 + compose/buildx 插件 + mirror/registry
换源）与 minikube / k7s / docker-image，但缺 **podman**（用户点名补充）。RHEL 系与国产
系统（麒麟、openEuler、统信服务器版）默认容器引擎即 podman：无守护进程、原生 rootless、
CLI 与 docker 兼容，是 docker 的重要替代/补充。本批次同时补齐 k8s 客户端三件套：
kubectl（独立客户端，远程管集群必备——库内有 minikube/k7s 但无 kubectl，缺口明显）、
k9s（k8s 终端管理面板，与 k7s 桌面版互补）、helm（k8s 包管理器，minikube 装完即用）。

## 模块清单

| 模块 | 位置 | 平台 | 安装来源 | CATEGORY |
|------|------|------|----------|----------|
| `podman` | `services/podman` | 全平台 | Linux=发行版仓库（pkg_install）；macOS=brew | 服务 |
| `containerd` | `services/containerd` | 全平台 | Linux=发行版仓库（缺包回退 containerd.io）+ nerdctl GitHub release；macOS=brew（仅 CLI） | 服务 |
| `kubectl` | `dev-tools/kubectl` | 全平台 | Linux=dl.k8s.io 官方二进制；macOS=brew | 开发环境 |
| `k9s` | `dev-tools/k9s` | 全平台 | Linux=GitHub release 二进制；macOS=brew | 开发环境 |
| `helm` | `dev-tools/helm` | 全平台 | Linux=get.helm.sh 官方 tarball；macOS=brew | 开发环境 |

不纳入本批次（YAGNI，留待后续批次）：buildah/skopeo（镜像构建/搬运）、kind、k3s、
harbor、数据库补齐（MySQL/MariaDB、MongoDB）、frp 内网穿透。

> 追加说明：containerd/nerdctl 原列排除项（`ctr` 是 containerd 随附的底层 CLI、无法
> 独立安装），定稿后按用户要求纳入——装 containerd 即有 ctr，模块同时附 nerdctl；
> macOS 宿主无法运行 Linux 容器，status 标注 `cli-only`。

## 统一约定（对齐面板批次①与状态契约）

- 骨架：`set -euo pipefail` + `source lib/common.sh` + `preflight()`（`detect_os` +
  `detect_arch` + 必要 `command_exists` 校验）。
- 子命令：`install | uninstall | status | help`（podman 另有 `mirror | unmirror`）；
  status 恒退出 0。
- **文件头注释含规范用法行** `# 用法: $0 {install|...}`——`lib/menu.sh` 按
  `grep -m1 '用法:'` 提取子命令列（ops-kit 踩坑③），新模块必须带。
- `.manifest`：`LABEL` / `CATEGORY` / `DEFAULT_ACTION=install` / `DESC`（≤20 字）/
  `NEXT_STEPS`；全平台适用，不声明 `PLATFORMS`；无 `REQUIRES`（k9s/helm 是独立 CLI，
  不强依赖 minikube，仅在 NEXT_STEPS 提示）。
- status 遵循 `emit_status`/`emit_version`/`emit_extra` 机器可读契约；已装检测先行，
  install 对已装模块 `yes_no` 确认重装，非 TTY 自动取消不卡死。
- 卸载默认保留容器/集群数据，删除数据需二次确认。

## 各模块设计

### services/containerd

- install（Linux）：`pkg_install containerd`（Deb 系包名 `containerd`；部分 RHEL 系
  仅有 docker 仓库的 `containerd.io`，失败自动回退），`uxs_svc enable-now containerd`
  启服务；nerdctl 经 GitHub release 二进制（`containerd/nerdctl`，资产
  `nerdctl-<ver>-linux-<arch>.tar.gz`）装 `/usr/local/bin/nerdctl`，失败不阻断。
- install（macOS）：`brew install containerd nerdctl`；显式警告宿主无法运行 Linux
  容器，ctr/nerdctl 仅作客户端（`CONTAINERD_ADDRESS` 指向 VM/远程 socket）。
- status：`containerd --version`（离线）→ VERSION；Linux 用 `uxs_svc is-active` 判
  `installed:running/stopped`，EXTRA `nerdctl=yes|no`；macOS 恒 `installed` +
  EXTRA `mode=cli-only`。
- uninstall：Linux 卸载包 + 删 nerdctl 二进制，`/var/lib/containerd` 二次确认；并
  提示 docker 若受影响可 `./install.sh docker` 重装。macOS brew uninstall。

### services/podman

- install（Linux）：`pkg_install podman`；Deb 系若仓库有 `podman-compose` 一并装
  （Ubuntu 22.04+/Debian 12+ 有，缺失时提示用 `pipx install podman-compose`）。
  rootless 前置检查：`/etc/subuid`、`/etc/subgid` 存在性（通常 useradd 自动生成），
  缺失时 `usermod --add-subuids` 补齐；提示 `loginctl enable-linger` 可选。
- install（macOS）：`brew install podman`；CLI 装完即止。`podman machine init` 需
  下载 GB 级机器镜像，不自动执行——交互 TTY 时询问是否立即 `machine init`（非 TTY
  跳过），并在 NEXT_STEPS 给出 `podman machine init && podman machine start`。
- mirror：写 containers 镜像加速配置（参考 docker 模块 mirror 的镜像站清单，
  `prefix=docker.io` + 多 mirror）：
  - Linux：`/etc/containers/registries.conf.d/uxs-mirror.conf`（sudo）
  - macOS：`~/.config/containers/registries.conf`（machine 内容器运行时拉取走宿主配置）
  - `unmirror` 删除对应文件。
- status：`command -v podman` 判已装；`podman --version` → VERSION；Linux 附加
  `EXTRA=rootless|root`（`podman info --format '{{.Host.Security.Rootless}}'`）；
  macOS 附加 `EXTRA=machine=<state>`（`podman machine list` 首行状态，无机器则为
  none）。
- uninstall：Linux `pkg_remove podman podman-compose`；macOS `brew uninstall podman`
  并 `podman machine rm -f`。容器存储数据（Linux `/var/lib/containers` 与
  `~/.local/share/containers`，macOS machine 磁盘镜像）二次确认后删，默认保留。
- 明确**不装 `podman-docker`**（会把 docker 命令改指向 podman，与 docker 模块冲突），
  README 说明等价用法 `alias docker=podman` 由用户自选。

### dev-tools/kubectl

- install（Linux）：版本取 `https://dl.k8s.io/release/stable.txt`（官方稳定版接口，
  无需 GitHub API），二进制
  `https://dl.k8s.io/release/v<ver>/bin/linux/<arch>/kubectl`（arch 映射同 k9s），
  直接放 `/usr/local/bin/kubectl`（sudo）。dl.k8s.io 不可达时给出手动下载指引。
- install（macOS）：`brew install kubectl`。
- status：`kubectl version --client` 离线探测（不连集群）→ VERSION。
- uninstall：Linux 删二进制；macOS `brew uninstall kubectl`。不动 `~/.kube`（用户
  集群凭据，二次确认后才删）。
- NEXT_STEPS：`本地集群:./install.sh minikube`。

### dev-tools/k9s

- install：Linux 用 GitHub release 二进制（`derailed/k9s`，`github_latest_tag` 取版
  本，资产名 `k9s_<OS>_<ARCH>.tar.gz`，arch 映射 ARM64→arm64 / X86_64→amd64），解压
  `k9s` 至 `/usr/local/bin`（sudo）。macOS `brew install k9s`。
- status：`k9s version`（`--short` 不带集群往返，离线可探测）→ VERSION。
- uninstall：Linux 删二进制；macOS `brew uninstall k9s`。不动 kubeconfig。
- NEXT_STEPS：`本地集群:./install.sh minikube`。

### dev-tools/helm

- install：版本取 GitHub API `helm/helm` latest（避免 raw.githubusercontent 脚本，
  国内可达性）；Linux 下载 `https://get.helm.sh/helm-v<ver>-<os>-<arch>.tar.gz`（官方
  分发域，国内可达），解压取二进制至 `/usr/local/bin/helm`（sudo）。macOS
  `brew install helm`。
- status：`helm version --short` → VERSION。
- uninstall：Linux 删二进制；macOS `brew uninstall helm`。
- NEXT_STEPS：`本地集群:./install.sh minikube`。

## 框架联动

- 模块数 61 → 66；主 README 模块计数 3 处刷新；AGENTS.md 表格 services 21→23、
  dev-tools 15→18、总数 61→66；CHANGELOG `[Unreleased]` 增「新增」条目。
- registry / completions / search 均由 `.manifest` 自动发现，无需改 `lib/`。

## 测试与验收

- `./tests/ci_run.sh --phase static`：shellcheck 0 告警（含 info 级）。
- `./tests/ci_run.sh --phase routing`：新模块 status/help exit 0、`set -u` 干净、
  `uninstall)` 分支存在、用法行可被 menu.sh 解析；`--list-modules` 与 `search` 能命中
  5 个新模块。
- macOS 冒烟：kubectl/k9s/helm/podman/containerd 的 status 输出正常（未装→
  not_installed）且 exit 0。
- 实装验证（不阻塞合入）：murphy-server（Ubuntu）实装
  podman/containerd/kubectl/k9s/helm 各一次验证 status 与基本功能；macOS 实装
  kubectl/k9s/helm、podman machine init 走通。
