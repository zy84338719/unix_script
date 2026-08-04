#!/usr/bin/env bash
#
# lib/common.sh
#
# 全脚本库的公共函数库。所有模块脚本通过 `source` 引入：
#
#     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     # shellcheck source=lib/common.sh
#     source "$SCRIPT_DIR/lib/common.sh"
#
# 提供：颜色 / 打印函数 / 平台与架构检测 / 包管理器检测 /
#       权限检查 / 依赖检查 / IP 与版本号获取 / 服务管理封装。
#
# 该文件被多次 source 是安全的（带幂等保护）。

# 本文件定义的全局变量（OS_TYPE/ARCH_TYPE/PKG_MANAGER/OS_KERNEL 等）供
# source 它的脚本读取，故对静态分析“看似未使用”，此处整体豁免 SC2034。
# shellcheck disable=SC2034
# ---------------- 幂等保护 ----------------
if [[ -n "${_UNIX_SCRIPT_COMMON_LOADED:-}" ]]; then
    # 被 source 时 return 成功；直接执行时回退到 exit（shellcheck SC2317 误报）
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
_UNIX_SCRIPT_COMMON_LOADED=1

# ---------------- 颜色定义 ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# NO_COLOR 支持：设置 NO_COLOR=1 或管道（非 TTY）时清除颜色码
# 遵循 https://no-color.org 标准
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' PURPLE='' NC=''
fi

# ---------------- 打印函数（统一命名：info/success/warn/error/header/menu） ----------------
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "${CYAN}$1${NC}"; }
menu()    { echo -e "${PURPLE}$1${NC}"; }

# ---------------- 平台 / 架构检测 ----------------
# 设置全局变量：OS_TYPE (linux|darwin)、ARCH_TYPE (x86_64|ARM64|ARMv7|<原值>)、OS_KERNEL
detect_os() {
    OS_KERNEL="$(uname -s)"
    case "$OS_KERNEL" in
        Linux)  OS_TYPE="linux"  ;;
        Darwin) OS_TYPE="darwin" ;;
        *)
            error "不支持的操作系统：$OS_KERNEL"
            exit 1
            ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)         ARCH_TYPE="x86_64" ;;
        aarch64|arm64)  ARCH_TYPE="ARM64"  ;;
        armv7l)         ARCH_TYPE="ARMv7"  ;;
        *)              ARCH_TYPE="$arch"  ;;
    esac
}

# ---------------- 包管理器检测 ----------------
# 设置全局变量 PKG_MANAGER (apt-get|yum|dnf|brew)；不支持则返回非零。
detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"          # openSUSE
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"          # Arch / Manjaro
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"             # Alpine
    elif command -v brew >/dev/null 2>&1; then
        PKG_MANAGER="brew"
    else
        return 1
    fi
}

# 统一包安装：pkg_install <包名...>
# 自动选择当前发行版的包管理器；已经是 root 则直接执行，否则用 sudo。
# 返回包管理器的退出码。各发行版标志差异在此封装。
pkg_install() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    local sudo_prefix=""
    [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
    case "$PKG_MANAGER" in
        apt-get) $sudo_prefix apt-get install -y "$@" ;;
        dnf)     $sudo_prefix dnf install -y "$@" ;;
        yum)     $sudo_prefix yum install -y "$@" ;;
        zypper)  $sudo_prefix zypper --non-interactive install "$@" ;;
        pacman)  $sudo_prefix pacman -S --noconfirm --needed "$@" ;;
        apk)     $sudo_prefix apk add --no-cache "$@" ;;
        brew)    brew install "$@" ;;
        *)       error "不支持的包管理器: $PKG_MANAGER"; return 1 ;;
    esac
}

# 统一包更新元数据（安装前刷新索引）：pkg_update
pkg_update() {
    detect_pkg_manager || return 1
    local sudo_prefix=""
    [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
    case "$PKG_MANAGER" in
        apt-get) $sudo_prefix apt-get update -y ;;
        dnf)     $sudo_prefix dnf makecache ;;
        yum)     $sudo_prefix yum makecache ;;
        zypper)  $sudo_prefix zypper --non-interactive refresh ;;
        pacman)  $sudo_prefix pacman -Sy ;;
        apk)     $sudo_prefix apk update ;;
        brew)    brew update ;;
    esac
}

# 统一包卸载：pkg_remove <包名...>
pkg_remove() {
    detect_pkg_manager || return 1
    local sudo_prefix=""
    [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
    case "$PKG_MANAGER" in
        apt-get) $sudo_prefix apt-get remove --purge -y "$@" ;;
        dnf)     $sudo_prefix dnf remove -y "$@" ;;
        yum)     $sudo_prefix yum remove -y "$@" ;;
        zypper)  $sudo_prefix zypper --non-interactive remove "$@" ;;
        pacman)  $sudo_prefix pacman -Rns --noconfirm "$@" ;;
        apk)     $sudo_prefix apk del "$@" ;;
        brew)    brew uninstall "$@" ;;
    esac
}

# 查询某包是否已安装：pkg_installed <包名>
pkg_installed() {
    detect_pkg_manager || return 1
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt-get) dpkg -s "$pkg" >/dev/null 2>&1 ;;
        dnf|yum) rpm -q "$pkg" >/dev/null 2>&1 ;;
        zypper)  rpm -q "$pkg" >/dev/null 2>&1 ;;
        pacman)  pacman -Qi "$pkg" >/dev/null 2>&1 ;;
        apk)     apk info -e "$pkg" >/dev/null 2>&1 ;;
        brew)    brew list "$pkg" >/dev/null 2>&1 ;;
    esac
}

# 确保 EPEL 仓库可用（仅 RHEL 系：dnf/yum；其他发行版为空操作）。
# fail2ban/cockpit 等包在 CentOS/RHEL 上位于 EPEL。
ensure_epel() {
    detect_pkg_manager || return 0
    case "$PKG_MANAGER" in
        dnf|yum)
            if ! rpm -q epel-release >/dev/null 2>&1; then
                info "安装 EPEL 仓库..."
                local sudo_prefix=""
                [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
                $sudo_prefix "$PKG_MANAGER" install -y epel-release 2>/dev/null || warn "EPEL 安装失败"
                $sudo_prefix "$PKG_MANAGER" makecache 2>/dev/null || true
            fi
            ;;
    esac
}

# ---------------- 通用辅助 ----------------
# 判断某命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查一组命令是否存在，缺一即报错退出
check_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done
    if ((${#missing[@]} > 0)); then
        error "缺少必要命令：${missing[*]}"
        error "请先安装后再运行本脚本。"
        exit 1
    fi
}

# 确保有足够的权限执行特权操作。
# - 已是 root：直接放行（适用于 CI 容器、直接 root 登录的服务器）
# - 普通用户：确保 sudo 可用（交互式场景）
require_sudo() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        info "此操作需要 sudo 权限，请输入密码："
        sudo -v || { error "无法获取 sudo 权限"; exit 1; }
    fi
}

# ---------------- 网络 / 版本 ----------------
# 获取本机首选 IPv4，失败返回 127.0.0.1
get_local_ip() {
    local ip_addr=""
    if [[ "$OS_TYPE" == "linux" ]]; then
        # hostname -I 在多数发行版可用
        ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        local iface
        for iface in en0 en1 en2; do
            ip_addr=$(ipconfig getifaddr "$iface" 2>/dev/null)
            [[ -n "$ip_addr" ]] && break
        done
    fi
    if [[ -z "$ip_addr" ]]; then
        ip_addr="127.0.0.1"
    fi
    echo "$ip_addr"
}

# 从 GitHub API 取最新 release 的 tag（不含前缀 v）
# 若设置了 GH_TOKEN 或 GITHUB_TOKEN 环境变量，则带认证头（提升速率限制到 5000/h）。
github_latest_tag() {
    local repo="$1"
    local tag
    local auth=()
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -n "$token" ]]; then
        auth=(-H "Authorization: Bearer $token")
    fi
    tag=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
          | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
    echo "$tag"
}

# ---------------- 版本更新检查 ----------------
# 本仓库在 GitHub 的标识（owner/repo），用于查询远端最新 release。
UPDATE_REPO="zy84338719/unix_script"

# 读取本地 VERSION 文件内容（去首尾空白）；读不到返回 "unknown"。
# 依赖调用方已定义的全局变量 SCRIPT_DIR（仓库根）。
get_local_version() {
    local ver_file="${SCRIPT_DIR:-.}/VERSION"
    local ver
    ver=$(tr -d '[:space:]' < "$ver_file" 2>/dev/null)
    if [[ -z "$ver" ]]; then
        ver="unknown"
    fi
    echo "$ver"
}

# 语义化版本比较：当且仅当 a > b 返回 0，否则返回 1。
# 自动去除前导 'v'；对空值或非法版本串保守返回 1（不误报有更新）。
# 实现：用 sort -V 对 "a\nb" 排序，若最小者 == b 且 a != b，则 a > b。
# 兼容 macOS BSD sort（支持 -V）。
version_gt() {
    local a="$1"
    local b="$2"
    # 去前导 v/V
    a="${a#v}"; a="${a#V}"
    b="${b#v}"; b="${b#V}"
    # 空值或含明显非版本字符（仅允许数字与点）则保守判否
    [[ -z "$a" || -z "$b" ]] && return 1
    [[ "$a" =~ ^[0-9][0-9.]*$ ]] || return 1
    [[ "$b" =~ ^[0-9][0-9.]*$ ]] || return 1
    [[ "$a" == "$b" ]] && return 1
    local lowest
    lowest=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)
    [[ "$lowest" == "$b" ]]
}

# 比对本地与远端版本，设置全局：
#   REMOTE_LATEST      远端最新 tag（去前导 v）；取不到则为空
#   UPDATE_AVAILABLE   true / false
# 返回码：0=有新版本，1=无新版本或检查过程出错（网络失败等，静默不报错）。
check_for_update() {
    REMOTE_LATEST=""
    UPDATE_AVAILABLE=false
    local local_ver remote_ver
    local_ver=$(get_local_version)
    # 复用既有 github_latest_tag（已处理 GH_TOKEN/GITHUB_TOKEN 认证与失败返回空）
    remote_ver=$(github_latest_tag "$UPDATE_REPO")
    REMOTE_LATEST="$remote_ver"
    if [[ -n "$remote_ver" ]] && version_gt "$remote_ver" "$local_ver"; then
        UPDATE_AVAILABLE=true
        return 0
    fi
    return 1
}

# 若有更新则打印一行醒目提示（仅提示，不自动改）。
# 若 UPDATE_AVAILABLE 未设置，先调用 check_for_update（容错：失败不打印）。
print_update_hint() {
    if [[ -z "${UPDATE_AVAILABLE:-}" ]]; then
        check_for_update 2>/dev/null || true
    fi
    if [[ "${UPDATE_AVAILABLE:-}" == "true" ]]; then
        warn "[更新提示] 检测到新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST}"
        warn "    运行 ./install.sh update 一键更新（会先确认，不会静默改动）"
    fi
}

# 安全自更新：检查前置条件 → yes_no 确认 → git pull。
# 任何不安全条件都拒绝执行并提示，绝不静默改动本地仓库。
# 返回码：0=更新成功（或已是最新），1=用户拒绝或不满足安全条件。
do_self_update() {
    cd "${SCRIPT_DIR:-.}" 2>/dev/null || { error "无法进入仓库目录"; return 1; }

    # 1) 必须是 git 仓库
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        error "当前目录不是 git 仓库（可能是直接下载的压缩包）。"
        info "请重新克隆：git clone https://github.com/${UPDATE_REPO}.git"
        return 1
    fi

    # 2) 必须有 origin 远端
    if ! git remote get-url origin >/dev/null 2>&1; then
        error "未配置 origin 远端，无法执行 git pull。"
        info "请手动添加远端或从 ${UPDATE_REPO} 重新克隆。"
        return 1
    fi

    # 3) 工作区必须干净（无未提交改动），避免 pull 覆盖本地修改
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        error "工作区有未提交改动，为安全起见拒绝自动 pull。"
        info "请先 commit 或 stash 本地改动后重试：./install.sh update"
        return 1
    fi

    # 4) detached HEAD 警告（main 分支才适合 pull）
    if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
        warn "当前处于 detached HEAD 状态，git pull 可能无意义。"
        if ! yes_no "仍要尝试更新？"; then
            info "已取消。请切到 main 分支：git checkout main && git pull"
            return 1
        fi
    fi

    # 先查询是否有新版本（取 REMOTE_LATEST 用于提示）
    check_for_update 2>/dev/null || true
    local target="${REMOTE_LATEST:-最新}"
    info "将执行 git pull 更新到 ${target}（origin: $(git remote get-url origin)）"
    if ! yes_no "确认执行 git pull 更新？"; then
        info "已取消更新。"
        return 1
    fi

    info "正在拉取更新..."
    if git pull --ff-only origin 2>/dev/null; then
        local new_ver
        new_ver=$(get_local_version)
        success "更新完成，当前版本：${new_ver}"
        return 0
    else
        error "git pull 失败（可能是冲突或网络问题）。"
        info "请手动执行：git pull --ff-only origin"
        return 1
    fi
}

# ---------------- 服务管理封装（systemd / launchd 双平台） ----------------
# service_is_active <systemd_name> <launchd_label>
service_is_active() {
    local sd_name="$1"
    local ld_label="$2"
    if [[ "$OS_TYPE" == "linux" ]]; then
        systemctl is-active --quiet "$sd_name" 2>/dev/null
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl list 2>/dev/null | grep -q "$ld_label"
    else
        return 1
    fi
}

# service_stop <systemd_name> <plist_path>
service_stop() {
    local sd_name="$1"
    local plist_path="$2"
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop "$sd_name" 2>/dev/null || true
        sudo systemctl disable "$sd_name" 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$plist_path" 2>/dev/null || true
    fi
}

# service_start <systemd_name> <plist_path>
# Linux: enable --now；macOS: bootstrap（失败回退 load）
service_start() {
    local sd_name="$1"
    local plist_path="$2"
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl daemon-reload
        sudo systemctl enable --now "$sd_name"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if sudo launchctl bootstrap system "$plist_path" 2>/dev/null; then
            return 0
        fi
        sudo launchctl load "$plist_path" 2>/dev/null || true
    fi
}

# ---------------- Dry-run 模式 ----------------
# 设置 UNIX_SCRIPT_DRY_RUN=1 或传入 --dry-run 启用。
# 启用后，所有 sudo/pkg_install/service 操作仅打印不执行。
UNIX_SCRIPT_DRY_RUN="${UNIX_SCRIPT_DRY_RUN:-0}"

# dry_run_exec <描述> <命令...>
# dry-run 模式打印命令，否则执行。
dry_run_exec() {
    local desc="$1"; shift
    if [[ "$UNIX_SCRIPT_DRY_RUN" == "1" ]]; then
        info "[dry-run] $desc: $*"
        return 0
    fi
    "$@"
}

# dry_run_sudo <描述> <命令...>
# dry-run 模式打印 sudo 命令，否则执行。
dry_run_sudo() {
    local desc="$1"; shift
    if [[ "$UNIX_SCRIPT_DRY_RUN" == "1" ]]; then
        info "[dry-run] $desc: sudo $*"
        return 0
    fi
    sudo "$@"
}

# ---------------- 交互工具 ----------------
# yes_no <prompt>  -> 输入 y/Y 返回 0，否则 1
yes_no() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N]: " -n 1 reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}
