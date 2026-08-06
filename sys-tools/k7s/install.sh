#!/usr/bin/env bash
#
# k7s/install.sh
#
# 安装 k7s —— Kubernetes 桌面监控工具（Tauri + Rust + React）。
# 支持 macOS (Apple Silicon / Intel) + Linux (deb/rpm/AppImage)。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="zy84338719/k7s"

preflight() {
    detect_os
    detect_arch
    check_commands curl
}

# --- 获取最新版本 ---
get_latest_version() {
    github_latest_tag "$REPO"
}

# --- macOS 安装（.dmg） ---
install_macos() {
    local version="$1"
    local arch_suffix
    if [[ "$ARCH_TYPE" == "ARM64" ]]; then
        arch_suffix="aarch64"
    else
        arch_suffix="x86_64"
    fi

    local dmg_name="k7s_${version}_${arch_suffix}.dmg"
    local url="https://github.com/${REPO}/releases/download/v${version}/${dmg_name}"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    info "下载 $url ..."
    if ! curl -fSL "$url" -o "$tmpdir/$dmg_name"; then
        error "下载失败，请检查网络或手动下载：https://github.com/${REPO}/releases"
        return 1
    fi

    info "安装到 /Applications ..."
    local volume="/Volumes/k7s-installer"
    hdiutil attach "$tmpdir/$dmg_name" -nobrowse -quiet 2>/dev/null || true
    sleep 1
    if [[ -d "$volume/k7s.app" ]]; then
        if cp -R "$volume/k7s.app" /Applications/ 2>/dev/null; then
            success "已安装 k7s.app 到 /Applications"
        else
            sudo cp -R "$volume/k7s.app" /Applications/ && success "已安装 k7s.app 到 /Applications（sudo）"
        fi
        hdiutil detach "$volume" -quiet 2>/dev/null || true
    else
        # 尝试查找挂载的 app
        local app_path
        app_path=$(find "$volume" -name "k7s.app" -maxdepth 2 2>/dev/null | head -1)
        if [[ -n "$app_path" ]]; then
            if cp -R "$app_path" /Applications/ 2>/dev/null; then
                success "已安装 k7s.app 到 /Applications"
            else
                sudo cp -R "$app_path" /Applications/ && success "已安装 k7s.app 到 /Applications（sudo）"
            fi
            hdiutil detach "$volume" -quiet 2>/dev/null || true
        else
            error "未在挂载的 DMG 中找到 k7s.app"
            hdiutil detach "$volume" -quiet 2>/dev/null || true
            return 1
        fi
    fi

    rm -rf "$tmpdir"
    trap - EXIT
}

# --- Linux 安装（deb/rpm/AppImage） ---
install_linux() {
    local version="$1"

    # 识别包格式
    local pkg_ext=""
    local install_cmd=""
    if command_exists dpkg; then
        pkg_ext="deb"
    elif command_exists rpm; then
        pkg_ext="rpm"
    else
        pkg_ext="AppImage"
    fi

    local arch_suffix
    if [[ "$ARCH_TYPE" == "ARM64" ]]; then
        arch_suffix="aarch64"
    else
        arch_suffix="x86_64"
    fi

    local filename="k7s_${version}_${arch_suffix}.${pkg_ext}"
    local url="https://github.com/${REPO}/releases/download/v${version}/${filename}"

    # AppImage 没有架构后缀的 deb/rpm 时回退
    if [[ "$pkg_ext" != "AppImage" ]]; then
        # 尝试下载 deb/rpm
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT

        info "下载 $url ..."
        if curl -fSL "$url" -o "$tmpdir/$filename" 2>/dev/null; then
            info "安装 $filename ..."
            case "$pkg_ext" in
                deb) sudo dpkg -i "$tmpdir/$filename" 2>/dev/null || sudo apt-get install -f -y ;;
                rpm) sudo rpm -i "$tmpdir/$filename" 2>/dev/null || sudo dnf install -y "$tmpdir/$filename" 2>/dev/null || sudo yum install -y "$tmpdir/$filename" ;;
            esac
            rm -rf "$tmpdir"
            trap - EXIT
            success "k7s 已安装（$pkg_ext）"
            return 0
        else
            warn "$pkg_ext 下载失败，尝试 AppImage..."
            rm -rf "$tmpdir"
            trap - EXIT
            pkg_ext="AppImage"
        fi
    fi

    # AppImage 安装
    local appimage_name="k7s_${version}_amd64.AppImage"
    [[ "$ARCH_TYPE" == "ARM64" ]] && appimage_name="k7s_${version}_aarch64.AppImage"
    local appimage_url="https://github.com/${REPO}/releases/download/v${version}/${appimage_name}"
    local target_dir="$HOME/.local/bin"
    local target="$target_dir/k7s"

    mkdir -p "$target_dir"

    info "下载 AppImage: $appimage_url ..."
    if ! curl -fSL "$appimage_url" -o "$target"; then
        error "下载失败，请检查网络或手动下载：https://github.com/${REPO}/releases"
        return 1
    fi
    chmod +x "$target"
    success "已安装 k7s AppImage 到 $target"

    # 确保 ~/.local/bin 在 PATH 中
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        warn "$HOME/.local/bin 不在 PATH 中，请添加到 shell 配置："
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# --- 安装主逻辑 ---
install_k7s() {
    preflight

    info "🚀 安装 k7s（Kubernetes 桌面监控工具）"

    local version
    version=$(get_latest_version)
    if [[ -z "$version" ]]; then
        error "无法获取最新版本，请检查网络"
        return 1
    fi
    success "最新版本：v$version"

    # 检查是否已安装
    if command_exists k7s; then
        local current
        current=$(k7s --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知")
        warn "已安装 k7s（$current）"
        if ! yes_no "是否继续安装 v$version？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        install_macos "$version"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        install_linux "$version"
    fi

    echo
    success "🎉 k7s 安装完成！"
    info "启动方式："
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  从 Launchpad 或 Applications 打开 k7s"
        echo "  或终端运行：open -a k7s"
    else
        echo "  终端运行：k7s"
    fi
    echo
    info "文档：https://github.com/${REPO}"
}

# --- 卸载 ---
uninstall_k7s() {
    detect_os

    info "卸载 k7s ..."

    local removed=false

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -d "/Applications/k7s.app" ]]; then
            if yes_no "确认删除 /Applications/k7s.app？"; then
                rm -rf "/Applications/k7s.app" 2>/dev/null || sudo rm -rf "/Applications/k7s.app"
                removed=true
            fi
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        # 尝试包管理器卸载
        if command_exists dpkg && dpkg -l | grep -q k7s; then
            sudo dpkg -r k7s 2>/dev/null && removed=true
        elif command_exists rpm && rpm -q k7s >/dev/null 2>&1; then
            sudo rpm -e k7s 2>/dev/null && removed=true
        fi
        # AppImage
        if [[ -f "$HOME/.local/bin/k7s" ]]; then
            if yes_no "确认删除 $HOME/.local/bin/k7s？"; then
                rm -f "$HOME/.local/bin/k7s"
                removed=true
            fi
        fi
    fi

    if $removed; then
        success "k7s 已卸载"
    else
        warn "未找到 k7s 安装"
    fi
}

# --- 状态 ---
status_k7s() {
    detect_os
    local found=false source="" ver=""

    if [[ "$OS_TYPE" == "darwin" ]] && [[ -d "/Applications/k7s.app" ]]; then
        found=true
        source="/Applications/k7s.app"
        ver=$(defaults read "/Applications/k7s.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "未知")
        emit_status "installed" "${GREEN}✅ 已安装${NC} (v$ver, /Applications/k7s.app)"
        emit_extra "source=$source"
        emit_version "$ver"
    elif command_exists k7s; then
        found=true
        source=$(command -v k7s)
        ver=$(k7s --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知")
        emit_status "installed" "${GREEN}✅ 已安装${NC} (v$ver)"
        emit_extra "source=$source"
        emit_version "$ver"
    elif [[ -f "$HOME/.local/bin/k7s" ]]; then
        found=true
        source="$HOME/.local/bin/k7s"
        emit_status "installed" "${GREEN}✅ 已安装${NC} (~/.local/bin/k7s)"
        emit_extra "source=$source"
    fi

    if ! $found; then
        # 检查 deb/rpm
        if command_exists dpkg && dpkg -l 2>/dev/null | grep -q k7s; then
            found=true
            source="deb"
            emit_status "installed" "${GREEN}✅ 已安装${NC} (deb 包)"
            emit_extra "source=$source"
        elif command_exists rpm && rpm -q k7s >/dev/null 2>&1; then
            found=true
            source="rpm"
            emit_status "installed" "${GREEN}✅ 已安装${NC} (rpm 包)"
            emit_extra "source=$source"
        fi
    fi

    $found || emit_status "not_installed" "${RED}❌ 未安装${NC}"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 k7s（Kubernetes 桌面监控工具，默认动作）
  uninstall   卸载 k7s
  status      查看安装状态
  help        显示此帮助

  项目主页: https://github.com/${REPO}
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_k7s ;;
        uninstall) uninstall_k7s ;;
        status)    status_k7s ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
