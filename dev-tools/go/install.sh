#!/usr/bin/env bash
#
# go/install.sh
#
# 安装 Go（Golang）—— 官方二进制 tarball 方式，Linux + macOS。
# 装到 /usr/local/go，自动配置 PATH。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

GO_DIR="/usr/local/go"
GO_BIN="$GO_DIR/bin/go"

preflight() {
    detect_os
    check_commands curl tar
}

# 获取最新稳定版本号（如 1.23.4）
# 复用 common.sh 的 github_latest_tag；golang/go 的 tag 格式 go1.23.4，剥前缀 go。
latest_go_version() {
    local tag
    tag=$(github_latest_tag "golang/go")
    echo "${tag#go}"
}

arch_suffix() {
    local arch
    arch="$(uname -m)"
    case "$OS_TYPE/$arch" in
        linux/x86_64)        echo "linux-amd64" ;;
        linux/aarch64|linux/arm64) echo "linux-arm64" ;;
        darwin/x86_64)       echo "darwin-amd64" ;;
        darwin/arm64|darwin/aarch64) echo "darwin-arm64" ;;
        *) error "$(_tf 'unsupported architecture: %s/%s' "$OS_TYPE" "$arch")"; exit 1 ;;
    esac
}

install_go() {
    preflight
    info "$(_t '🐹 Installing Go (Golang)')"

    # macOS 优先 brew（无需 sudo，自动管理）
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "$(_t 'Installing Go via Homebrew...')"
        brew install go
        success "Go $(_t 'Installation complete (the version is managed by brew)')"
        echo "  go version          # $(_t 'View the version')"
        echo "  go env GOPATH       # $(_t 'View GOPATH')"
        return 0
    fi

    require_sudo

    if [[ -x "$GO_BIN" ]]; then
        local cur
        cur=$("$GO_BIN" version 2>/dev/null | awk '{print $3}' || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Go %s detected (already installed)' "${cur}")"
        if ! yes_no "$(_t 'Continue and overwrite it with the latest version?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
        sudo rm -rf "$GO_DIR"
    fi

    local version suffix url tmpdir
    version=$(latest_go_version)
    if [[ -z "$version" ]]; then
        error "$(_t 'Cannot get the latest Go version (check the network or set GH_TOKEN)')"
        exit 1
    fi
    success "$(_tf 'Latest version: Go %s' "$version")"
    suffix=$(arch_suffix)

    url="https://go.dev/dl/go${version}.${suffix}.tar.gz"
    info "$(_tf 'Downloading: %s' "$url")"
    tmpdir=$(mktemp -d)
    if ! curl -fSL "$url" -o "$tmpdir/go.tar.gz"; then
        error "$(_t 'Download failed')"; rm -rf "$tmpdir"; exit 1
    fi
    info "$(_tf 'Extracting to %s...' "$GO_DIR")"
    if ! sudo tar -C /usr/local -xzf "$tmpdir/go.tar.gz"; then
        error "$(_t 'Extraction failed')"; rm -rf "$tmpdir"; exit 1
    fi
    rm -rf "$tmpdir"
    success "Go $version $(_t 'Installation complete')"

    # 配置 PATH
    local rc updated=false
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]] && ! grep -q '/usr/local/go/bin' "$rc" 2>/dev/null; then
            {
                echo ""
                echo "# >>> unix_script go >>> Go $(_t 'Environment (added by unix_script)')"
                # 以下两行需以字面量写入 rc（$PATH 和 $(go env GOPATH) 在 shell 启动时展开）
                # shellcheck disable=SC2016
                echo 'export PATH=$PATH:/usr/local/go/bin'
                # shellcheck disable=SC2016
                echo 'export PATH=$PATH:$(go env GOPATH)/bin'
            } >> "$rc"
            info "$(_tf 'Added the Go PATH configuration for %s' "$(basename "$rc")")"
            updated=true
        fi
    done
    if ! $updated; then
        info "Go PATH $(_t 'The configuration already exists (or there is no rc file)')"
    fi

    echo
    success "$(_tf '🎉 Go %s installation complete!' "$version")"
    info "$(_t 'Take effect after reloading the shell: source ~/.bashrc (or ~/.zshrc)')"
    echo "  go version          # $(_t 'View the version')"
    echo "  go env GOPATH       # $(_t 'View GOPATH')"
    echo "  go run main.go      # $(_t 'Run')"
}

uninstall_go() {
    preflight
    require_sudo
    if [[ ! -d "$GO_DIR" ]]; then
        warn "$(_tf 'Go is not installed (%s does not exist)' "$GO_DIR")"; return 0
    fi
    if ! yes_no "$(_tf 'Confirm uninstalling Go (deleting %s)?' "${GO_DIR}")"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    sudo rm -rf "$GO_DIR"
    # 清理 shell rc 中的 Go PATH
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]]; then
            sed -i.bak '/>>> unix_script go >>>\|\/usr\/local\/go\/bin\|GOPATH.\/bin/d' "$rc" 2>/dev/null || true
        fi
    done
    success "Go $(_tf 'Uninstalled (%s deleted)' "$GO_DIR")"
    warn "GOPATH $(_t 'The data stays in ~/go, you can delete it manually')"
}

status_go() {
    detect_os
    if [[ -x "$GO_BIN" ]] || command_exists go; then
        local ver
        ver=$("$GO_BIN" version 2>/dev/null | awk '{print $3}' || go version 2>/dev/null | awk '{print $3}' || echo "")
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Go (the official binary, into /usr/local/go, default action)')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_go ;;
        uninstall) uninstall_go ;;
        status)    status_go ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
