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

# ---------------- 网络超时 ----------------
# 所有对外 curl 统一带超时，弱网下不阻塞菜单启动。
# 可用环境变量覆盖：UXS_CURL_TIMEOUT（max-time 秒）、UXS_CURL_CONNECT_TIMEOUT（connect 秒）。
UXS_CURL_TIMEOUT_ARGS=(
    "--connect-timeout" "${UXS_CURL_CONNECT_TIMEOUT:-5}"
    "--max-time" "${UXS_CURL_TIMEOUT:-10}"
)

# ---------------- 调试输出开关 ----------------
# UXS_DEBUG=1 时，库内原本静默的 stderr（2>/dev/null）改为透出到终端，
# 便于排查网络/解析失败。默认 0（静默，保持输出整洁）。
UXS_DEBUG="${UXS_DEBUG:-0}"
# uxs_stderr — 返回 stderr 重定向目标：debug 时 /dev/stderr，否则 /dev/null。
# 用法：cmd 2>"$(uxs_stderr)"
uxs_stderr() {
    if [[ "$UXS_DEBUG" == "1" ]]; then
        echo "/dev/stderr"
    else
        echo "/dev/null"
    fi
}

# ---------------- 打印函数（统一命名：info/success/warn/error/header/menu） ----------------
info()    { echo -e "${BLUE}[INFO]${NC} ${1:-}"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} ${1:-}"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} ${1:-}"; }
error()   { echo -e "${RED}[ERROR]${NC} ${1:-}"; }
header()  { echo -e "${CYAN}${1:-}${NC}"; }
menu()    { echo -e "${PURPLE}${1:-}${NC}"; }

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
    # 归一化小写形式（ARCH_TYPE 历史值为 x86_64/ARM64/ARMv7 大小写不一，下游匹配易踩坑）。
    # 新代码建议用 ARCH_TYPE_LOWER（统一小写：x86_64/arm64/armv7）；ARCH_TYPE 保留以兼容现有模块。
    ARCH_TYPE_LOWER="$(echo "$ARCH_TYPE" | tr '[:upper:]' '[:lower:]')"
}

# ---------------- 发行版识别 ----------------
# 读取 os-release 风格文件的字段值：_osr_field <文件> <KEY>（值可带或不带引号）。
# 文件为空/不可读时静默返回空；管道接 || true，防止 set -euo pipefail 环境下
# （如 install.sh）因 sed 对缺失文件报错而中止整个脚本。
_osr_field() {
    [[ -n "${1:-}" && -r "$1" ]] || return 0
    sed -n "s/^$2=[\"\']\{0,1\}\([^\"\']*\)[\"\']\{0,1\}\$/\1/p" "$1" 2>/dev/null | head -1 || true
}

# 发行版识别：读取 /etc/os-release，设置全局变量：
#   DISTRO_ID          小写发行版 ID（ubuntu / debian / centos / kylin / uos / openeuler …）
#   DISTRO_VERSION_ID  版本号（22.04 / 10 / 20 / 24.03 …）
#   DISTRO_NAME        人类可读名称（PRETTY_NAME，缺省回退 NAME）
#   DISTRO_FAMILY      包系族：debian | rhel | suse | arch | alpine | unknown
# 两种模式：
#   - 主机模式（不传参）：族判定以「实际可用的包管理器」为准、ID/ID_LIKE 词表兜底。
#     本库 pkg_install/pkg_remove 均按包管理器分发，实测最不易误判，且能正确区分
#     麒麟/统信的双形态（服务器版=RPM 系、桌面版=Deb 系）。
#   - 文件模式（显式传 os-release 路径，测试/预检用）：跳过包管理器实测，
#     纯按该文件的 ID_LIKE → ID 词表分类，跨平台结果一致。
# 恒返回 0；识别失败时 DISTRO_ID 为空、DISTRO_FAMILY=unknown，由调用方决定如何提示。
detect_distro() {
    local rel_file="${1:-}"
    local host_mode=0
    if [[ -z "$rel_file" ]]; then
        host_mode=1
        for rel_file in /etc/os-release /usr/lib/os-release; do
            [[ -r "$rel_file" ]] && break
            rel_file=""
        done
    fi

    DISTRO_ID=""
    DISTRO_VERSION_ID=""
    DISTRO_NAME=""
    DISTRO_FAMILY="unknown"

    if [[ -n "$rel_file" && -r "$rel_file" ]]; then
        DISTRO_ID="$(_osr_field "$rel_file" ID | tr '[:upper:]' '[:lower:]')"
        DISTRO_VERSION_ID="$(_osr_field "$rel_file" VERSION_ID)"
        DISTRO_NAME="$(_osr_field "$rel_file" PRETTY_NAME)"
        [[ -z "$DISTRO_NAME" ]] && DISTRO_NAME="$(_osr_field "$rel_file" NAME)"
    fi

    # 族判定 ①：主机模式先按包管理器实测
    if [[ "$host_mode" == 1 ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            DISTRO_FAMILY="debian"
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            DISTRO_FAMILY="rhel"
        elif command -v zypper >/dev/null 2>&1; then
            DISTRO_FAMILY="suse"
        elif command -v pacman >/dev/null 2>&1; then
            DISTRO_FAMILY="arch"
        elif command -v apk >/dev/null 2>&1; then
            DISTRO_FAMILY="alpine"
        fi
    fi

    # 族判定 ②：ID_LIKE 词表（文件模式 / 实测无已知包管理器时的依据）
    if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
        local id_like
        id_like="$(_osr_field "$rel_file" ID_LIKE | tr '[:upper:]' '[:lower:]')"
        case "$id_like" in
            *debian*|*ubuntu*|*mint*)                         DISTRO_FAMILY="debian" ;;
            *rhel*|*fedora*|*centos*|*euler*|*anolis*|*amzn*) DISTRO_FAMILY="rhel" ;;
            *suse*)                                           DISTRO_FAMILY="suse" ;;
            *arch*|*manjaro*)                                 DISTRO_FAMILY="arch" ;;
            *alpine*)                                         DISTRO_FAMILY="alpine" ;;
        esac
    fi
    # 族判定 ③：ID 词表兜底。注意：kylin 有意不入表——其服务器版基于 RHEL/CentOS、
    # 桌面版基于 Ubuntu，硬编码任何一个族都会误判一半场景，交由 ①实测/②ID_LIKE 决定。
    if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
        case "$DISTRO_ID" in
            debian|ubuntu|deepin|openkylin|uos|linuxmint|kali) DISTRO_FAMILY="debian" ;;
            centos|rhel|rocky|almalinux|fedora|amzn|ol|openeuler|anolis) DISTRO_FAMILY="rhel" ;;
            opensuse*|sles)                          DISTRO_FAMILY="suse" ;;
            arch|manjaro)                            DISTRO_FAMILY="arch" ;;
            alpine)                                  DISTRO_FAMILY="alpine" ;;
        esac
    fi
    return 0
}

# 读 os-release 风格文件的字段值：uxs_os_release <KEY> [file]
# file 缺省依次尝试 /etc/os-release、/usr/lib/os-release；均不可读返回空。
# 供模块替代手写 `$(. /etc/os-release && echo "$ID")`；恒返回 0。
uxs_os_release() {
    local key="$1" rel_file="${2:-}"
    if [[ -z "$rel_file" ]]; then
        for rel_file in /etc/os-release /usr/lib/os-release; do
            [[ -r "$rel_file" ]] && break
            rel_file=""
        done
    fi
    _osr_field "$rel_file" "$key"
}

# ---------------- 桌面环境检测 ----------------
# 设置全局变量：
#   DESKTOP_ENV  ukui|dde|gnome|kde|xfce|mate|cinnamon|lxqt|budgie|none
#   IS_DESKTOP   1=检测到桌面环境（麒麟桌面 UKUI / 统信·深度 DDE 等），0=无
# 识别线索：① 会话环境变量（XDG_CURRENT_DESKTOP / XDG_SESSION_DESKTOP / DESKTOP_SESSION）；
# ② 桌面会话进程/启动器是否安装（SSH/容器里也能探到已装未启动的桌面）。
# 用于让服务类模块在桌面系统上做差异化处理（如桌面系统常无 systemd 服务、
# 代理/网络管理方式不同），并供 doctor / CI 验证展示。
detect_desktop() {
    DESKTOP_ENV="none"
    IS_DESKTOP=0
    local clues="" v vlow de_bin
    # 兼容 macOS bash 3.2：不用 ${v,,}（bash4+），统一用 tr 转小写
    for v in "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}"; do
        [[ -n "$v" ]] || continue
        vlow="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
        clues="$clues $vlow"
    done
    for de_bin in ukui-session kwin_x11 startdde dde-desktop gnome-session gnome-shell \
                  plasmashell startplasma-x11 xfce4-session mate-session cinnamon-session lxsession; do
        command -v "$de_bin" >/dev/null 2>&1 && clues="$clues $de_bin"
    done
    case "$clues" in
        *ukui*)      DESKTOP_ENV="ukui" ;;   # 麒麟桌面版
        *dde*|*deepin*) DESKTOP_ENV="dde" ;; # 统信 UOS / 深度 deepin 桌面（startdde 含 dde 已覆盖）
        *plasma*|*kde*)  DESKTOP_ENV="kde" ;;
        *gnome*)     DESKTOP_ENV="gnome" ;;
        *xfce*)      DESKTOP_ENV="xfce" ;;
        *mate*)      DESKTOP_ENV="mate" ;;
        *cinnamon*)  DESKTOP_ENV="cinnamon" ;;
        *lxqt*|*lxsession*) DESKTOP_ENV="lxqt" ;;
        *budgie*)    DESKTOP_ENV="budgie" ;;
    esac
    [[ "$DESKTOP_ENV" != "none" ]] && IS_DESKTOP=1
    return 0
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
        # DEBIAN_FRONTEND=noninteractive：容器/极简镜像里 tzdata 等包会弹 debconf
        # 交互（时区询问），无 TTY 时可能挂死（CI 与脚本场景必须避免）
        apt-get) $sudo_prefix env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
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
        # DEBIAN_FRONTEND=noninteractive：理由同 pkg_install（避免 debconf 交互挂死）
        apt-get) $sudo_prefix env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y "$@" ;;
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
    # dry-run 预览不实际执行，不需要真实 sudo 凭据（配合下方 sudo 遮蔽函数）
    if [[ "$UNIX_SCRIPT_DRY_RUN" == "1" ]]; then
        info "[dry-run] 跳过 sudo 授权（预览模式不实际执行）"
        return 0
    fi
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
        ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
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
# 优先用 jq 解析 JSON（健壮，能区分空字段与解析失败）；无 jq 时回退 grep+sed
# （逐字节兼容旧实现，保留 v 前缀剥离）。失败（网络/限流/解析）静默返回空串。
github_latest_tag() {
    local repo="$1"
    local tag
    local auth=()
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -n "$token" ]]; then
        auth=(-H "Authorization: Bearer $token")
    fi
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    if command -v jq >/dev/null 2>&1; then
        tag=$(curl -fsSL "${UXS_CURL_TIMEOUT_ARGS[@]}" ${auth[@]+"${auth[@]}"} "$api_url" 2>"$(uxs_stderr)" \
              | jq -r '.tag_name // empty' 2>"$(uxs_stderr)" || true)
        tag="${tag#v}"; tag="${tag#V}"
    else
        tag=$(curl -fsSL "${UXS_CURL_TIMEOUT_ARGS[@]}" ${auth[@]+"${auth[@]}"} "$api_url" 2>"$(uxs_stderr)" \
              | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
    fi
    echo "$tag"
}

# 从 GitHub 最新 release 取匹配的资产下载 URL（取第一个匹配项）。
# github_release_asset_url <repo> <url-pattern>
#   <url-pattern>：作用于 browser_download_url 的正则（jq 分支用 test()，回退分支用 grep -E）。
# 优先 jq；无 jq 回退 grep+sed（替代脆弱的 cut -d'"' -f4 字段下标）。失败返回空串。
github_release_asset_url() {
    local repo="$1" pattern="$2"
    local auth=()
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    if command -v jq >/dev/null 2>&1; then
        curl -fsSL "${UXS_CURL_TIMEOUT_ARGS[@]}" ${auth[@]+"${auth[@]}"} "$api_url" 2>"$(uxs_stderr)" \
            | jq -r --arg p "$pattern" \
                '.assets[].browser_download_url | select(test($p))' 2>"$(uxs_stderr)" \
            | head -1 || true
    else
        curl -fsSL "${UXS_CURL_TIMEOUT_ARGS[@]}" ${auth[@]+"${auth[@]}"} "$api_url" 2>"$(uxs_stderr)" \
            | grep '"browser_download_url"' | grep -E "$pattern" | head -1 \
            | sed -E 's/.*"([^"]+)".*/\1/' || true
    fi
}

# 校验文件 SHA256。verify_sha256 <file> <expected-sha256>
# 跨平台：macOS/BSD 用 shasum -a 256，Linux 用 sha256sum。匹配返回 0，不匹配 1，无工具 2。
verify_sha256() {
    local file="$1" expected="$2"
    [[ -f "$file" ]] || return 1
    local actual
    if command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    else
        return 2
    fi
    [[ "$actual" == "$expected" ]]
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
    # 不用 `... | head -n1`：在 pipefail 下 head 提前关管道会触发上游 SIGPIPE。
    # 排序结果固定 2 行，用参数展开取首行即可。
    local sorted lowest
    sorted=$(printf '%s\n%s\n' "$a" "$b" | sort -V)
    lowest=${sorted%%$'\n'*}
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
        warn "[更新提示] 检测到新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST:-未知}"
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

# 安装 sudo 遮蔽函数——dry-run 全局拦截的关键。
# 各模块脚本都 source 本文件，source 时若已处 dry-run（子进程继承
# UNIX_SCRIPT_DRY_RUN），这里用同名 bash 函数遮蔽 sudo 二进制，使模块内
# 直接书写的 `sudo ...`（apt/systemd/写 /etc 等 root 操作）降级为打印。
# 顶层 install.sh 解析 --dry-run 后需显式调用一次（其 source 时还没解析到）。
uxs_install_sudo_shim() {
    sudo() {
        info "[dry-run] sudo $*"
        return 0
    }
}
if [[ "$UNIX_SCRIPT_DRY_RUN" == "1" ]]; then
    uxs_install_sudo_shim
fi

# ---------------- 交互工具 ----------------
# yes_no <prompt>  -> 输入 y/Y 返回 0，否则 1
yes_no() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N]: " -n 1 reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

# ---------------- status 输出契约 helper（UXS_STATUS_MODE 双轨）----------------
# 详见 docs/superpowers/specs/2026-08-07-status-contract-deps-profile-design.md 阶段 A。
# 人类模式（默认）：输出带颜色/emoji 的中文，向后兼容。
# 机器模式（UXS_STATUS_MODE=machine）：输出规范字段行，无颜色无 emoji。
#
# 规范状态码有限集：not_installed / installed:running / installed:stopped /
#                   installed / configured / not_configured / n/a

# emit_status <state> <human_msg>
# 人类模式：echo -e "$human_msg"（含颜色/emoji）
# 机器模式：printf 'STATE=%s\n' "$state"
emit_status() {
    local state="$1" human_msg="$2"
    if [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]; then
        printf 'STATE=%s\n' "$state"
    else
        echo -e "$human_msg"
    fi
}

# emit_version <version>
# 仅机器模式输出 VERSION= 行（人类模式版本已在状态消息里，不重复）
# 始终返回 0：模块 status 子命令必须退出 0，不能因 human 模式无输出而返回非零。
emit_version() {
    if [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]; then
        printf 'VERSION=%s\n' "$1"
    fi
}

# emit_extra <key=value>
# 仅机器模式输出 EXTRA= 行（人类模式的额外信息由模块自己 echo，并用 human 守卫包裹）
# 始终返回 0（同 emit_version）。
emit_extra() {
    if [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]; then
        printf 'EXTRA=%s\n' "$1"
    fi
}

# uxs_is_machine_mode — 供模块判断是否需用 human 守卫包裹纯人类辅助输出
# 返回：机器模式 0，人类模式 1（这是一个判断函数，返回值即其语义）。
uxs_is_machine_mode() {
    [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]
}
