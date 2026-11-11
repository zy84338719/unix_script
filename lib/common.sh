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

# ---------------- shellkit：唯一的基础库入口 ----------------
# 用自定位而不是 $SCRIPT_DIR：模块脚本 source 本文件时 $SCRIPT_DIR 是模块目录。
_UXS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_UXS_ROOT="$(cd "$_UXS_COMMON_DIR/.." &>/dev/null && pwd)"
# 标记**不导出**：shellkit 的 bootstrap 会 export SK_VERSION，用它当「已加载」的
# 判据会让子进程（模块脚本、install.sh 的子进程）以为库已就位而跳过 bootstrap，
# 于是能力函数全缺（os_name: command not found）。
if [ -z "${_UXS_SHELLKIT_LOADED:-}" ]; then
    source "$_UXS_ROOT/vendor/shellkit/lib/bootstrap.sh"
    _UXS_SHELLKIT_LOADED=1
fi

# unix_script 自己的约定层（能力一律来自 shellkit，这里只做口径映射）：
#   uxs_platform.sh —— 平台/架构/包管理检测落成全局变量；缺命令/认不出包管理器的文案与退出码
#   uxs_status.sh   —— 把 unix_script 的 UXS_STATUS_MODE 映射到 shellkit 的 SHELLKIT_STATUS_MODE
source "$_UXS_COMMON_DIR/uxs_platform.sh"
source "$_UXS_COMMON_DIR/uxs_status.sh"

# i18n 域配置：unix_script 自己的文案走 unix_script 域
source "$_UXS_COMMON_DIR/uxs_i18n.sh"
uxs_i18n_init "$_UXS_ROOT"


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


# 比对本地与远端版本，设置全局：
#   REMOTE_LATEST      远端最新 tag（去前导 v）；取不到则为空
#   UPDATE_AVAILABLE   true / false
# 返回码：0=有新版本，1=无新版本或检查过程出错（网络失败等，静默不报错）。
check_for_update() {
    REMOTE_LATEST=""
    UPDATE_AVAILABLE=false
    local local_ver remote_ver
    local_ver=$(get_local_version)
    # 复用既有 http_github_latest_tag（已处理 GH_TOKEN/GITHUB_TOKEN 认证与失败返回空）
    remote_ver=$(http_github_latest_tag "$UPDATE_REPO")
    REMOTE_LATEST="$remote_ver"
    if [[ -n "$remote_ver" ]] && ver_gt "$remote_ver" "$local_ver"; then
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
# macOS 分支用 sudo -n：status 查询绝不弹密码——sudo 凭据已缓存则真查，
# 否则静默失败（按未运行处理）；安装/停止路径的 service_start/stop 才允许提示。
service_is_active() {
    local sd_name="$1"
    local ld_label="$2"
    if [[ "$OS_TYPE" == "linux" ]]; then
        systemctl is-active --quiet "$sd_name" 2>/dev/null
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        # 不用 `| grep -q`：grep 命中即退会给上游 SIGPIPE(141)，pipefail 下整条管道非 0，
        # 会把「已运行」误判成「未运行」。先把输出收进变量，再用读完整个输入的 grep 匹配。
        local ld_list
        ld_list=$(sudo -n launchctl list 2>/dev/null) || ld_list=""
        printf '%s\n' "$ld_list" | grep "$ld_label" >/dev/null
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

# _uxs_os_type — 确保 OS_TYPE 已初始化；未初始化时内联 uname 判定。
# 刻意不调 detect_os()：部分模块（如 wireguard）以自有实现遮蔽了同名函数，
# 且其版本对 apk/pacman/zypper 系统会 exit 1，函数内 exit 无法被 || true 拦截。
_uxs_os_type() {
    if [[ -n "${OS_TYPE:-}" ]]; then
        return 0
    fi
    case "$(uname -s)" in
        Linux)  OS_TYPE="linux"  ;;
        Darwin) OS_TYPE="darwin" ;;
        *)      OS_TYPE="unknown" ;;
    esac
}

# uxs_svc <action> <unit>... — systemd 服务动作封装（Linux-only）。
# action: start|stop|restart|reload|enable|disable|enable-now|disable-now|
#         daemon-reload|is-active|is-enabled|list-unit-files
# 写类动作走 dry_run_sudo（--dry-run 下仅打印）；is-active/is-enabled/list-unit-files
# 为只读直跑。daemon-reload 无 unit 参数，其余 action 缺 unit 报错。非 Linux 返回 1。
# 与 service_start/stop/is_active 并存：那组是 systemd+launchd 双平台签名，
# Linux-only 模块用本函数，签名更简单。
uxs_svc() {
    local action="$1"; shift
    if [[ "$action" != "daemon-reload" ]] && [[ $# -lt 1 ]]; then
        error "uxs_svc: 缺少 unit 参数" >&2
        return 1
    fi
    _uxs_os_type
    if [[ "${OS_TYPE:-}" != "linux" ]]; then
        # 走 stderr：机器模式（UXS_STATUS_MODE=machine）的 stdout 必须保持 STATE= 首行契约
        warn "uxs_svc 仅支持 systemd（Linux），当前：${OS_TYPE:-unknown}" >&2
        return 1
    fi
    case "$action" in
        is-active)       systemctl is-active --quiet "$@" ;;
        is-enabled)      systemctl is-enabled "$@" ;;
        list-unit-files) systemctl list-unit-files "$@" ;;
        daemon-reload)   dry_run_sudo "systemctl daemon-reload" systemctl daemon-reload ;;
        start|stop|restart|reload|enable|disable)
            dry_run_sudo "systemctl $action" systemctl "$action" "$@" ;;
        enable-now)  dry_run_sudo "systemctl enable --now" systemctl enable --now "$@" ;;
        disable-now) dry_run_sudo "systemctl disable --now" systemctl disable --now "$@" ;;
        *)          error "uxs_svc: 未知 action：$action" >&2; return 1 ;;
    esac
}

# install_systemd_unit <unit-name> — 从 stdin 读 unit 内容写入 /etc/systemd/system/
# 并 daemon-reload。用法：
#     install_systemd_unit myapp.service <<EOF
#     [Unit]
#     ...
#     EOF
# heredoc 引号语义（变量展开与否）由调用方决定；dry-run 下仅打印不写入；
# 写入或 daemon-reload 失败返回非 0；非 Linux 告警（stderr）返回 1。
install_systemd_unit() {
    local unit="$1"
    if [[ -z "$unit" ]]; then
        error "install_systemd_unit: 缺少 unit 名参数" >&2
        return 1
    fi
    _uxs_os_type
    if [[ "${OS_TYPE:-}" != "linux" ]]; then
        warn "install_systemd_unit 仅支持 systemd（Linux），当前：${OS_TYPE:-unknown}" >&2
        return 1
    fi
    local target="/etc/systemd/system/$unit"
    # 真跑时 >/dev/null 抑制 tee 的内容回显；dry-run 下该重定向会连
    # 提示一起吞掉，故 dry-run 分支单独打印。
    if [[ "$UNIX_SCRIPT_DRY_RUN" == "1" ]]; then
        info "[dry-run] 写入 $target: sudo tee $target"
    else
        sudo tee "$target" >/dev/null
    fi
    uxs_svc daemon-reload
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
    # dry-run 顺带压制 brew auto-update：纯网络副作用（更新 tap）违背预览语义且拖慢执行
    export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
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


