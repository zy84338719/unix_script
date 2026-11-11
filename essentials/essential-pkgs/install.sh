#!/usr/bin/env bash
#
# essential-pkgs/install.sh
#
# 装机必备基础软件包一键安装。Linux（apt/dnf/yum）+ macOS（brew）。
# 覆盖日常运维与开发常用工具：网络、文本处理、压缩、监控、编辑等。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 通用必备工具（命令名）
ESSENTIAL_TOOLS=(curl wget git vim unzip zip tar gzip bzip2 htop tmux tree jq screen)
# 仅 Linux 的额外工具（命令名）
LINUX_EXTRA=(net-tools bind-utils sudo bash-completion ca-certificates gnupg lsof psmisc)

# 命令名 -> 包名的特殊映射（不同发行版/平台包名不同）
pkg_name_for() {
    local cmd="$1"
    case "$cmd" in
        bind-utils)
            # Debian 系叫 dnsutils；Arch/Alpine 叫 bind-tools；其他 bind-utils
            case "$PKG_MANAGER" in
                apt-get)   echo "dnsutils" ;;
                pacman)    echo "bind-tools" ;;
                apk)       echo "bind-tools" ;;
                *)         echo "bind-utils" ;;
            esac
            ;;
        gnupg)
            # RHEL 系包名是 gnupg2
            case "$PKG_MANAGER" in
                dnf|yum)   echo "gnupg2" ;;
                *)         echo "gnupg" ;;
            esac
            ;;
        *) echo "$cmd" ;;
    esac
}

# 开发工具组的包名（各发行版不同）
dev_tools_pkg() {
    case "$PKG_MANAGER" in
        apt-get) echo "build-essential" ;;
        # 用组：@development tools（单独处理）
        dnf|yum) echo "" ;;
        pacman)  echo "base-devel" ;;
        apk)     echo "build-base" ;;
        zypper)  echo "patterns-devel_basis" ;;
        *)       echo "" ;;
    esac
}

install_pkgs() {
    detect_os
    require_sudo
    info "$(_t '📦 Installing the essential tools')"

    # macOS：用 brew（brew 本身不需 sudo）
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! os_has_cmd brew; then
            error "macOS $(_t 'Homebrew is required. Install it first: https://brew.sh/')"
            exit 1
        fi
        info "$(_tf 'Installing via Homebrew: %s' "${ESSENTIAL_TOOLS[*]}")"
        brew install "${ESSENTIAL_TOOLS[@]}"
        success "macOS $(_t 'The essential tools installation is complete')"
        return
    fi

    detect_pkg_manager
    ensure_epel
    local missing_pkgs=()
    local t pkg

    # 逐个安装（容错：个别包缺失不中断）
    info "$(_tf 'Installing the essential tools (package manager: %s)...' "${PKG_MANAGER}")"
    for t in "${ESSENTIAL_TOOLS[@]}" "${LINUX_EXTRA[@]}"; do
        if ! os_has_cmd "$t" 2>/dev/null; then
            pkg=$(pkg_name_for "$t")
            if ! pkg_install "$pkg" >/dev/null 2>&1; then
                missing_pkgs+=("$pkg")
            fi
        fi
    done

    # 开发工具组
    case "$PKG_MANAGER" in
        dnf|yum)
            # dnf/yum 用组安装
            local sudo_prefix=""; [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
            $sudo_prefix "$PKG_MANAGER" groupinstall -y "Development Tools" 2>/dev/null || missing_pkgs+=("Development Tools")
            ;;
        *)
            pkg=$(dev_tools_pkg)
            if [[ -n "$pkg" ]]; then
                pkg_install "$pkg" >/dev/null 2>&1 || missing_pkgs+=("$pkg")
            fi
            ;;
    esac

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        warn "$(_tf 'The following packages could not be installed: %s' "${missing_pkgs[*]}")"
    fi
    success "$(_t 'The essential tools have been installed')"
    echo
    info "$(_tf 'The installed tools: %s' "${ESSENTIAL_TOOLS[*]}")"
    [[ "$OS_TYPE" == "linux" ]] && echo "         ${LINUX_EXTRA[*]} build-essential"
}

# 卸载（通常不建议卸载必备工具，这里提供按需移除个别包的入口）
uninstall_pkgs() {
    detect_os
    warn "$(_t 'Uninstalling the essential tools is usually not recommended (other programs may depend on them).')"
    warn "$(_t 'If you really need to uninstall a specific package, remove it manually with the system package manager, for example:')"
    echo "  Debian/Ubuntu: sudo apt-get remove <$(_t 'package name>')"
    echo "  RHEL/CentOS:   sudo dnf/yum remove <$(_t 'package name>')"
    echo "  macOS:         brew uninstall <$(_t 'package name>')"
}

status_pkgs() {
    detect_os
    local missing=() t
    for t in "${ESSENTIAL_TOOLS[@]}"; do
        os_has_cmd "$t" 2>/dev/null || missing+=("$t")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        uxs_emit_status "installed" "${GREEN}$(_t '✅ All the essential tools are installed')${NC}"
    else
        uxs_emit_status "not_installed" "${YELLOW}$(_tf '⚠️  Missing: %s' "${missing[*]}")${NC}"
        # 缺少的工具列表：逗号分隔，机器模式 EXTRA 行
        local missing_csv
        missing_csv=$(IFS=,; echo "${missing[*]}")
        uxs_emit_extra "missing=$missing_csv"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install the essential tool packages (curl/wget/git/vim/htop/tmux/jq/development tools etc.)')
  status      $(_t 'Check whether all the essential tools are installed')
  uninstall   $(_t 'Description (uninstalling is not recommended, the manual command is given)')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_pkgs ;;
        uninstall) uninstall_pkgs ;;
        status)    status_pkgs ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
