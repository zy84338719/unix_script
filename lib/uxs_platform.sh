#!/usr/bin/env bash
#
# lib/uxs_platform.sh —— unix_script 的平台与包管理适配层
#
# Stage 1 时这一层叫 uxs_compat.sh：它把 unix_script 的旧函数名**转发**到 shellkit，
# 让 78 个模块在迁移完成前不用改。Stage 3 把模块迁到 shellkit API 之后，转发层
# 就删掉了 —— 剩下的这些函数不是「shellkit 能力的替身」，而是 unix_script 自己的约定：
#
#   · shellkit 的能力函数一律「结果返回到 stdout」，unix_script 的脚本读的是全局变量
#     （OS_TYPE / ARCH_TYPE / PKG_MANAGER / ...）—— 适配层负责把前者落成后者。
#   · 架构名怎么写（ARM64 / ARMv7）、缺命令时报什么文案、包管理器认不出来时退出码是几，
#     都是 unix_script 自己的口径 —— 通用库不该知道这些，就留在这里。
#
# 本文件不实现任何能力：每个函数都直接调用 shellkit 的能力函数。
#
# 幂等保护
if [[ -n "${_UXS_PLATFORM_LOADED:-}" ]]; then
    # 被 source 时 return 成功；直接执行时回退到 exit（shellcheck SC2317 误报）
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
_UXS_PLATFORM_LOADED=1

# ---------------- 平台 / 架构 ----------------

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

# ---------------- 包管理 ----------------

# detect_pkg_manager —— 设置 PKG_MANAGER（apt-get/dnf/yum/zypper/pacman/apk/brew）
detect_pkg_manager() {
    PKG_MANAGER="$(os_pkg_manager_full 2>/dev/null)" || return 1
    return 0
}

# 下面四个是 unix_script 的包管理入口：能力来自 shellkit，认不出包管理器时的
# 文案与退出码是 unix_script 自己的口径（shellkit 那边是 log_error + 退出码 3）。
pkg_install()   { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_install_root "$@"; }
pkg_remove()    { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_remove_root "$@"; }
pkg_update()    { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_update_root; }
pkg_installed() { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_installed "$@"; }

# ---------------- 依赖检查 ----------------

# check_commands —— 缺命令时报同样的中文并 exit 1（呈现层留在 unix_script）
check_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! os_has_cmd "$cmd"; then
            missing+=("$cmd")
        fi
    done
    if ((${#missing[@]} > 0)); then
        error "缺少必要命令：${missing[*]}"
        error "请先安装后再运行本脚本。"
        exit 1
    fi
}
