#!/usr/bin/env bash
#
# restic/install.sh
#
# 安装与管理 Restic 备份工具。
# 支持 Linux（apt/dnf/yum 或 GitHub 二进制）与 macOS（Homebrew）。
#
# 子命令：
#   install           安装/更新 Restic
#   uninstall         卸载 Restic
#   status            查看状态
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

RESTIC_BIN="/usr/local/bin/restic"

# --- 检查已有安装 ---
handle_existing_installation() {
    if ! command_exists restic; then
        return 0
    fi
    local current_version
    current_version=$(restic version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
    warn "$(_tf 'Restic detected (%s)' "${current_version}")"
    if ! yes_no "$(_t 'Continue and overwrite it with the latest version?')"; then
        info "$(_t 'The installation was cancelled')"
        exit 0
    fi
}

# --- 从 GitHub 下载二进制（Linux 备选） ---
install_from_github() {
    require_sudo
    check_commands curl

    info "$(_t 'Fetching the latest version info...')"
    local latest
    latest=$(github_latest_tag "restic/restic")
    if [[ -z "$latest" ]]; then
        error "$(_t 'Cannot fetch the latest version info, check the network connection')"
        exit 1
    fi
    success "$(_tf 'Latest version: v%s' "$latest")"

    # 确定架构后缀
    local arch_suffix
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)         arch_suffix="linux_amd64" ;;
        aarch64|arm64)  arch_suffix="linux_arm64" ;;
        armv7l)         arch_suffix="linux_arm" ;;
        *) error "$(_tf 'Unsupported architecture: %s' "$arch")"; exit 1 ;;
    esac

    local url="https://github.com/restic/restic/releases/download/v${latest}/restic_${latest}_${arch_suffix}.bz2"
    info "$(_tf 'Download URL: %s' "$url")"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    if ! curl -SL "$url" -o "$tmpdir/restic.bz2"; then
        error "$(_t 'Download failed')"
        exit 1
    fi

    info "$(_t 'Extracting...')"
    if ! bunzip2 "$tmpdir/restic.bz2"; then
        error "$(_t 'Extract failed, trying to install bzip2...')"
        pkg_install bzip2
        bunzip2 "$tmpdir/restic.bz2"
    fi

    sudo mv "$tmpdir/restic" "$RESTIC_BIN"
    sudo chmod 755 "$RESTIC_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$RESTIC_BIN"
    else
        sudo chown root:root "$RESTIC_BIN"
    fi

    rm -rf "$tmpdir"
    trap - EXIT
    success "$(_t 'The binary files are installed')"
}

# --- 安装 Restic ---
install_restic() {
    detect_os
    handle_existing_installation

    info "$(_t '🚀 Restic backup tool install script')"
    echo "=========================================="

    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS 优先 brew
        if command_exists brew; then
            info "$(_t 'Installing Restic via Homebrew...')"
            brew install restic
        else
            error "macOS $(_t 'requires Homebrew to be installed first: https://brew.sh/')"
            exit 1
        fi
    else
        # Linux：优先使用包管理器，失败则从 GitHub 下载
        detect_pkg_manager
        case "$PKG_MANAGER" in
            apt-get)
                info "$(_t 'Installing Restic via apt...')"
                require_sudo
                pkg_update
                if pkg_install restic; then
                    success "apt $(_t 'Installation complete')"
                else
                    warn "apt $(_t 'Installation failed, falling back to the GitHub binary...')"
                    install_from_github
                fi
                ;;
            dnf|yum)
                info "$(_tf 'Installing Restic via %s...' "$PKG_MANAGER")"
                require_sudo
                if pkg_install restic; then
                    success "$PKG_MANAGER $(_t 'Installation complete')"
                else
                    warn "$PKG_MANAGER $(_t 'Installation failed, falling back to the GitHub binary...')"
                    install_from_github
                fi
                ;;
            *)
                warn "$(_t 'The current package manager does not ship restic, downloading it from GitHub...')"
                install_from_github
                ;;
        esac
    fi

    if ! command_exists restic; then
        error "$(_t 'The restic command was not found after the install, check PATH')"
        exit 1
    fi

    local version
    version=$(restic version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown')")

    echo
    echo "=========================================="
    success "$(_t '🎉 Restic installation complete!')"
    echo
    info "$(_tf 'Version info: %s' "$version")"
    echo
    info "$(_t 'Getting started:')"
    echo "  # $(_t 'Initialize a local backup repository')"
    echo "  restic init --repo /path/to/backup-repo"
    echo
    echo "  # $(_t 'Back up a directory')"
    echo "  restic -r /path/to/backup-repo backup /home/user/docs"
    echo
    echo "  # $(_t 'List the backup snapshots')"
    echo "  restic -r /path/to/backup-repo snapshots"
    echo
    echo "  # $(_t 'Restore a file')"
    echo "  restic -r /path/to/backup-repo restore latest --target /tmp/restore"
    echo
    echo "  # $(_t 'Initialize a remote repository (S3 example)')"
    echo "  restic -r s3:s3.amazonaws.com/bucket-name init"
    echo
    info "$(_t 'More usage: https://restic.readthedocs.io/')"
}

# --- 卸载 Restic ---
uninstall_restic() {
    detect_os
    warn "$(_t 'About to uninstall Restic.')"
    if ! yes_no "$(_t 'Confirm uninstall?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall restic 2>/dev/null || true
    elif [[ -f "$RESTIC_BIN" ]]; then
        require_sudo
        sudo rm -f "$RESTIC_BIN"
    else
        detect_pkg_manager
        pkg_remove restic 2>/dev/null || true
    fi

    success "Restic $(_t 'Uninstalled.')"
}

# --- 状态检查 ---
status_restic() {
    detect_os
    local installed=false version=""
    if command_exists restic; then
        installed=true
        version=$(restic version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
    fi
    if $installed; then
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ($version)"
        emit_version "$version"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

# --- 用法 ---
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install or update Restic (default action)')
  uninstall   $(_t 'Uninstall Restic')
  status      $(_t 'View the install and run status')
  help        $(_t 'Show this help')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_restic ;;
        uninstall) uninstall_restic ;;
        status)    status_restic ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
