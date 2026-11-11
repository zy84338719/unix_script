#!/usr/bin/env bash
#
# upftp/install.sh
#
# 安装 upftp —— 轻量级 FTP 文件分享工具（Go 单二进制，即开即用）。
# Linux + macOS。支持 brew / 官方一键脚本 / GitHub 二进制。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="zy84338719/upftp"

preflight() {
    detect_os
    check_commands curl
}

arch_suffix() {
    local arch
    arch="$(uname -m)"
    case "$OS_TYPE/$arch" in
        linux/x86_64)        echo "linux-amd64" ;;
        linux/aarch64|linux/arm64) echo "linux-arm64" ;;
        darwin/x86_64)       echo "darwin-amd64" ;;
        darwin/arm64|darwin/aarch64) echo "darwin-arm64" ;;
        *) error "$(_tf 'Unsupported architecture: %s/%s' "$OS_TYPE" "$arch")"; exit 1 ;;
    esac
}

install_upftp() {
    preflight
    info "$(_t '📂 Installing upftp (a lightweight FTP file sharing tool)')"

    if os_has_cmd upftp; then
        local cur
        cur=$(upftp --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'upftp detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    # macOS 优先 brew
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "$(_t 'Installing via Homebrew...')"
        brew install upftp 2>/dev/null || brew install zy84338719/upftp/upftp 2>/dev/null
    else
        # 从 GitHub Releases 下载二进制
        local version suffix url tmpdir
        version=$(http_github_latest_tag "$REPO")
        if [[ -z "$version" ]]; then
            error "$(_t 'Cannot fetch the latest upftp version (check the network or set GH_TOKEN)')"
            exit 1
        fi
        success "$(_tf 'Latest version: %s' "$version")"
        suffix=$(arch_suffix)

        # 尝试常见命名格式
        url="https://github.com/${REPO}/releases/download/${version}/upftp-${suffix}.tar.gz"
        info "$(_tf 'Downloading: %s' "$url")"
        tmpdir=$(mktemp -d)
        if ! curl -fSL "$url" -o "$tmpdir/upftp.tar.gz" 2>/dev/null; then
            # 回退：直接下载裸二进制
            url="https://github.com/${REPO}/releases/download/${version}/upftp-${suffix}"
            info "$(_tf 'Trying the bare binary: %s' "$url")"
            if ! curl -fSL "$url" -o "$tmpdir/upftp"; then
                error "$(_tf 'Download failed, download it manually from https://github.com/%s/releases' "${REPO}")"
                rm -rf "$tmpdir"; exit 1
            fi
            require_sudo
            sudo mv "$tmpdir/upftp" /usr/local/bin/upftp
            sudo chmod +x /usr/local/bin/upftp
            rm -rf "$tmpdir"
            success "upftp $version $(_t 'Installation complete')"
            _show_usage_hint
            return 0
        fi

        # 解压 tar.gz
        require_sudo
        if ! tar -xzf "$tmpdir/upftp.tar.gz" -C "$tmpdir" 2>/dev/null; then
            error "$(_t 'Extract failed')"; rm -rf "$tmpdir"; exit 1
        fi
        # 找到二进制文件
        local bin_file
        bin_file=$(find "$tmpdir" -name "upftp" -type f | head -1)
        if [[ -z "$bin_file" ]]; then
            error "$(_t 'The upftp binary was not found in the archive')"; rm -rf "$tmpdir"; exit 1
        fi
        sudo mv "$bin_file" /usr/local/bin/upftp
        sudo chmod +x /usr/local/bin/upftp
        rm -rf "$tmpdir"
        success "upftp $version $(_t 'Installation complete')"
    fi

    if os_has_cmd upftp; then
        _show_usage_hint
    else
        warn "upftp $(_t 'It may have been installed outside the PATH, please check')"
    fi
}

_show_usage_hint() {
    echo
    info "$(_t 'Quick start:')"
    echo "  upftp                        # $(_t 'Share the current directory (FTP 2121 / HTTP 8080)')"
    echo "  upftp -d /shared -p 3000     # $(_t 'Specify a directory and a port')"
    echo "  upftp --read-only            # $(_t 'Read-only mode')"
    echo "  upftp --tui=false            # $(_t 'Background service mode')"
    echo
    info "$(_t 'Open http://<your IP>:8080 in a browser to reach the web interface')"
    info "$(_tf 'Docs: https://github.com/%s' "${REPO}")"
}

uninstall_upftp() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        brew uninstall upftp 2>/dev/null
    fi
    require_sudo
    sudo rm -f /usr/local/bin/upftp
    success "upftp $(_t 'Uninstalled')"
}

status_upftp() {
    detect_os
    local installed=false ver=""
    if os_has_cmd upftp; then
        installed=true
        ver=$(upftp --version 2>/dev/null || echo "")
    fi
    if $installed; then
        uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
        uxs_emit_version "$ver"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install upftp (the FTP file sharing tool, default action)')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_upftp ;;
        uninstall) uninstall_upftp ;;
        status)    status_upftp ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
