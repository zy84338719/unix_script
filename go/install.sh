#!/usr/bin/env bash
#
# go/install.sh
#
# 安装 Go（Golang）—— 官方二进制 tarball 方式，Linux + macOS。
# 装到 /usr/local/go，自动配置 PATH。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

GO_DIR="/usr/local/go"
GO_BIN="$GO_DIR/bin/go"

preflight() {
    detect_os
    check_commands curl tar
}

# 获取最新稳定版本号（如 1.23.4）
latest_go_version() {
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local auth=()
    if [[ -n "$token" ]]; then auth=(-H "Authorization: Bearer $token"); fi
    # golang/go 的 release tag 格式 go1.23.4
    curl -fsSL "${auth[@]}" "https://api.github.com/repos/golang/go/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"go([0-9.]+)".*/\1/'
}

arch_suffix() {
    local arch
    arch="$(uname -m)"
    case "$OS_TYPE/$arch" in
        linux/x86_64)        echo "linux-amd64" ;;
        linux/aarch64|linux/arm64) echo "linux-arm64" ;;
        darwin/x86_64)       echo "darwin-amd64" ;;
        darwin/arm64|darwin/aarch64) echo "darwin-arm64" ;;
        *) error "不支持的架构：$OS_TYPE/$arch"; exit 1 ;;
    esac
}

install_go() {
    preflight
    require_sudo
    info "🐹 安装 Go（Golang）"

    if [[ -x "$GO_BIN" ]]; then
        local cur
        cur=$("$GO_BIN" version 2>/dev/null | awk '{print $3}' || echo "已安装")
        warn "检测到已安装 Go（$cur）"
        if ! yes_no "是否继续并覆盖安装最新版？"; then
            info "已取消"; return 0
        fi
        sudo rm -rf "$GO_DIR"
    fi

    local version suffix url tmpdir
    version=$(latest_go_version)
    if [[ -z "$version" ]]; then
        error "无法获取 Go 最新版本（请检查网络或设置 GH_TOKEN）"
        exit 1
    fi
    success "最新版本：Go $version"
    suffix=$(arch_suffix)

    url="https://go.dev/dl/go${version}.${suffix}.tar.gz"
    info "下载：$url"
    tmpdir=$(mktemp -d)
    if ! curl -fSL "$url" -o "$tmpdir/go.tar.gz"; then
        error "下载失败"; rm -rf "$tmpdir"; exit 1
    fi
    info "解压到 $GO_DIR..."
    if ! sudo tar -C /usr/local -xzf "$tmpdir/go.tar.gz"; then
        error "解压失败"; rm -rf "$tmpdir"; exit 1
    fi
    rm -rf "$tmpdir"
    success "Go $version 安装完成"

    # 配置 PATH
    local rc updated=false
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]] && ! grep -q '/usr/local/go/bin' "$rc" 2>/dev/null; then
            {
                echo ""
                echo "# Go 环境（由 unix_script 添加）"
                # 以下两行需以字面量写入 rc（$PATH 和 $(go env GOPATH) 在 shell 启动时展开）
                # shellcheck disable=SC2016
                echo 'export PATH=$PATH:/usr/local/go/bin'
                # shellcheck disable=SC2016
                echo 'export PATH=$PATH:$(go env GOPATH)/bin'
            } >> "$rc"
            info "已为 $(basename "$rc") 添加 Go PATH 配置"
            updated=true
        fi
    done
    if ! $updated; then
        info "Go PATH 配置已存在（或无 rc 文件）"
    fi

    echo
    success "🎉 Go $version 安装完成！"
    info "重新加载 shell 后生效：source ~/.bashrc（或 ~/.zshrc）"
    echo "  go version          # 查看版本"
    echo "  go env GOPATH       # 查看 GOPATH"
    echo "  go run main.go      # 运行"
}

uninstall_go() {
    preflight
    require_sudo
    if [[ ! -d "$GO_DIR" ]]; then
        warn "未安装 Go（$GO_DIR 不存在）"; return 0
    fi
    if ! yes_no "确认卸载 Go（删除 $GO_DIR）？"; then
        info "已取消"; return 0
    fi
    sudo rm -rf "$GO_DIR"
    # 清理 shell rc 中的 Go PATH
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$rc" ]]; then
            sed -i.bak '/Go 环境\|\/usr\/local\/go\/bin\|GOPATH.\/bin/d' "$rc" 2>/dev/null || true
        fi
    done
    success "Go 已卸载（$GO_DIR 已删除）"
    warn "GOPATH 数据保留在 ~/go，可手动删除"
}

status_go() {
    detect_os
    if [[ -x "$GO_BIN" ]] || command_exists go; then
        local ver
        ver=$("$GO_BIN" version 2>/dev/null | awk '{print $3}' || go version 2>/dev/null | awk '{print $3}' || echo "")
        echo -e "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Go（官方二进制，装到 /usr/local/go，默认动作）
  uninstall   卸载
  status      查看状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
