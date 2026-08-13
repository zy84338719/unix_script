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
        *) error "不支持的架构：$OS_TYPE/$arch"; exit 1 ;;
    esac
}

install_upftp() {
    preflight
    info "📂 安装 upftp（轻量级 FTP 文件分享工具）"

    if command_exists upftp; then
        local cur
        cur=$(upftp --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 upftp（${cur}）"
        if ! yes_no "是否继续并更新？"; then
            info "已取消"; return 0
        fi
    fi

    # macOS 优先 brew
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装..."
        brew install upftp 2>/dev/null || brew install zy84338719/upftp/upftp 2>/dev/null
    else
        # 从 GitHub Releases 下载二进制
        local version suffix url tmpdir
        version=$(github_latest_tag "$REPO")
        if [[ -z "$version" ]]; then
            error "无法获取 upftp 最新版本（请检查网络或设置 GH_TOKEN）"
            exit 1
        fi
        success "最新版本：$version"
        suffix=$(arch_suffix)

        # 尝试常见命名格式
        url="https://github.com/${REPO}/releases/download/${version}/upftp-${suffix}.tar.gz"
        info "下载：$url"
        tmpdir=$(mktemp -d)
        if ! curl -fSL "$url" -o "$tmpdir/upftp.tar.gz" 2>/dev/null; then
            # 回退：直接下载裸二进制
            url="https://github.com/${REPO}/releases/download/${version}/upftp-${suffix}"
            info "尝试裸二进制：$url"
            if ! curl -fSL "$url" -o "$tmpdir/upftp"; then
                error "下载失败，请从 https://github.com/${REPO}/releases 手动下载"
                rm -rf "$tmpdir"; exit 1
            fi
            require_sudo
            sudo mv "$tmpdir/upftp" /usr/local/bin/upftp
            sudo chmod +x /usr/local/bin/upftp
            rm -rf "$tmpdir"
            success "upftp $version 安装完成"
            _show_usage_hint
            return 0
        fi

        # 解压 tar.gz
        require_sudo
        if ! tar -xzf "$tmpdir/upftp.tar.gz" -C "$tmpdir" 2>/dev/null; then
            error "解压失败"; rm -rf "$tmpdir"; exit 1
        fi
        # 找到二进制文件
        local bin_file
        bin_file=$(find "$tmpdir" -name "upftp" -type f | head -1)
        if [[ -z "$bin_file" ]]; then
            error "未在压缩包中找到 upftp 二进制"; rm -rf "$tmpdir"; exit 1
        fi
        sudo mv "$bin_file" /usr/local/bin/upftp
        sudo chmod +x /usr/local/bin/upftp
        rm -rf "$tmpdir"
        success "upftp $version 安装完成"
    fi

    if command_exists upftp; then
        _show_usage_hint
    else
        warn "upftp 可能装到非 PATH 路径，请检查"
    fi
}

_show_usage_hint() {
    echo
    info "快速开始："
    echo "  upftp                        # 分享当前目录（FTP 2121 / HTTP 8080）"
    echo "  upftp -d /shared -p 3000     # 指定目录和端口"
    echo "  upftp --read-only            # 只读模式"
    echo "  upftp --tui=false            # 后台服务模式"
    echo
    info "浏览器打开 http://<你的IP>:8080 访问 Web 界面"
    info "文档：https://github.com/${REPO}"
}

uninstall_upftp() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall upftp 2>/dev/null
    fi
    require_sudo
    sudo rm -f /usr/local/bin/upftp
    success "upftp 已卸载"
}

status_upftp() {
    detect_os
    local installed=false ver=""
    if command_exists upftp; then
        installed=true
        ver=$(upftp --version 2>/dev/null || echo "")
    fi
    if $installed; then
        emit_status "installed" "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 upftp（FTP 文件分享工具，默认动作）
  uninstall   卸载
  status      查看状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
