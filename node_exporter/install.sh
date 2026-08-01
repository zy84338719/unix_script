#!/usr/bin/env bash
set -e

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# 全局变量
OS_TYPE=""
NE_BIN="/usr/local/bin/node_exporter"
NE_PLIST="/Library/LaunchDaemons/com.prometheus.node_exporter.plist"
NE_PLIST_LABEL="com.prometheus.node_exporter"

# 检查操作系统
check_os() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "检测到操作系统：macOS"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        info "检测到操作系统：Linux"
    fi
}

# 检查权限
check_permissions() {
    require_sudo
}

# 检查必要命令
check_dependencies() {
    local deps=("curl" "tar")
    # Linux 系统需要 systemctl
    if [[ "$OS_TYPE" == "linux" ]]; then
        deps+=("systemctl")
    fi
    check_commands "${deps[@]}"
}

# 检查是否已安装
check_existing_installation() {
    if command -v node_exporter &> /dev/null; then
        local current_version
        current_version=$(node_exporter --version 2>&1 | grep -o 'version [0-9.]*' | cut -d' ' -f2 2>/dev/null || echo "未知版本")
        warn "检测到已安装 node_exporter v$current_version"
        read -r -p "是否继续并覆盖安装最新版本？[y/N]: " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "安装已取消"
            exit 0
        fi

        info "正在停止现有服务..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo systemctl stop node_exporter &>/dev/null || true
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            if sudo launchctl list | grep -q "node_exporter"; then
                sudo launchctl bootout system "$NE_PLIST" &>/dev/null || true
            fi
            if command -v brew &> /dev/null && brew services list | grep -q "node_exporter"; then
                brew services stop node_exporter &>/dev/null || true
            fi
        fi
    fi
}

# 安装
install_node_exporter() {
    check_os
    check_dependencies
    check_existing_installation

    info "🚀 Node Exporter 跨平台安装脚本"
    echo "=========================================="

    # macOS 优先 brew（含 launchd 服务管理）
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 node_exporter..."
        brew install node_exporter
        brew services start node_exporter 2>/dev/null || true
        local ip_addr; ip_addr=$(get_local_ip)
        success "🎉 Node Exporter 安装完成！（brew 管理）"
        info "指标地址：http://${ip_addr}:9100/metrics"
        info "常用命令：brew services info node_exporter"
        return 0
    fi

    check_permissions

    # 获取最新版本号
    info "正在获取最新版本信息..."
    latest=$(github_latest_tag "prometheus/node_exporter")

    if [[ -z "$latest" ]]; then
        error "无法获取最新版本信息，请检查网络连接"
        exit 1
    fi

    success "最新版本：v$latest"

    # 确定架构和下载地址
    arch=$(uname -m)
    arch_suffix=""
    case "$OS_TYPE" in
      "linux")
        case "$arch" in
          x86_64) arch_suffix=linux-amd64;;
          aarch64|arm64) arch_suffix=linux-arm64;;
          armv7l) arch_suffix=linux-armv7;;
          *) error "不支持的 Linux 架构：$arch"; exit 1;;
        esac
        ;;
      "darwin")
        case "$arch" in
          x86_64) arch_suffix=darwin-amd64;;
          arm64) arch_suffix=darwin-arm64;;
          *) error "不支持的 macOS 架构：$arch"; exit 1;;
        esac
        ;;
    esac

    info "检测到架构：$arch -> $arch_suffix"

    # 确认安装
    echo
    info "即将安装 Node Exporter v$latest"
    info "安装位置：$NE_BIN"
    info "服务端口：9100"
    echo
    read -r -p "确认继续安装？[y/N]: " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "安装已取消"
        exit 0
    fi

    # 下载并解压
    info "正在下载和解压..."
    tmpdir=$(mktemp -d)

    url="https://github.com/prometheus/node_exporter/releases/download/v${latest}/node_exporter-${latest}.${arch_suffix}.tar.gz"
    info "下载地址：$url"

    if ! curl -SL "$url" -o "$tmpdir/node_exporter.tar.gz"; then
        error "下载失败"
        rm -rf "$tmpdir"
        exit 1
    fi

    if ! tar -xzf "$tmpdir/node_exporter.tar.gz" -C "$tmpdir"; then
        error "解压失败"
        rm -rf "$tmpdir"
        exit 1
    fi

    success "下载和解压完成"

    # 安装二进制
    info "正在安装二进制文件..."
    if sudo mv "$tmpdir/node_exporter-${latest}.${arch_suffix}/node_exporter" /usr/local/bin/; then
        sudo chmod 755 "$NE_BIN"
        if [[ "$OS_TYPE" == "darwin" ]]; then
            sudo chown root:wheel "$NE_BIN"
        elif [[ "$OS_TYPE" == "linux" ]]; then
            sudo chown root:root "$NE_BIN"
        fi
        success "二进制文件安装完成"
    else
        error "二进制文件安装失败"
        rm -rf "$tmpdir"
        exit 1
    fi

    # 创建服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "正在创建系统用户..."
        if ! id -u node_exporter &>/dev/null; then
            if sudo useradd --no-create-home --shell /bin/false node_exporter; then
                success "用户 node_exporter 创建成功"
            else
                error "用户创建失败"
                rm -rf "$tmpdir"
                exit 1
            fi
        else
            info "用户 node_exporter 已存在"
        fi

        info "正在创建 systemd 服务..."
        if sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<EOF; then
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=${NE_BIN} --web.listen-address=":9100"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
            success "systemd 服务文件创建成功"
        else
            error "systemd 服务文件创建失败"
            rm -rf "$tmpdir"
            exit 1
        fi

        info "正在启动服务..."
        sudo systemctl daemon-reload
        if sudo systemctl enable --now node_exporter; then
            success "node_exporter 服务已启动并设置为开机自启"
        else
            error "服务启动失败"
            rm -rf "$tmpdir"
            exit 1
        fi

    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "正在创建 macOS 服务..."
        if sudo tee "$NE_PLIST" >/dev/null <<EOF; then
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${NE_PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NE_BIN}</string>
        <string>--web.listen-address=:9100</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/node_exporter.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/node_exporter.log</string>
</dict>
</plist>
EOF
            success "LaunchDaemon 服务文件创建成功"
        else
            error "LaunchDaemon 服务文件创建失败"
            rm -rf "$tmpdir"
            exit 1
        fi

        info "正在启动服务..."
        if sudo launchctl list | grep -q "$NE_PLIST_LABEL"; then
            info "服务已在运行中"
            success "node_exporter 服务已启动并设置为开机自启"
        else
            if sudo launchctl bootstrap system "$NE_PLIST"; then
                success "node_exporter 服务已启动并设置为开机自启"
            else
                warn "bootstrap 命令失败，尝试使用 load 命令作为备选方案"
                if sudo launchctl load "$NE_PLIST" 2>/dev/null; then
                    success "node_exporter 服务已启动（使用 load 命令）"
                else
                    warn "自动启动失败，但服务文件已安装"
                    info "您可以手动启动服务：sudo launchctl bootstrap system $NE_PLIST"
                fi
            fi
        fi
    fi

    # 验证安装
    info "正在验证安装..."
    sleep 3
    service_active=false

    if service_is_active node_exporter "$NE_PLIST_LABEL"; then
        service_active=true
    fi

    if $service_active; then
        success "服务运行正常"
        sleep 2
        if curl -s http://localhost:9100/metrics > /dev/null; then
            success "端口 9100 响应正常"
        else
            warn "端口 9100 暂时无响应，可能需要等待几秒钟"
        fi
    else
        error "服务未正常运行"
        info "可以使用以下命令查看状态和日志："
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo "  sudo systemctl status node_exporter"
            echo "  sudo journalctl -u node_exporter -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            echo "  sudo launchctl list | grep node_exporter"
            echo "  tail -f /var/log/node_exporter.log"
        fi
    fi

    rm -rf "$tmpdir"
    ip_addr=$(get_local_ip)

    echo
    echo "========================================"
    success "🎉 Node Exporter v$latest 安装完成！"
    echo
    info "服务信息："
    echo "  - 监听地址：http://0.0.0.0:9100"
    echo "  - 指标地址：http://${ip_addr}:9100/metrics"
    echo "  - 状态页面：http://${ip_addr}:9100"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - 服务状态：sudo systemctl status node_exporter"
        echo "  - 查看日志：sudo journalctl -u node_exporter -f"
        echo "  - 重启服务：sudo systemctl restart node_exporter"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - 服务状态：sudo launchctl list | grep node_exporter"
        echo "  - 查看日志：tail -f /var/log/node_exporter.log"
        echo "  - 启动服务：sudo launchctl bootstrap system $NE_PLIST"
    fi
}

# 卸载
uninstall_node_exporter() {
    detect_os
    require_sudo
    info "正在卸载 Node Exporter..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop node_exporter &>/dev/null || true
        sudo systemctl disable node_exporter &>/dev/null || true
        sudo rm -f /etc/systemd/system/node_exporter.service
        sudo systemctl daemon-reload &>/dev/null || true
        sudo rm -f "$NE_BIN"
        if id node_exporter &>/dev/null; then
            sudo userdel node_exporter
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$NE_PLIST" &>/dev/null || true
        sudo rm -f "$NE_PLIST"
        sudo rm -f "$NE_BIN"
        sudo rm -f /var/log/node_exporter.log /var/log/node_exporter.err
    fi
    success "Node Exporter 已成功卸载！"
}

# 状态
status_node_exporter() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v node_exporter &>/dev/null || [[ -f "$NE_BIN" ]]; then
        is_installed=true
        if command -v node_exporter &>/dev/null; then
            version=$(node_exporter --version 2>/dev/null | head -1 || echo "未知版本")
        fi
    fi
    if service_is_active node_exporter "$NE_PLIST_LABEL"; then
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

  install     安装或更新 Node Exporter（默认动作）
  uninstall   卸载 Node Exporter
  status      查看安装与运行状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_node_exporter ;;
        uninstall) uninstall_node_exporter ;;
        status)    status_node_exporter ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
