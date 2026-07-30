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
    elif command -v brew >/dev/null 2>&1; then
        PKG_MANAGER="brew"
    else
        return 1
    fi
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

# 要求以非 root 身份运行、且具备 sudo 权限（与现有模块逻辑一致）
require_sudo() {
    if [[ $EUID -eq 0 ]]; then
        error "请不要使用 root 用户运行本脚本（需要普通用户 + sudo）。"
        exit 1
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
github_latest_tag() {
    local repo="$1"
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
          | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
    echo "$tag"
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

# ---------------- 交互工具 ----------------
# yes_no <prompt>  -> 输入 y/Y 返回 0，否则 1
yes_no() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N]: " -n 1 reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}
