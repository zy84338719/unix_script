# 容器工具批次①：Podman / k9s / Helm 设计

- 日期：2026-08-30
- 状态：设计中（待用户确认后实现）
- 关联：`services/docker`（容器引擎模板 + mirror/registry 先例）、`dev-tools/minikube`、`sys-tools/dev-tui`

## 背景

库内容器生态已有 docker（Engine/Desktop 双平台 + compose/buildx 插件 + mirror/registry
换源）与 minikube / k7s / docker-image，但缺 **podman**（用户点名补充）。RHEL 系与国产
系统（麒麟、openEuler、统信服务器版）默认容器引擎即 podman：无守护进程、原生 rootless、
CLI 与 docker 兼容，是 docker 的重要替代/补充。本批次顺带补齐 k8s 生态两个高频 CLI：
k9s（k8s 终端管理面板，与 k7s 桌面版互补）、helm（k8s 包管理器，minikube 装完即用）。

## 模块清单

| 模块 | 位置 | 平台 | 安装来源 | CATEGORY |
|------|------|------|----------|----------|
| `podman` | `services/podman` | 全平台 | Linux=发行版仓库（pkg_install）；macOS=brew | 服务 |
| `k9s` | `dev-tools/k9s` | 全平台 | Linux=GitHub release 二进制；macOS=brew | 开发环境 |
| `helm` | `dev-tools/helm` | 全平台 | Linux=get.helm.sh 官方 tarball；macOS=brew | 开发环境 |

不纳入本批次（YAGNI，留待后续批次）：kind、k3s、nerdctl、podman-desktop、skopeo、
containerd 独立安装；数据库补齐（MySQL/MariaDB、MongoDB）、frp 内网穿透另立批次。

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

- 模块数 61 → 64；主 README 模块计数 3 处刷新；AGENTS.md 表格 services 21→22、
  dev-tools 15→17、总数 61→64；CHANGELOG `[Unreleased]` 增「新增」条目。
- registry / completions / search 均由 `.manifest` 自动发现，无需改 `lib/`。

## 测试与验收

- `./tests/ci_run.sh --phase static`：shellcheck 0 告警（含 info 级）。
- `./tests/ci_run.sh --phase routing`：新模块 status/help exit 0、`set -u` 干净、
  `uninstall)` 分支存在、用法行可被 menu.sh 解析；`--list-modules` 与 `search` 能命中
  3 个新模块。
- macOS 冒烟：k9s/helm/podman 的 status 输出 `not_installed` 且 exit 0。
- 实装验证（不阻塞合入）：murphy-server（Ubuntu）实装 podman/k9s/helm 各一次验证
  status 与基本功能；macOS 实装 k9s/helm、podman machine init 走通。
