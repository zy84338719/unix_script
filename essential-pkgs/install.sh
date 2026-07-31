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
        # bind-utils 在 Debian 系叫 dnsutils
        bind-utils)
            if command -v apt-get >/dev/null 2>&1; then echo "dnsutils"; else echo "bind-utils"; fi
            ;;
        bash-completion) echo "bash-completion" ;;
        net-tools) echo "net-tools" ;;
        *) echo "$cmd" ;;
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
    local all_pkgs=()
    local t
    for t in "${ESSENTIAL_TOOLS[@]}" "${LINUX_EXTRA[@]}"; do
        if ! command_exists "$t" 2>/dev/null; then
            all_pkgs+=("$(pkg_name_for "$t")")
        fi
    done

    # build-essential / 开发工具组
    case "$PKG_MANAGER" in
        apt-get) all_pkgs+=(build-essential) ;;
        dnf|yum) all_pkgs+=("@development tools") ;;
    esac

    if [[ ${#all_pkgs[@]} -eq 0 ]]; then
        success "所有必备工具均已安装"
        return
    fi

    info "将安装：${all_pkgs[*]}"
    case "$PKG_MANAGER" in
        apt-get)
            sudo apt-get update -y
            sudo apt-get install -y "${all_pkgs[@]}"
            ;;
        dnf|yum)
            # RHEL/CentOS 系：先确保 EPEL（htop/screen 等在 EPEL 仓库）
            if ! rpm -q epel-release >/dev/null 2>&1; then
                info "安装 EPEL 仓库（提供 htop/screen 等）..."
                sudo "$PKG_MANAGER" install -y epel-release 2>/dev/null || warn "EPEL 安装失败，部分包可能不可用"
                sudo "$PKG_MANAGER" makecache 2>/dev/null || true
            fi
            # 逐包安装并容错：个别包在当前仓库/EPEL 仍缺失时，记录但不中断
            local missing_pkgs=()
            for p in "${all_pkgs[@]}"; do
                if ! sudo "$PKG_MANAGER" install -y "$p" >/dev/null 2>&1; then
                    missing_pkgs+=("$p")
                    warn "包 '$p' 安装失败（可能需要额外仓库），已跳过"
                fi
            done
            if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
                warn "以下包未能安装：${missing_pkgs[*]}"
            fi
            ;;
        *)       error "不支持的包管理器"; exit 1 ;;
    esac
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
