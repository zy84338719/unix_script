#!/usr/bin/env bash
#
# 能力函数转发门面（Stage 1 过渡层）。
#
# 为什么有这一层：Stage 1 不动 78 个模块脚本，它们调用的是 lib/common.sh 里的
# 旧函数名。直接删掉旧名会让全部模块崩，所以这里保留同名函数，转发到 shellkit。
#
# Stage 3 把 78 个模块逐个迁到 shellkit API 之后，这一层整体删除。
#
# 转发要求：**输出与退出码逐字等价**。unix_script 的行为快照门禁
#（tools/check_snapshot.sh）与单测（tests/unit_*.sh）负责证明这一点。
#
# 两条纪律：
#   1. 只换**能力**函数，不换**呈现**函数 —— info/success/warn/error/header/menu
#      留在 unix_script（Stage 3 再一起迁）。
#   2. 凡是转发后会改变输出或退出码的，一律不转发（见下方 uxs_svc / install_systemd_unit
#      的说明：它们绑定 unix_script 自己的 dry-run 文案与平台护栏）。
#
# 幂等保护
if [[ -n "${_UXS_COMPAT_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_UXS_COMPAT_LOADED=1

# ---------- 机器模式旋钮映射 ----------
# shellkit 只认 SHELLKIT_STATUS_MODE；unix_script 的旋钮名由门面映射
# （通用库不该知道调用方的旋钮名）。
uxs_status_sync() {
    export SHELLKIT_STATUS_MODE="${UXS_STATUS_MODE:-human}"
}

# ---------- 平台 / 架构 ----------

# detect_os —— 设置 OS_TYPE / OS_KERNEL（兼容既有全局变量口径）
detect_os() {
    OS_KERNEL="$(uname -s)"
    OS_TYPE="$(os_name)"
    case "$OS_TYPE" in
        linux|darwin) return 0 ;;
        *)
            error "不支持的操作系统：$OS_KERNEL"
            exit 1
            ;;
    esac
}

# detect_arch —— 设置 ARCH_TYPE / ARCH_TYPE_LOWER
# 架构名的历史口径（ARM64 / ARMv7）是 unix_script 自己的约定，
# shellkit 的 os_arch 只给 x86_64 / aarch64 / other —— 其余按 uname -m 原样透传。
detect_arch() {
    local arch
    arch="$(os_arch)"
    case "$arch" in
        x86_64)  ARCH_TYPE="x86_64" ;;
        aarch64) ARCH_TYPE="ARM64" ;;
        other)
            arch="$(uname -m)"
            case "$arch" in
                aarch64|arm64) ARCH_TYPE="ARM64" ;;
                armv7l)        ARCH_TYPE="ARMv7" ;;
                *)             ARCH_TYPE="$arch" ;;
            esac
            ;;
        *)       ARCH_TYPE="$arch" ;;
    esac
    ARCH_TYPE_LOWER="$(printf '%s' "$ARCH_TYPE" | tr '[:upper:]' '[:lower:]')"
}

# detect_distro —— 设置 DISTRO_ID / DISTRO_VERSION_ID / DISTRO_NAME / DISTRO_FAMILY
detect_distro() {
    DISTRO_ID="$(os_distro_id "${1:-}")"
    DISTRO_VERSION_ID="$(os_release_field VERSION_ID "${1:-}")"
    DISTRO_NAME="$(os_distro_name "${1:-}")"
    DISTRO_FAMILY="$(os_distro_family "${1:-}")"
    return 0
}

# detect_desktop —— 设置 DESKTOP_ENV / IS_DESKTOP
detect_desktop() {
    DESKTOP_ENV="$(os_desktop_env)"
    if [[ "$DESKTOP_ENV" != "none" ]]; then IS_DESKTOP=1; else IS_DESKTOP=0; fi
    return 0
}

# ---------- 包管理 ----------

# detect_pkg_manager —— 设置 PKG_MANAGER（apt-get/dnf/yum/zypper/pacman/apk/brew）
detect_pkg_manager() {
    PKG_MANAGER="$(os_pkg_manager_full 2>/dev/null)" || return 1
    return 0
}

pkg_install()   { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_install_root "$@"; }
pkg_remove()    { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_remove_root "$@"; }
pkg_update()    { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_update_root; }
pkg_installed() { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_installed "$@"; }

# ---------- 命令存在性 ----------

command_exists() { os_has_cmd "$1"; }

# check_commands —— 缺命令时报同样的中文并 exit 1（呈现层留在 unix_script）
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

# ---------- 校验 / 版本 ----------

verify_sha256() { net_verify "$@"; }

# version_gt —— 转给 shellkit 的分段比较。
# 已知口径差：缺段当 0（1.0 与 1.0.0 判等），而旧的 sort -V 认为 1.0 < 1.0.0。
version_gt()    { ver_gt "$@"; }

# ---------- GitHub ----------

github_latest_tag()        { http_github_latest_tag "$@"; }
github_release_asset_url() { http_github_release_asset "$@"; }

# ---------- 超时 ----------

uxs_with_timeout()      { run_timeout "$@"; }
uxs_func_with_timeout() { run_func_timeout "$@"; }

# ---------- 状态契约 ----------

emit_status()  { uxs_status_sync; status_emit "$@"; }
emit_version() { uxs_status_sync; status_version "$@"; }
emit_extra()   { uxs_status_sync; status_extra "$@"; }
uxs_is_machine_mode() { uxs_status_sync; status_is_machine; }

# ---------- os-release 字段 ----------
# uxs_os_release KEY [FILE] —— 读 os-release 风格文件的字段值
# shellkit 的 os_release_field 参数顺序是（KEY, [FILE]），这里保持 unix_script 的原签名。
uxs_os_release() { os_release_field "$1" "${2:-}"; }
