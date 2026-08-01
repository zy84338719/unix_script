#!/usr/bin/env bash
#
# rust/install.sh
#
# 安装 Rust（通过 rustup 官方安装器）。Linux + macOS。
# 装到 ~/.rustup + ~/.cargo，用户态安装无需 sudo。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

RUSTUP_INSTALLER="https://sh.rustup.rs"
CARGO_DIR="$HOME/.cargo"
RUSTUP_DIR="$HOME/.rustup"

preflight() {
    detect_os
    check_commands curl
}

install_rust() {
    preflight
    info "🦀 安装 Rust（通过 rustup）"

    if command_exists rustc; then
        local cur
        cur=$(rustc --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 Rust（$cur）"
        if ! yes_no "是否继续并更新？"; then
            info "已取消"; return 0
        fi
        info "通过 rustup 更新..."
        rustup update
        success "Rust 已更新"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 rustup..."
        brew install rustup
        rustup-init -y --no-modify-path 2>/dev/null || true
    else
        info "通过官方 rustup 安装（$RUSTUP_INSTALLER）..."
        # rustup 安装器：-y 跳过所有交互确认，使用默认配置
        if ! curl --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INSTALLER" | bash -s -- -y; then
            error "rustup 安装失败，请检查网络或参考 https://rustup.rs"
            exit 1
        fi
    fi

    # rustup 装到 ~/.cargo/bin，当前 session 可能不在 PATH
    if ! command_exists rustc && [[ -x "$CARGO_DIR/bin/rustc" ]]; then
        warn "rustc 已装到 $CARGO_DIR/bin，但不在当前 PATH"
        info "请添加到 shell 配置：export PATH=\"$CARGO_DIR/bin:\$PATH\""
        info "或重新加载 shell：source ~/.cargo/env"
    fi

    success "🎉 Rust 安装完成！"
    info "快速开始："
    echo "  rustc --version          # 查看版本"
    echo "  cargo new my-project     # 创建新项目"
    echo "  cargo build              # 编译"
    echo "  cargo run                # 运行"
    echo "  cargo test               # 测试"
    echo "  rustup component add rust-analyzer  # 添加 LSP"
    echo
    info "重新加载 shell 后生效：source ~/.cargo/env（或 source ~/.bashrc / ~/.zshrc）"
    info "文档：https://rustup.rs / https://doc.rust-lang.org"
}

uninstall_rust() {
    preflight
    if [[ ! -d "$RUSTUP_DIR" ]] && ! command_exists rustup; then
        warn "未安装 Rust（rustup）"; return 0
    fi
    if ! yes_no "确认卸载 Rust（删除 ~/.rustup + ~/.cargo）？"; then
        info "已取消"; return 0
    fi
    # rustup 自带卸载
    if command_exists rustup; then
        rustup self uninstall -y 2>/dev/null && success "Rust 已通过 rustup 卸载" && return 0
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
    success "Rust 已卸载（~/.rustup + ~/.cargo 已删除）"
}

status_rust() {
    detect_os
    if command_exists rustc || [[ -x "$CARGO_DIR/bin/rustc" ]]; then
        local ver
        ver=$(rustc --version 2>/dev/null || "$CARGO_DIR/bin/rustc" --version 2>/dev/null || echo "")
        echo -e "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Rust（通过 rustup，默认动作）
  uninstall   卸载（删除 ~/.rustup + ~/.cargo）
  status      查看状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
