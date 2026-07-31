#!/usr/bin/env bash
#
# essential-pkgs/install.sh
#
# 装机必备基础软件包一键安装。Linux（apt/dnf/yum）+ macOS（brew）。
# 覆盖日常运维与开发常用工具：网络、文本处理、压缩、监控、编辑等。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

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
        dnf|yum) echo "" ;;              # 用组：@development tools（单独处理）
        pacman)  echo "base-devel" ;;
        apk)     echo "build-base" ;;
        zypper)  echo "patterns-devel_basis" ;;
        *)       echo "" ;;
    esac
}

install_pkgs() {
    detect_os
    require_sudo
    info "📦 安装装机必备工具"

    # macOS：用 brew（brew 本身不需 sudo）
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! command_exists brew; then
            error "macOS 需要 Homebrew。请先安装：https://brew.sh/"
            exit 1
        fi
        info "通过 Homebrew 安装：${ESSENTIAL_TOOLS[*]}"
        brew install "${ESSENTIAL_TOOLS[@]}"
        success "macOS 必备工具安装完成"
        return
    fi

    detect_pkg_manager
    ensure_epel
    local missing_pkgs=()
    local t pkg

    # 逐个安装（容错：个别包缺失不中断）
    info "安装必备工具（包管理器：$PKG_MANAGER）..."
    for t in "${ESSENTIAL_TOOLS[@]}" "${LINUX_EXTRA[@]}"; do
        if ! command_exists "$t" 2>/dev/null; then
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
        warn "以下包未能安装：${missing_pkgs[*]}"
    fi
    success "装机必备工具安装完成"
    echo
    info "已安装工具：${ESSENTIAL_TOOLS[*]}"
    [[ "$OS_TYPE" == "linux" ]] && echo "         ${LINUX_EXTRA[*]} build-essential"
}

# 卸载（通常不建议卸载必备工具，这里提供按需移除个别包的入口）
uninstall_pkgs() {
    detect_os
    warn "通常不建议卸载装机必备工具（其他程序可能依赖它们）。"
    warn "如确需卸载个别包，请用系统包管理器手动移除，例如："
    echo "  Debian/Ubuntu: sudo apt-get remove <包名>"
    echo "  RHEL/CentOS:   sudo dnf/yum remove <包名>"
    echo "  macOS:         brew uninstall <包名>"
}

status_pkgs() {
    detect_os
    local missing=() t
    for t in "${ESSENTIAL_TOOLS[@]}"; do
        command_exists "$t" 2>/dev/null || missing+=("$t")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 必备工具已安装齐全${NC}"
    else
        echo -e "${YELLOW}⚠️  缺少：${missing[*]}${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装装机必备工具包（curl/wget/git/vim/htop/tmux/jq/开发工具 等）
  status      检查必备工具是否齐全
  uninstall   说明（不建议卸载，给出手动命令）
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
