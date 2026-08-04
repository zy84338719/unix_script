#!/usr/bin/env bash
#
# gitea/install.sh
#
# 安装与管理 Gitea 自托管 Git 服务。
# 从 GitHub 下载二进制，创建系统用户与目录，
# 配置 systemd（Linux）或 launchd（macOS）服务。
#
# 子命令：
#   install           安装/更新 Gitea
#   uninstall         卸载 Gitea
#   status            查看状态
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

GITEA_BIN="/usr/local/bin/gitea"
GITEA_USER="git"
GITEA_CONFIG="/etc/gitea/app.ini"
GITEA_DATA="/var/lib/gitea"
GITEA_SYSTEMD="/etc/systemd/system/gitea.service"
GITEA_PLIST="/Library/LaunchDaemons/io.gitea.web.plist"
GITEA_PLIST_LABEL="io.gitea.web"
GITEA_PORT="3000"
GITEA_SSH_PORT="2222"

# --- 获取最新版本 ---
get_latest_version() {
    local ver
    ver=$(github_latest_tag "go-gitea/gitea")
    if [[ -z "$ver" ]]; then
        error "无法获取最新版本信息，请检查网络连接"
        return 1
    fi
    echo "$ver"
}

# --- 检测架构后缀 ---
detect_arch_suffix() {
    local arch
    arch=$(uname -m)
    case "$OS_TYPE" in
        linux)
            case "$arch" in
                x86_64)         echo "linux-amd64" ;;
                aarch64|arm64)  echo "linux-arm64" ;;
                armv7l)         echo "linux-arm-7" ;;
                *) error "不支持的 Linux 架构：$arch"; return 1 ;;
            esac
            ;;
        darwin)
            case "$arch" in
                x86_64) echo "darwin-amd64" ;;
                arm64)  echo "darwin-arm64" ;;
                *) error "不支持的 macOS 架构：$arch"; return 1 ;;
            esac
            ;;
    esac
}

# --- 检查已有安装 ---
handle_existing_installation() {
    if ! command_exists gitea && [[ ! -f "$GITEA_BIN" ]]; then
        return 0
    fi
    local current_version
    current_version=$(gitea --version 2>/dev/null | head -1 || echo "未知版本")
    warn "检测到已安装 Gitea（$current_version）"
    if ! yes_no "是否继续并覆盖安装最新版本？"; then
        info "安装已取消"
        exit 0
    fi
    info "正在停止现有服务..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop gitea 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$GITEA_PLIST" 2>/dev/null || true
    fi
}

# --- 创建系统用户（Linux） ---
create_gitea_user() {
    if id -u "$GITEA_USER" &>/dev/null; then
        info "用户 $GITEA_USER 已存在"
        return 0
    fi
    info "创建系统用户 $GITEA_USER..."
    sudo adduser --system --shell /bin/bash --group --disabled-password --home "/home/$GITEA_USER" "$GITEA_USER" 2>/dev/null \
        || sudo useradd --system --shell /bin/bash --create-home "$GITEA_USER" 2>/dev/null \
        || { error "创建用户失败"; return 1; }
    success "用户 $GITEA_USER 创建成功"
}

# --- 创建目录结构 ---
create_directories() {
    require_sudo
    info "创建目录结构..."
    sudo mkdir -p "$GITEA_DATA"/{data,indexers,log,custom}
    sudo mkdir -p /etc/gitea

    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo chown -R "$GITEA_USER":"$GITEA_USER" "$GITEA_DATA"
        sudo chown root:"$GITEA_USER" /etc/gitea
        sudo chmod 750 /etc/gitea
    fi
    success "目录结构创建完成"
}

# --- 创建 systemd 服务（Linux） ---
setup_systemd_service() {
    info "创建 systemd 服务..."
    sudo tee "$GITEA_SYSTEMD" >/dev/null <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target
Wants=network.target

[Service]
Type=simple
User=$GITEA_USER
Group=$GITEA_USER
WorkingDirectory=$GITEA_DATA
ExecStart=$GITEA_BIN web --config $GITEA_CONFIG
Restart=always
RestartSec=10
Environment=USER=$GITEA_USER HOME=/home/$GITEA_USER GITEA_WORK_DIR=$GITEA_DATA

[Install]
WantedBy=multi-user.target
EOF
    success "systemd 服务文件创建成功"

    sudo systemctl daemon-reload
    if sudo systemctl enable --now gitea; then
        success "Gitea 服务已启动并设置为开机自启"
    else
        error "服务启动失败"
        return 1
    fi
}

# --- 创建 launchd 服务（macOS） ---
setup_launchd_service() {
    info "创建 macOS 服务..."
    sudo tee "$GITEA_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$GITEA_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$GITEA_BIN</string>
        <string>web</string>
        <string>--config</string>
        <string>$GITEA_CONFIG</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$GITEA_DATA</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GITEA_WORK_DIR</key>
        <string>$GITEA_DATA</string>
    </dict>
    <key>StandardErrorPath</key>
    <string>/var/log/gitea.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/gitea.log</string>
</dict>
</plist>
EOF
    success "LaunchDaemon 服务文件创建成功"

    if sudo launchctl list | grep -q "$GITEA_PLIST_LABEL"; then
        info "服务已在运行中"
    else
        if sudo launchctl bootstrap system "$GITEA_PLIST"; then
            success "Gitea 服务已启动"
        else
            warn "bootstrap 失败，尝试 load"
            if sudo launchctl load "$GITEA_PLIST" 2>/dev/null; then
                success "Gitea 服务已启动（load）"
            else
                warn "自动启动失败，服务文件已安装"
                info "手动启动：sudo launchctl bootstrap system $GITEA_PLIST"
            fi
        fi
    fi
}

# --- 安装 Gitea ---
install_gitea() {
    detect_os
    check_commands curl
    handle_existing_installation

    info "🚀 Gitea 自托管 Git 服务安装脚本"
    echo "=========================================="

    # macOS 优先 brew
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 Gitea..."
        brew install gitea
        brew services start gitea 2>/dev/null || true
        local ip_addr; ip_addr=$(get_local_ip)
        success "🎉 Gitea 安装完成！（brew 管理）"
        info "访问地址：http://${ip_addr}:${GITEA_PORT}"
        info "常用命令：brew services info gitea"
        return 0
    fi

    require_sudo

    # 获取最新版本
    info "正在获取最新版本信息..."
    local latest
    latest=$(get_latest_version) || return 1
    success "最新版本：v$latest"

    # 确定架构
    local arch_suffix
    arch_suffix=$(detect_arch_suffix) || return 1
    info "检测到架构：$(uname -m) -> $arch_suffix"

    # 确认安装
    echo
    info "即将安装 Gitea v$latest"
    info "安装位置：$GITEA_BIN"
    info "Web 端口：$GITEA_PORT | SSH 端口：$GITEA_SSH_PORT"
    info "配置文件：$GITEA_CONFIG"
    info "数据目录：$GITEA_DATA"
    echo
    if ! yes_no "确认继续安装？"; then
        info "安装已取消"
        return 0
    fi

    # 下载二进制
    local url="https://github.com/go-gitea/gitea/releases/download/v${latest}/gitea-${latest}-${arch_suffix}"
    info "下载地址：$url"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    if ! curl -SL "$url" -o "$tmpdir/gitea"; then
        error "下载失败"
        exit 1
    fi
    success "下载完成"

    # 安装二进制
    sudo mv "$tmpdir/gitea" "$GITEA_BIN"
    sudo chmod 755 "$GITEA_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$GITEA_BIN"
    else
        sudo chown root:root "$GITEA_BIN"
    fi
    success "二进制文件安装完成"

    # Linux：创建用户与目录，配置服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        create_gitea_user
        create_directories
        setup_systemd_service
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        create_directories
        setup_launchd_service
    fi

    rm -rf "$tmpdir"
    trap - EXIT

    # 验证
    info "正在验证安装..."
    sleep 3
    local ip_addr
    ip_addr=$(get_local_ip)

    if service_is_active gitea "$GITEA_PLIST_LABEL"; then
        success "服务运行正常"
    else
        warn "服务可能还在启动中..."
    fi

    echo
    echo "=========================================="
    success "🎉 Gitea v$latest 安装完成！"
    echo
    info "服务信息："
    echo "  - Web 访问：http://${ip_addr}:${GITEA_PORT}"
    echo "  - SSH 地址：ssh://${ip_addr}:${GITEA_SSH_PORT}"
    echo "  - 配置文件：$GITEA_CONFIG"
    echo "  - 数据目录：$GITEA_DATA"
    echo
    info "首次访问请完成初始安装向导（设置管理员账号、数据库等）。"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - 服务状态：sudo systemctl status gitea"
        echo "  - 查看日志：sudo journalctl -u gitea -f"
        echo "  - 重启服务：sudo systemctl restart gitea"
        echo "  - 编辑配置：sudo nano $GITEA_CONFIG"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - 服务状态：sudo launchctl list | grep gitea"
        echo "  - 查看日志：tail -f /var/log/gitea.log"
        echo "  - 重启服务：sudo launchctl kickstart -k system/$GITEA_PLIST_LABEL"
        echo "  - 编辑配置：sudo nano $GITEA_CONFIG"
    fi
}

# --- 卸载 Gitea ---
uninstall_gitea() {
    detect_os
    warn "即将卸载 Gitea。"
    echo
    local delete_data=false
    if yes_no "是否同时删除数据目录（$GITEA_DATA）？"; then
        delete_data=true
        info "将删除数据目录"
    else
        info "将保留数据目录"
    fi

    if ! yes_no "确认卸载 Gitea？"; then
        info "已取消"
        return 0
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        require_sudo
        sudo systemctl stop gitea 2>/dev/null || true
        sudo systemctl disable gitea 2>/dev/null || true
        sudo rm -f "$GITEA_SYSTEMD"
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo rm -f "$GITEA_BIN"
        # 删除配置目录
        sudo rm -rf /etc/gitea
        # 按用户选择删除数据
        if $delete_data; then
            sudo rm -rf "$GITEA_DATA"
            info "数据目录已删除"
        else
            info "数据目录已保留：$GITEA_DATA"
        fi
        if id -u "$GITEA_USER" &>/dev/null; then
            sudo userdel "$GITEA_USER" 2>/dev/null || true
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            brew services stop gitea 2>/dev/null || true
            brew uninstall gitea 2>/dev/null || true
        else
            sudo launchctl bootout system "$GITEA_PLIST" 2>/dev/null || true
            sudo rm -f "$GITEA_PLIST"
            sudo rm -f "$GITEA_BIN"
        fi
        sudo rm -rf /etc/gitea
        if $delete_data; then
            sudo rm -rf "$GITEA_DATA"
            info "数据目录已删除"
        else
            info "数据目录已保留：$GITEA_DATA"
        fi
    fi

    success "Gitea 已卸载。"
}

# --- 状态检查 ---
status_gitea() {
    detect_os
    local is_installed=false is_running=false version=""
    if command_exists gitea || [[ -f "$GITEA_BIN" ]]; then
        is_installed=true
        if command_exists gitea; then
            version=$(gitea --version 2>/dev/null | head -1 || echo "未知版本")
        fi
    fi
    if service_is_active gitea "$GITEA_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($version)"
        else
            echo -e "${YELLOW}⚠️  已安装但服务未运行${NC} ($version)"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# --- 用法 ---
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装或更新 Gitea（默认动作）
  uninstall   卸载 Gitea
  status      查看安装与运行状态
  help        显示本帮助
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_gitea ;;
        uninstall) uninstall_gitea ;;
        status)    status_gitea ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
