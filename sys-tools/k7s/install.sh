#!/usr/bin/env bash
#
# k7s/install.sh
#
# 安装 k7s —— Kubernetes 桌面监控工具（Tauri + Rust + React）。
# 支持 macOS (Apple Silicon / Intel) + Linux (deb/rpm/AppImage)。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

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

    info "$(_tf 'Downloading %s ...' "$url")"
    if ! curl -fSL "$url" -o "$tmpdir/$dmg_name"; then
        error "$(_tf 'Download failed, check the network or download it manually: https://github.com/%s/releases' "${REPO}")"
        return 1
    fi

    info "$(_t 'Installing into /Applications ...')"
    local volume="/Volumes/k7s-installer"
    hdiutil attach "$tmpdir/$dmg_name" -nobrowse -quiet 2>/dev/null || true
    sleep 1
    if [[ -d "$volume/k7s.app" ]]; then
        if cp -R "$volume/k7s.app" /Applications/ 2>/dev/null; then
            success "$(_t 'k7s.app has been installed into /Applications')"
        else
            sudo cp -R "$volume/k7s.app" /Applications/ && success "$(_t 'k7s.app has been installed into /Applications (sudo)')"
        fi
        hdiutil detach "$volume" -quiet 2>/dev/null || true
    else
        # 尝试查找挂载的 app
        local app_path
        app_path=$(find "$volume" -name "k7s.app" -maxdepth 2 2>/dev/null | head -1)
        if [[ -n "$app_path" ]]; then
            if cp -R "$app_path" /Applications/ 2>/dev/null; then
                success "$(_t 'k7s.app has been installed into /Applications')"
            else
                sudo cp -R "$app_path" /Applications/ && success "$(_t 'k7s.app has been installed into /Applications (sudo)')"
            fi
            hdiutil detach "$volume" -quiet 2>/dev/null || true
        else
            error "$(_t 'k7s.app was not found in the mounted DMG')"
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

        info "$(_tf 'Downloading %s ...' "$url")"
        if curl -fSL "$url" -o "$tmpdir/$filename" 2>/dev/null; then
            info "$(_tf 'Installing %s ...' "$filename")"
            case "$pkg_ext" in
                deb) sudo dpkg -i "$tmpdir/$filename" 2>/dev/null || sudo apt-get install -f -y ;;
                rpm) sudo rpm -i "$tmpdir/$filename" 2>/dev/null || sudo dnf install -y "$tmpdir/$filename" 2>/dev/null || sudo yum install -y "$tmpdir/$filename" ;;
            esac
            rm -rf "$tmpdir"
            trap - EXIT
            success "k7s $(_tf 'Installed (%s)' "${pkg_ext}")"
            return 0
        else
            warn "$pkg_ext $(_t 'Download failed, trying AppImage...')"
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

    info "$(_tf 'Downloading the AppImage: %s ...' "$appimage_url")"
    if ! curl -fSL "$appimage_url" -o "$target"; then
        error "$(_tf 'Download failed, check the network or download it manually: https://github.com/%s/releases' "${REPO}")"
        return 1
    fi
    chmod +x "$target"
    success "$(_tf 'The k7s AppImage has been installed into %s' "$target")"

    # 确保 ~/.local/bin 在 PATH 中
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        warn "$HOME/.local/bin $(_t 'Not in PATH, add it to your shell configuration:')"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# --- 安装主逻辑 ---
install_k7s() {
    preflight

    info "$(_t '🚀 Installing k7s (the Kubernetes desktop monitoring tool)')"

    local version
    version=$(get_latest_version)
    if [[ -z "$version" ]]; then
        error "$(_t 'Cannot fetch the latest version, check the network')"
        return 1
    fi
    success "$(_tf 'Latest version: v%s' "$version")"

    # 检查是否已安装
    if command_exists k7s; then
        local current
        current=$(k7s --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown')")
        warn "$(_tf 'k7s detected (%s)' "${current}")"
        if ! yes_no "$(_tf 'Continue installing v%s?' "${version}")"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        install_macos "$version"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        install_linux "$version"
    fi

    echo
    success "$(_t '🎉 k7s installation complete!')"
    info "$(_t 'How to launch it:')"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  $(_t 'Open k7s from Launchpad or Applications')"
        echo "  $(_t 'Or run it in a terminal: open -a k7s')"
    else
        echo "  $(_t 'Run it in a terminal: k7s')"
    fi
    echo
    info "$(_tf 'Docs: https://github.com/%s' "${REPO}")"
}

# --- 卸载 ---
uninstall_k7s() {
    detect_os

    info "$(_t 'Uninstalling k7s ...')"

    local removed=false

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -d "/Applications/k7s.app" ]]; then
            if yes_no "$(_t 'Delete /Applications/k7s.app?')"; then
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
            if yes_no "$(_tf 'Delete %s/.local/bin/k7s?' "$HOME")"; then
                rm -f "$HOME/.local/bin/k7s"
                removed=true
            fi
        fi
    fi

    if $removed; then
        success "k7s $(_t 'Uninstalled')"
    else
        warn "$(_t 'No k7s installation was found')"
    fi
}

# --- 状态 ---
status_k7s() {
    detect_os
    local found=false source="" ver=""

    if [[ "$OS_TYPE" == "darwin" ]] && [[ -d "/Applications/k7s.app" ]]; then
        found=true
        source="/Applications/k7s.app"
        ver=$(defaults read "/Applications/k7s.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} (v$ver, /Applications/k7s.app)"
        emit_extra "source=$source"
        emit_version "$ver"
    elif command_exists k7s; then
        found=true
        source=$(command -v k7s)
        ver=$(k7s --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown')")
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} (v$ver)"
        emit_extra "source=$source"
        emit_version "$ver"
    elif [[ -f "$HOME/.local/bin/k7s" ]]; then
        found=true
        source="$HOME/.local/bin/k7s"
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} (~/.local/bin/k7s)"
        emit_extra "source=$source"
    fi

    if ! $found; then
        # 检查 deb/rpm
        if command_exists dpkg && dpkg -l 2>/dev/null | grep -q k7s; then
            found=true
            source="deb"
            emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} (deb $(_t 'package)')"
            emit_extra "source=$source"
        elif command_exists rpm && rpm -q k7s >/dev/null 2>&1; then
            found=true
            source="rpm"
            emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} (rpm $(_t 'package)')"
            emit_extra "source=$source"
        fi
    fi

    $found || emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install k7s (the Kubernetes desktop monitoring tool, default action)')
  uninstall   $(_t 'Uninstall k7s')
  status      $(_t 'View the installation status')
  help        $(_t 'Display this help')

  $(_tf 'Project home: https://github.com/%s' "${REPO}")
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
