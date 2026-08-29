# 容器工具批次①（podman/kubectl/k9s/helm）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 podman、kubectl、k9s、helm 四个模块（61→65），遵循统一子命令接口与状态契约。

**Architecture:** 每个模块 = `<分类>/<模块>/install.sh`（自包含子命令脚本）+ `.manifest`（自动注册）+ `README.md`。安装通道：podman 走 pkg_install（Linux 包管理器 / macOS 自动走 brew）；kubectl/k9s/helm 三件套统一「Linux 二进制下载 / macOS brew」模式。spec：`docs/superpowers/specs/2026-08-30-container-tools-design.md`。

**Tech Stack:** Bash + `lib/common.sh`（detect_os/detect_arch → OS_TYPE/ARCH_TYPE_LOWER、pkg_install/pkg_remove/pkg_update、github_latest_tag、github_release_asset_url、emit_status/emit_version/emit_extra、yes_no、command_exists、check_commands、info/warn/error/success）。

## Global Constraints

- 分支：`feat/container-tools`（从 main 新建；main 已含 2 个 spec 提交）。
- 每个模块 `install.sh` 文件头必须含规范用法行 `# 用法: $0 {install|...}`——`lib/menu.sh` 用 `grep -m1 '用法:'` 提取子命令列。
- status 恒退出 0；用 emit_status/emit_version/emit_extra 输出（机器模式无颜色无 emoji）。
- 已装时 install 先 `yes_no` 确认（非 TTY 自动取消，不卡死）；卸载默认保留用户数据，删数据二次确认。
- 不声明 `PLATFORMS`（全平台适用）、不声明 `REQUIRES`。
- shellcheck 0 告警（含 info 级）；`bash -n` 语法通过。
- podman 模块明确不装 `podman-docker`。
- DESC ≤ 20 字。

---

### Task 0: 建分支

- [ ] **Step 1: 从 main 新建分支**

```bash
git checkout main && git checkout -b feat/container-tools
```

---

### Task 1: dev-tools/kubectl

**Files:**
- Create: `dev-tools/kubectl/install.sh`
- Create: `dev-tools/kubectl/.manifest`
- Create: `dev-tools/kubectl/README.md`

**Interfaces:**
- Consumes: `lib/common.sh` 全部 helper（见 Global Constraints）。
- Produces: 模块 `kubectl`，子命令 `install|uninstall|status|help`；status 机器模式输出 `STATE=/VERSION=`。

- [ ] **Step 1: 写 install.sh（完整代码）**

```bash
#!/usr/bin/env bash
#
# kubectl/install.sh
#
# 安装 kubectl —— Kubernetes 命令行客户端。
# 支持 macOS (brew) + Linux (dl.k8s.io 官方二进制)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

BIN="/usr/local/bin/kubectl"

preflight() {
    detect_os
    detect_arch
    check_commands curl
}

# dl.k8s.io 用 amd64/arm64 命名（ARCH_TYPE_LOWER 是 x86_64/arm64）
arch_for_k8s() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

# 从 kubectl 输出提取 vX.Y.Z 版本号（离线 --client 探测，不连集群）
kubectl_client_version() {
    kubectl version --client 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true
}

do_install() {
    preflight
    if command_exists kubectl; then
        local cur
        cur=$(kubectl_client_version)
        yes_no "已检测到 kubectl ${cur:-}，是否覆盖安装最新稳定版？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 kubectl..."
        pkg_install kubectl || { error "brew 安装失败"; exit 1; }
    else
        info "获取 kubectl 最新稳定版本号（dl.k8s.io）..."
        local ver
        ver=$(curl -fsSL --connect-timeout 10 https://dl.k8s.io/release/stable.txt || true)
        if [[ -z "$ver" ]]; then
            error "无法获取版本号（dl.k8s.io 不可达）。手动下载：https://kubernetes.io/zh-cn/docs/tasks/tools/"
            exit 1
        fi
        local arch
        arch=$(arch_for_k8s)
        local url="https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl"
        info "下载 $url ..."
        local tmp
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        curl -fSL "$url" -o "$tmp" || { error "下载失败"; exit 1; }
        sudo install -m 0755 "$tmp" "$BIN"
        success "kubectl 已安装到 $BIN"
    fi
    info "下一步：本地集群用 minikube —— ./install.sh minikube"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "kubectl"; then
            brew uninstall kubectl && success "已卸载 kubectl"
        else
            warn "未通过 brew 检测到 kubectl"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "已删除 $BIN"
        else
            warn "未检测到 $BIN"
        fi
    fi
    if [[ -d "$HOME/.kube" ]]; then
        if yes_no "是否同时删除集群配置 ~/.kube（含集群凭据，默认保留）？"; then
            rm -rf "$HOME/.kube" && success "已删除 ~/.kube"
        else
            info "保留 ~/.kube"
        fi
    fi
}

do_status() {
    if ! command_exists kubectl; then
        emit_status "not_installed" "❌ kubectl 未安装"
        return 0
    fi
    local ver
    ver=$(kubectl_client_version)
    emit_status "installed" "✅ kubectl 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
kubectl —— Kubernetes 命令行客户端

用法: install.sh {install|uninstall|status|help}

  install    安装最新稳定版（Linux: dl.k8s.io 官方二进制；macOS: brew）
  uninstall  卸载（默认保留 ~/.kube 集群配置）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
```

- [ ] **Step 2: 写 .manifest**

```
LABEL=kubectl
CATEGORY=开发环境
DEFAULT_ACTION=install
DESC=Kubernetes 命令行客户端
NEXT_STEPS=本地集群:./install.sh minikube
```

- [ ] **Step 3: 写 README.md**

````markdown
# kubectl

Kubernetes 命令行客户端。Linux 安装 dl.k8s.io 官方稳定版二进制到 `/usr/local/bin`；
macOS 走 Homebrew。卸载默认保留 `~/.kube` 集群配置（删除需二次确认）。

```bash
./install.sh kubectl            # 安装
./install.sh kubectl status     # 状态（机器模式：UXS_STATUS_MODE=machine）
```

本地集群推荐配套 minikube：`./install.sh minikube`
````

- [ ] **Step 4: 语法与风格检查**

Run: `bash -n dev-tools/kubectl/install.sh && shellcheck -x dev-tools/kubectl/install.sh`
Expected: 无输出（0 告警）

- [ ] **Step 5: status 冒烟**

Run: `UXS_STATUS_MODE=machine dev-tools/kubectl/install.sh status; echo "exit=$?"`
Expected: 输出 `STATE=not_installed`（若本机未装），`exit=0`

- [ ] **Step 6: 提交**

```bash
git add dev-tools/kubectl && git commit -m "feat: 新增 kubectl 模块——dl.k8s.io 官方二进制/brew 双通道"
```

---

### Task 2: dev-tools/k9s

**Files:**
- Create: `dev-tools/k9s/install.sh`
- Create: `dev-tools/k9s/.manifest`
- Create: `dev-tools/k9s/README.md`

**Interfaces:**
- Consumes: 同 Task 1；另用 `github_latest_tag` / `github_release_asset_url`。
- Produces: 模块 `k9s`，子命令 `install|uninstall|status|help`。

- [ ] **Step 1: 写 install.sh（完整代码）**

```bash
#!/usr/bin/env bash
#
# k9s/install.sh
#
# 安装 k9s —— Kubernetes 终端管理面板（TUI）。
# 支持 macOS (brew) + Linux (GitHub release 二进制)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="derailed/k9s"
BIN="/usr/local/bin/k9s"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
}

# GitHub release 资产用 amd64/arm64 命名
arch_for_k9s() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

do_install() {
    preflight
    if command_exists k9s; then
        yes_no "已检测到 k9s，是否覆盖安装最新版？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 k9s..."
        pkg_install k9s || { error "brew 安装失败"; exit 1; }
    else
        info "获取 k9s 最新版本（GitHub API）..."
        local ver
        ver=$(github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
        local arch
        arch=$(arch_for_k9s)
        local url
        url=$(github_release_asset_url "$REPO" "k9s_Linux_${arch}.tar.gz")
        [[ -n "$url" ]] || { error "未找到资产 k9s_Linux_${arch}.tar.gz"; exit 1; }
        info "下载 $url ..."
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/k9s.tar.gz" || { error "下载失败"; exit 1; }
        tar -xzf "$tmpdir/k9s.tar.gz" -C "$tmpdir" || { error "解压失败"; exit 1; }
        sudo install -m 0755 "$tmpdir/k9s" "$BIN"
        success "k9s v$ver 已安装到 $BIN"
    fi
    info "下一步：本地集群用 minikube —— ./install.sh minikube"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "k9s"; then
            brew uninstall k9s && success "已卸载 k9s"
        else
            warn "未通过 brew 检测到 k9s"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "已删除 $BIN"
        else
            warn "未检测到 $BIN"
        fi
    fi
    info "k9s 不改写 kubeconfig，集群配置无需清理"
}

do_status() {
    if ! command_exists k9s; then
        emit_status "not_installed" "❌ k9s 未安装"
        return 0
    fi
    local ver
    ver=$(k9s version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ k9s 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
k9s —— Kubernetes 终端管理面板（TUI）

用法: install.sh {install|uninstall|status|help}

  install    安装最新版（Linux: GitHub release 二进制；macOS: brew）
  uninstall  卸载二进制（不动 kubeconfig）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
```

- [ ] **Step 2: 写 .manifest**

```
LABEL=k9s
CATEGORY=开发环境
DEFAULT_ACTION=install
DESC=Kubernetes 终端管理面板
NEXT_STEPS=本地集群:./install.sh minikube
```

- [ ] **Step 3: 写 README.md**

````markdown
# k9s

Kubernetes 终端管理面板（TUI），与桌面版 k7s 互补。Linux 安装 GitHub release 二进制；
macOS 走 Homebrew。不改写 kubeconfig。

```bash
./install.sh k9s            # 安装
./install.sh k9s status     # 状态
```
````

- [ ] **Step 4: 语法与风格检查**

Run: `bash -n dev-tools/k9s/install.sh && shellcheck -x dev-tools/k9s/install.sh`
Expected: 无输出

- [ ] **Step 5: status 冒烟**

Run: `UXS_STATUS_MODE=machine dev-tools/k9s/install.sh status; echo "exit=$?"`
Expected: `STATE=not_installed`，`exit=0`

- [ ] **Step 6: 提交**

```bash
git add dev-tools/k9s && git commit -m "feat: 新增 k9s 模块——K8s 终端管理面板"
```

---

### Task 3: dev-tools/helm

**Files:**
- Create: `dev-tools/helm/install.sh`
- Create: `dev-tools/helm/.manifest`
- Create: `dev-tools/helm/README.md`

**Interfaces:**
- Consumes: 同 Task 1/2。
- Produces: 模块 `helm`，子命令 `install|uninstall|status|help`。

- [ ] **Step 1: 写 install.sh（完整代码）**

```bash
#!/usr/bin/env bash
#
# helm/install.sh
#
# 安装 helm —— Kubernetes 包管理器。
# 支持 macOS (brew) + Linux (get.helm.sh 官方 tarball)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="helm/helm"
BIN="/usr/local/bin/helm"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
}

# get.helm.sh tarball 用 amd64/arm64 命名
arch_for_helm() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

do_install() {
    preflight
    if command_exists helm; then
        yes_no "已检测到 helm，是否覆盖安装最新版？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 helm..."
        pkg_install helm || { error "brew 安装失败"; exit 1; }
    else
        info "获取 helm 最新版本（GitHub API）..."
        local ver
        ver=$(github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
        local arch
        arch=$(arch_for_helm)
        local url="https://get.helm.sh/helm-v${ver}-linux-${arch}.tar.gz"
        info "下载 $url ..."
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/helm.tar.gz" || { error "下载失败（get.helm.sh 不可达？）"; exit 1; }
        tar -xzf "$tmpdir/helm.tar.gz" -C "$tmpdir" || { error "解压失败"; exit 1; }
        sudo install -m 0755 "$tmpdir/linux-${arch}/helm" "$BIN"
        success "helm v$ver 已安装到 $BIN"
    fi
    info "下一步：本地集群用 minikube —— ./install.sh minikube"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "helm"; then
            brew uninstall helm && success "已卸载 helm"
        else
            warn "未通过 brew 检测到 helm"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "已删除 $BIN"
        else
            warn "未检测到 $BIN"
        fi
    fi
}

do_status() {
    if ! command_exists helm; then
        emit_status "not_installed" "❌ helm 未安装"
        return 0
    fi
    local ver
    ver=$(helm version --short 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ helm 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
helm —— Kubernetes 包管理器

用法: install.sh {install|uninstall|status|help}

  install    安装最新版（Linux: get.helm.sh 官方 tarball；macOS: brew）
  uninstall  卸载二进制
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
```

- [ ] **Step 2: 写 .manifest**

```
LABEL=Helm
CATEGORY=开发环境
DEFAULT_ACTION=install
DESC=Kubernetes 包管理器
NEXT_STEPS=本地集群:./install.sh minikube
```

- [ ] **Step 3: 写 README.md**

````markdown
# helm

Kubernetes 包管理器。Linux 从 get.helm.sh 官方分发域下载 tarball（版本号经 GitHub API
获取，避开 raw.githubusercontent 脚本，国内可达）；macOS 走 Homebrew。

```bash
./install.sh helm           # 安装
./install.sh helm status    # 状态
```
````

- [ ] **Step 4: 语法与风格检查**

Run: `bash -n dev-tools/helm/install.sh && shellcheck -x dev-tools/helm/install.sh`
Expected: 无输出

- [ ] **Step 5: status 冒烟**

Run: `UXS_STATUS_MODE=machine dev-tools/helm/install.sh status; echo "exit=$?"`
Expected: `STATE=not_installed`，`exit=0`

- [ ] **Step 6: 提交**

```bash
git add dev-tools/helm && git commit -m "feat: 新增 helm 模块——get.helm.sh 官方 tarball/brew 双通道"
```

---

### Task 4: services/podman

**Files:**
- Create: `services/podman/install.sh`
- Create: `services/podman/.manifest`
- Create: `services/podman/README.md`

**Interfaces:**
- Consumes: 同前；另用 `pkg_update`、`yes_no`、`command_exists`。
- Produces: 模块 `podman`，子命令 `install|mirror|unmirror|uninstall|status|help`。

- [ ] **Step 1: 写 install.sh（完整代码）**

```bash
#!/usr/bin/env bash
#
# podman/install.sh
#
# 安装 podman —— 无守护进程容器引擎（rootless）。
# Linux: 发行版仓库（pkg_install）；macOS: brew + podman machine。
# 注意：刻意不装 podman-docker（会把 docker 命令改指向 podman，与 docker 模块冲突）。
#
# 用法: $0 {install|mirror|unmirror|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

MIRROR_CONF_NAME="uxs-mirror.conf"

# docker.io 国内镜像加速配置（containers 镜像栈格式，非 docker daemon.json）
MIRRORS_CONTENT='[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "docker.m.daocloud.io"

[[registry.mirror]]
location = "docker.1ms.run"

[[registry.mirror]]
location = "dockerpull.org"
'

preflight() {
    detect_os
    detect_arch
}

# rootless 前置：/etc/subuid、/etc/subgid 缺失时补齐当前用户映射段
setup_rootless() {
    if [[ ! -s /etc/subuid || ! -s /etc/subgid ]]; then
        info "补齐 rootless 前置：/etc/subuid /etc/subgid 用户映射..."
        sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER" 2>/dev/null \
            || warn "自动补齐失败，请手动执行：sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER"
    fi
    info "可选：开机自启 rootless 容器需 loginctl enable-linger"
}

# macOS 上是否有已创建的 podman machine
has_machine() {
    podman machine list 2>/dev/null | tail -n +2 | grep -q .
}

do_install() {
    preflight
    if command_exists podman; then
        local cur
        cur=$(podman --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 podman ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 podman CLI..."
        pkg_install podman || { error "brew 安装失败"; exit 1; }
        if ! has_machine; then
            if [[ -t 0 ]] && yes_no "是否立即初始化 podman machine（需下载 GB 级系统镜像，耗时较长）？"; then
                podman machine init && podman machine start && success "podman machine 已就绪"
            else
                info "已跳过。之后手动执行：podman machine init && podman machine start"
            fi
        else
            info "检测到已有 podman machine，跳过初始化"
        fi
    else
        info "通过系统仓库安装 podman..."
        pkg_update || true
        pkg_install podman || { error "podman 安装失败"; exit 1; }
        # podman-compose 可选：部分仓库没有该包，失败不阻断
        pkg_install podman-compose 2>/dev/null || warn "仓库无 podman-compose，可后续 pipx install podman-compose"
        setup_rootless
        success "podman 安装完成。试一下：podman run --rm quay.io/podman/hello"
    fi
    info "拉取 docker.io 镜像慢？换国内加速：./install.sh podman mirror"
}

do_mirror() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local conf_dir="$HOME/.config/containers"
        mkdir -p "$conf_dir"
        printf '%s\n' "$MIRRORS_CONTENT" > "$conf_dir/registries.conf"
        success "已写入 $conf_dir/registries.conf"
        if has_machine; then
            info "machine 需重启后生效：podman machine stop && podman machine start"
        fi
    else
        local conf_dir="/etc/containers/registries.conf.d"
        sudo mkdir -p "$conf_dir"
        printf '%s\n' "$MIRRORS_CONTENT" | sudo tee "$conf_dir/$MIRROR_CONF_NAME" >/dev/null
        success "已写入 $conf_dir/$MIRROR_CONF_NAME，下次拉取即生效"
    fi
}

do_unmirror() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -f "$HOME/.config/containers/registries.conf" ]]; then
            rm -f "$HOME/.config/containers/registries.conf" && success "已移除镜像加速配置"
        else
            warn "未检测到镜像加速配置"
        fi
    else
        if [[ -f "/etc/containers/registries.conf.d/$MIRROR_CONF_NAME" ]]; then
            sudo rm -f "/etc/containers/registries.conf.d/$MIRROR_CONF_NAME" && success "已移除镜像加速配置"
        else
            warn "未检测到镜像加速配置"
        fi
    fi
}

do_uninstall() {
    preflight
    if ! command_exists podman; then
        warn "podman 未安装"
        exit 0
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if has_machine; then
            if yes_no "是否删除 podman machine 磁盘（含全部容器/镜像数据）？"; then
                podman machine stop 2>/dev/null || true
                podman machine rm -f && success "machine 已删除"
            else
                info "保留 machine 与数据"
            fi
        fi
        brew uninstall podman 2>/dev/null || pkg_remove podman 2>/dev/null || true
        success "podman CLI 已卸载"
    else
        yes_no "确认卸载 podman？" || { info "已取消"; exit 0; }
        pkg_remove podman-compose 2>/dev/null || true
        pkg_remove podman || { error "卸载失败"; exit 1; }
        success "podman 已卸载"
        echo "容器存储目录：/var/lib/containers、$HOME/.local/share/containers"
        if yes_no "是否删除容器存储数据（镜像/卷，不可恢复）？"; then
            sudo rm -rf /var/lib/containers "$HOME/.local/share/containers"
            success "存储数据已删除"
        else
            info "保留存储数据"
        fi
    fi
}

do_status() {
    if ! command_exists podman; then
        emit_status "not_installed" "❌ podman 未安装"
        return 0
    fi
    local ver
    ver=$(podman --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local mstate="none"
        if has_machine; then
            mstate=$(podman machine list 2>/dev/null | tail -n +2 | head -1 \
                | grep -oE 'Running|Stopped|Saved' | head -1 || true)
            [[ -z "$mstate" ]] && mstate="present"
        fi
        emit_status "installed" "✅ podman 已安装 ${ver:-(版本未知)}（machine: $mstate）"
        emit_version "$ver"
        emit_extra "machine=$mstate"
    else
        local mode="root"
        [[ $EUID -ne 0 ]] && mode="rootless"
        emit_status "installed" "✅ podman 已安装 ${ver:-(版本未知)}（$mode）"
        emit_version "$ver"
        emit_extra "mode=$mode"
    fi
}

do_help() {
    cat <<'EOF'
podman —— 无守护进程容器引擎（rootless）

用法: install.sh {install|mirror|unmirror|uninstall|status|help}

  install    安装（Linux: 系统仓库含 podman-compose；macOS: brew，可选初始化 machine）
  mirror     docker.io 拉取走国内镜像加速（写 containers registries 配置）
  unmirror   移除镜像加速配置
  uninstall  卸载（默认保留容器存储数据，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

注意：本模块不装 podman-docker（避免劫持 docker 命令，与 docker 模块冲突）。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    mirror)         do_mirror ;;
    unmirror)       do_unmirror ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
```

- [ ] **Step 2: 写 .manifest**

```
LABEL=Podman
CATEGORY=服务
DEFAULT_ACTION=install
DESC=无守护进程容器引擎（rootless）
NEXT_STEPS=镜像加速:./install.sh podman mirror;容器 TUI:./install.sh dev-tui
```

- [ ] **Step 3: 写 README.md**

````markdown
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
````

- [ ] **Step 4: 语法与风格检查**

Run: `bash -n services/podman/install.sh && shellcheck -x services/podman/install.sh`
Expected: 无输出

- [ ] **Step 5: status 冒烟**

Run: `UXS_STATUS_MODE=machine services/podman/install.sh status; echo "exit=$?"`
Expected: `STATE=not_installed`（本 Mac 未装 podman），`exit=0`

- [ ] **Step 6: 提交**

```bash
git add services/podman && git commit -m "feat: 新增 podman 模块——rootless 容器引擎，含 mirror 镜像加速"
```

---

### Task 5: 框架联动（计数与变更日志）

**Files:**
- Modify: `README.md:6`（"61 个模块"→"65 个模块"）
- Modify: `README.md:15`（"- **61 个模块**"→"- **65 个模块**"）
- Modify: `README.md:169`（"## 📦 全部 61 个模块"→"## 📦 全部 65 个模块"）
- Modify: `AGENTS.md:7`（"61 个模块"→"65 个模块"）
- Modify: `AGENTS.md:13`（services 行 "21"→"22"）
- Modify: `AGENTS.md:15`（dev-tools 行 "15"→"18"）
- Modify: `CHANGELOG.md`（`[Unreleased]` 增「新增」条目）

- [ ] **Step 1: 改 README.md 三处计数**

```bash
sed -i '' 's/61 个模块/65 个模块/g' README.md && grep -n "65 个模块" README.md
```
Expected: 命中 3 行（6、15、169）

- [ ] **Step 2: 改 AGENTS.md**

先 `grep -n "61 个模块\|服务类\|开发环境" AGENTS.md` 定位，再把总计数 61→65、
services 21→22、dev-tools 15→18。

- [ ] **Step 3: CHANGELOG 增条目**

先读 `CHANGELOG.md` 的 `[Unreleased]` 段确认既有格式，按其格式新增：

```markdown
### 新增
- **podman**：无守护进程容器引擎（rootless），含 `mirror`/`unmirror` docker.io 国内加速
- **kubectl**：Kubernetes 命令行客户端（dl.k8s.io 官方二进制 / brew）
- **k9s**：Kubernetes 终端管理面板（GitHub release 二进制 / brew）
- **helm**：Kubernetes 包管理器（get.helm.sh 官方 tarball / brew）
- 模块总数 61 → 65
```

- [ ] **Step 4: 提交**

```bash
git add README.md AGENTS.md CHANGELOG.md && git commit -m "docs: 容器工具批次①联动——模块计数 61→65，CHANGELOG 补 4 模块"
```

---

### Task 6: 全量测试验收

- [ ] **Step 1: 静态检查全仓**

Run: `./tests/ci_run.sh --phase static`
Expected: shellcheck 0 告警（含 info 级）

- [ ] **Step 2: 路由/契约测试**

Run: `./tests/ci_run.sh --phase routing`
Expected: 全绿——新模块 status/help exit 0、`set -u` 干净、用法行可被 menu.sh 解析

- [ ] **Step 3: 出口冒烟**

```bash
./install.sh --list-modules | wc -l                                   # 65
./install.sh search podman && ./install.sh search kubectl             # 命中
for m in services/podman dev-tools/kubectl dev-tools/k9s dev-tools/helm; do
    UXS_STATUS_MODE=machine ./$m/install.sh status || echo "FAIL: $m"
done                                                                  # 全部 STATE=... 且 exit 0
```
Expected: 计数 65；search 命中；4 模块 status 输出 `STATE=not_installed`（本机未装）。

- [ ] **Step 4: machine 模式帮助解析抽查**

Run: `./install.sh podman help`（经 install.sh 入口透传）
Expected: 输出 podman 帮助文本，exit 0

---

## Self-Review 结论

- spec 覆盖：模块清单 4/4、统一约定（用法行/manifest/状态契约/确认与保留数据）、
  各模块设计（podman mirror/rootless/machine、kubectl dl.k8s.io+~/.kube 二次确认、
  k9s/helm 二进制通道）、框架联动（README 3 处+AGENTS 3 处+CHANGELOG）、测试四步——
  全部有对应 Task/Step。
- 占位符：无 TBD/TODO；全部代码为成品。
- 一致性：三件套统一 `arch_for_*` 映射（x86_64→amd64）、`BIN=/usr/local/bin/<name>`、
  `${1:-install}` 分发；status 均 `emit_status+emit_version`（podman 另有 emit_extra）。

## 实装验证（不阻塞合入，后续批次模式）

- murphy-server（Ubuntu）实装 podman/kubectl/k9s/helm 各一次，验证 status 与
  `podman run --rm quay.io/podman/hello`。
- macOS 实装 kubectl/k9s/helm；podman machine init 走通。
