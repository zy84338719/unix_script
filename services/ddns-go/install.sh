#!/usr/bin/env bash
set -e

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
OS_TYPE=""
DDNS_DIR="/opt/ddns-go"
DDNS_BIN="$DDNS_DIR/ddns-go"
DDNS_PLIST="/Library/LaunchDaemons/jeessy.ddns-go.plist"
DDNS_PLIST_LABEL="jeessy.ddns-go"

check_os() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then info "检测到操作系统：macOS"; fi
    if [[ "$OS_TYPE" == "linux" ]];  then info "检测到操作系统：Linux"; fi
}

check_permissions() { require_sudo; }
check_dependencies() { check_commands curl tar; }

check_existing_installation() {
    if [ -f "$DDNS_BIN" ]; then
        local current_version
        current_version=$("$DDNS_BIN" --version 2>&1)
        warn "检测到已安装 ddns-go $current_version"
        read -r -p "是否继续并覆盖安装最新版本？[y/N]: " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "安装已取消"; exit 0
        fi
        info "正在停止并卸载现有服务..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo systemctl stop ddns-go &>/dev/null || true
        fi
        sudo "$DDNS_BIN" -s uninstall &>/dev/null || true
    fi
}

install_ddns_go() {
    check_os
    check_permissions
    check_dependencies
    check_existing_installation

    info "🚀 ddns-go 跨平台安装脚本"
    echo "=========================================="

    info "正在获取最新版本信息..."
    api_url="https://api.github.com/repos/jeessy2/ddns-go/releases/latest"
    gh_auth=()
    gh_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -n "$gh_token" ]]; then
        gh_auth=(-H "Authorization: Bearer $gh_token")
    fi
    release_info=$(curl -s "${gh_auth[@]}" "$api_url")

    latest_tag=$(echo "$release_info" | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$latest_tag" ]]; then
        error "无法获取最新版本信息，请检查网络连接或 API 速率限制"
        exit 1
    fi
    success "最新版本：$latest_tag"

    arch=$(uname -m)
    arch_suffix=""
    case "$OS_TYPE" in
      "linux")
        case "$arch" in
          x86_64) arch_suffix=linux_x86_64;;
          aarch64|arm64) arch_suffix=linux_arm64;;
          armv7l) arch_suffix=linux_armv7;;
          *) error "不支持的 Linux 架构：$arch"; exit 1;;
        esac
        ;;
      "darwin")
        case "$arch" in
          x86_64) arch_suffix=darwin_amd64;;
          arm64) arch_suffix=darwin_arm64;;
          *) error "不支持的 macOS 架构：$arch"; exit 1;;
        esac
        ;;
    esac

    download_url=$(echo "$release_info" | grep "browser_download_url" | grep "$arch_suffix.tar.gz" | cut -d '"' -f 4)
    if [[ -z "$download_url" ]]; then
        error "无法找到适用于 $arch_suffix 的下载链接"; exit 1
    fi

    echo
    info "即将安装 ddns-go $latest_tag"
    info "安装位置：$DDNS_DIR"
    info "服务端口：9876"
    echo
    read -r -p "确认继续安装？[y/N]: " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "安装已取消"; exit 0
    fi

    info "正在下载和解压..."
    tmpdir=$(mktemp -d)
    if ! curl -SL "$download_url" -o "$tmpdir/ddns-go.tar.gz"; then
        error "下载失败"; rm -rf "$tmpdir"; exit 1
    fi
    if ! tar -xzf "$tmpdir/ddns-go.tar.gz" -C "$tmpdir"; then
        error "解压失败"; rm -rf "$tmpdir"; exit 1
    fi
    success "下载和解压完成"

    info "正在安装 ddns-go..."
    sudo mkdir -p "$DDNS_DIR"
    sudo mv "$tmpdir/ddns-go" "$DDNS_DIR/"
    sudo mv "$tmpdir/README.md" "$DDNS_DIR/" 2>/dev/null || true
    sudo mv "$tmpdir/LICENSE" "$DDNS_DIR/" 2>/dev/null || true
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown -R root:wheel "$DDNS_DIR"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        sudo chown -R root:root "$DDNS_DIR"
    fi
    sudo chmod +x "$DDNS_BIN"
    success "文件安装完成"

    info "正在安装服务..."
    if sudo "$DDNS_BIN" -s install; then
        success "服务安装成功"
    else
        error "服务安装失败"; rm -rf "$tmpdir"; exit 1
    fi

    info "正在启动服务..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        if sudo systemctl enable --now ddns-go; then
            success "ddns-go 服务已启动并设置为开机自启"
        else
            error "服务启动失败"; rm -rf "$tmpdir"; exit 1
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if sudo launchctl list | grep -q "$DDNS_PLIST_LABEL"; then
            info "服务已在运行中"; success "ddns-go 服务已启动并设置为开机自启"
        else
            if sudo launchctl bootstrap system "$DDNS_PLIST"; then
                success "ddns-go 服务已启动并设置为开机自启"
            else
                warn "bootstrap 失败，尝试 load"
                if sudo launchctl load "$DDNS_PLIST" 2>/dev/null; then
                    success "ddns-go 服务已启动（load）"
                else
                    warn "自动启动失败，服务文件已安装"
                fi
            fi
        fi
    fi

    rm -rf "$tmpdir"

    info "正在验证安装..."
    sleep 3
    if service_is_active ddns-go "$DDNS_PLIST_LABEL"; then
        success "服务运行正常"
    else
        error "服务未正常运行"
        info "查看日志："
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo "  sudo systemctl status ddns-go"
            echo "  sudo journalctl -u ddns-go -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            echo "  sudo launchctl list | grep ddns-go"
        fi
    fi

    ip_addr=$(get_local_ip)
    echo
    echo "=========================================="
    success "🎉 ddns-go $latest_tag 安装完成！"
    echo
    info "服务信息："
    echo "  - 访问地址：http://${ip_addr}:9876"
    echo "  - 安装目录：$DDNS_DIR"
    echo "  - 配置文件：$DDNS_DIR/.ddns_go_config.yaml (首次访问后自动创建)"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - 服务状态：sudo systemctl status ddns-go"
        echo "  - 查看日志：sudo journalctl -u ddns-go -f"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - 服务状态：sudo launchctl list | grep ddns-go"
        echo "  - 启动服务：sudo launchctl bootstrap system $DDNS_PLIST"
    fi
    echo
    warn "请务必在 Web 界面中设置您的 DNS 服务商信息和要更新的域名！"
}

uninstall_ddns_go() {
    detect_os
    require_sudo
    info "正在卸载 DDNS-GO..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop ddns-go &>/dev/null || true
        sudo systemctl disable ddns-go &>/dev/null || true
        sudo systemctl daemon-reload
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$DDNS_PLIST" &>/dev/null || true
        sudo rm -f "$DDNS_PLIST"
    fi
    sudo rm -rf "$DDNS_DIR"
    success "DDNS-GO 已成功卸载！"
}

status_ddns_go() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v ddns-go &>/dev/null || [[ -f "$DDNS_BIN" ]]; then
        is_installed=true
        if [[ -x "$DDNS_BIN" ]]; then
            version=$("$DDNS_BIN" --version 2>&1 | head -1 || echo "")
        fi
    fi
    if service_is_active ddns-go "$DDNS_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($version)"
        else
            echo -e "${YELLOW}⚠️  已安装但未运行${NC} ($version)"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装或更新 DDNS-GO（默认动作）
  uninstall   卸载 DDNS-GO
  status      查看安装与运行状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_ddns_go ;;
        uninstall) uninstall_ddns_go ;;
        status)    status_ddns_go ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
