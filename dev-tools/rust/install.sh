#!/usr/bin/env bash
#
# rust/install.sh
#
# 安装 Rust（通过 rustup 官方安装器）。Linux + macOS。
# 装到 ~/.rustup + ~/.cargo，用户态安装无需 sudo。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

RUSTUP_INSTALLER="https://sh.rustup.rs"
CARGO_DIR="$HOME/.cargo"
RUSTUP_DIR="$HOME/.rustup"

preflight() {
    detect_os
    check_commands curl
}

install_rust() {
    preflight
    info "$(_t '🦀 Installing Rust (via rustup)')"

    if os_has_cmd rustc; then
        local cur
        cur=$(rustc --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Detected that Rust is already installed (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
        info "$(_t 'Updating via rustup...')"
        rustup update
        success "Rust $(_t 'Updated')"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "$(_t 'Installing rustup via Homebrew...')"
        brew install rustup
        rustup-init -y --no-modify-path 2>/dev/null || true
    else
        info "$(_tf 'Installing via the official rustup script (%s)...' "${RUSTUP_INSTALLER}")"
        # rustup 安装器：-y 跳过所有交互确认，使用默认配置。
        # 信任模型：rustup 安装器内部会校验下载的 rustup-init 二进制完整性（rust-lang/rustup#2711），
        # 故仅信任传输层（强制 --proto '=https' --tlsv1.2）即可。
        if ! curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INSTALLER" | bash -s -- -y; then
            error "rustup $(_t 'The installation failed, check the network or see https://rustup.rs')"
            exit 1
        fi
    fi

    # rustup 装到 ~/.cargo/bin，当前 session 可能不在 PATH
    if ! os_has_cmd rustc && [[ -x "$CARGO_DIR/bin/rustc" ]]; then
        warn "rustc $(_tf 'Installed to %s/bin, but it is not in the current PATH' "$CARGO_DIR")"
        # shellcheck disable=SC2016  # 译文里的 $PATH 是要原样打印的字面量，不能展开
        info "$(_tf 'Add it to your shell configuration: export PATH="%s/bin:$PATH"' "$CARGO_DIR")"
        info "$(_t 'Or reload the shell: source ~/.cargo/env')"
    fi

    success "$(_t '🎉 Rust installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  rustc --version          # $(_t 'View the version')"
    echo "  cargo new my-project     # $(_t 'Create a new project')"
    echo "  cargo build              # $(_t 'Compile')"
    echo "  cargo run                # $(_t 'Run')"
    echo "  cargo test               # $(_t 'Test')"
    echo "  rustup component add rust-analyzer  # $(_t 'Add the LSP')"
    echo
    info "$(_t 'Take effect after reloading the shell: source ~/.cargo/env (or source ~/.bashrc / ~/.zshrc)')"
    info "$(_t 'Docs: https://rustup.rs / https://doc.rust-lang.org')"
}

uninstall_rust() {
    preflight
    if [[ ! -d "$RUSTUP_DIR" ]] && ! os_has_cmd rustup; then
        warn "$(_t 'Rust is not installed (rustup)')"; return 0
    fi
    if ! yes_no "$(_t 'Confirm uninstalling Rust (deleting ~/.rustup + ~/.cargo)?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    # rustup 自带卸载
    if os_has_cmd rustup; then
        rustup self uninstall -y 2>/dev/null && success "Rust $(_t 'Uninstalled via rustup')" && return 0
    fi
    # 手动清理
    rm -rf "$RUSTUP_DIR" "$CARGO_DIR"
    # 清理 shell rc 中的 cargo env
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]]; then
            sed -i.bak '/cargo\/env/d' "$rc" 2>/dev/null || true
        fi
    done
    success "Rust $(_t 'Uninstalled (~/.rustup + ~/.cargo deleted)')"
}

status_rust() {
    detect_os
    if os_has_cmd rustc || [[ -x "$CARGO_DIR/bin/rustc" ]]; then
        local ver
        ver=$(rustc --version 2>/dev/null || "$CARGO_DIR/bin/rustc" --version 2>/dev/null || echo "")
        uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
        uxs_emit_version "$ver"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Rust (via rustup, default action)')
  uninstall   $(_t 'Uninstall (deleting ~/.rustup + ~/.cargo)')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_rust ;;
        uninstall) uninstall_rust ;;
        status)    status_rust ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
