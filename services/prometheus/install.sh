#!/usr/bin/env bash
set -euo pipefail

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
PROM_BIN="/usr/local/bin/prometheus"
PROMTOOL_BIN="/usr/local/bin/promtool"
PROM_PLIST="/Library/LaunchDaemons/io.prometheus.prometheus.plist"
PROM_PLIST_LABEL="io.prometheus.prometheus"
PROM_CONFIG="/etc/prometheus/prometheus.yml"
PROM_DATA_DIR="/var/lib/prometheus"
PROM_USER="prometheus"
PROM_PORT=9090

# --- 获取最新版本 ---
get_latest_version() {
    local ver
    ver=$(github_latest_tag "prometheus/prometheus")
    if [[ -z "$ver" ]]; then
        error "无法获取最新版本信息，请检查网络连接"
        return 1
    fi
    echo "$ver"
}

# --- 检测架构后缀 ---
detect_arch_suffix() {
    case "$OS_TYPE" in
        linux)
            case "$(uname -m)" in
                x86_64)         echo "linux-amd64" ;;
                aarch64|arm64)  echo "linux-arm64" ;;
                armv7l)         echo "linux-armv7" ;;
                *) error "不支持的 Linux 架构：$(uname -m)"; return 1 ;;
            esac
            ;;
        darwin)
            case "$(uname -m)" in
                x86_64) echo "darwin-amd64" ;;
                arm64)  echo "darwin-arm64" ;;
                *) error "不支持的 macOS 架构：$(uname -m)"; return 1 ;;
            esac
            ;;
    esac
}

# --- 检查已有安装并处理 ---
handle_existing_installation() {
    if ! command -v prometheus &>/dev/null; then
        return 0
    fi
    local current_version
    current_version=$(prometheus --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知版本")
    warn "检测到已安装 Prometheus v$current_version"
    if ! yes_no "是否继续并覆盖安装最新版本？"; then
        info "安装已取消"
        exit 0
    fi

    info "正在停止现有服务..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop prometheus &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$PROM_PLIST" &>/dev/null || true
    fi
}

# --- 下载并解压 ---
download_and_extract() {
    local latest="$1" arch_suffix="$2" tmpdir="$3"
    local url="https://github.com/prometheus/prometheus/releases/download/v${latest}/prometheus-${latest}.${arch_suffix}.tar.gz"
    info "下载地址：$url"

    if ! curl -fSL "$url" -o "$tmpdir/prometheus.tar.gz"; then
        error "下载失败"
        return 1
    fi
    if ! tar -xzf "$tmpdir/prometheus.tar.gz" -C "$tmpdir"; then
        error "解压失败"
        return 1
    fi
    success "下载和解压完成"
}

# --- 安装二进制文件 ---
install_binaries() {
    local latest="$1" arch_suffix="$2" tmpdir="$3"
    local src_dir="$tmpdir/prometheus-${latest}.${arch_suffix}"

    info "正在安装二进制文件..."
    sudo cp "$src_dir/prometheus" "$PROM_BIN"
    sudo cp "$src_dir/promtool" "$PROMTOOL_BIN"
    sudo chmod 755 "$PROM_BIN" "$PROMTOOL_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$PROM_BIN" "$PROMTOOL_BIN"
    else
        sudo chown root:root "$PROM_BIN" "$PROMTOOL_BIN"
    fi
    success "二进制文件安装完成（prometheus, promtool）"
}

# --- 创建目录和配置（Linux） ---
setup_linux_dirs_and_config() {
    # 创建用户
    info "正在创建系统用户..."
    if ! id -u "$PROM_USER" &>/dev/null; then
        sudo useradd --no-create-home --shell /bin/false "$PROM_USER"
        success "用户 $PROM_USER 创建成功"
    else
        info "用户 $PROM_USER 已存在"
    fi

    # 创建目录
    sudo mkdir -p /etc/prometheus "$PROM_DATA_DIR"
    sudo chown "$PROM_USER:$PROM_USER" "$PROM_DATA_DIR"

    # 写入默认配置（如果不存在）
    if [[ ! -f "$PROM_CONFIG" ]]; then
        info "正在创建默认配置 $PROM_CONFIG ..."
        sudo tee "$PROM_CONFIG" >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF
        sudo chown "$PROM_USER:$PROM_USER" "$PROM_CONFIG"
        success "默认配置已创建"
    else
        info "配置文件 $PROM_CONFIG 已存在，跳过创建"
    fi
}

# --- 创建 systemd 服务（Linux） ---
setup_systemd_service() {
    info "正在创建 systemd 服务..."
    sudo tee /etc/systemd/system/prometheus.service >/dev/null <<EOF
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=$PROM_USER
Group=$PROM_USER
Type=simple
ExecStart=$PROM_BIN \\
    --config.file=$PROM_CONFIG \\
    --storage.tsdb.path=$PROM_DATA_DIR \\
    --web.listen-address=0.0.0.0:$PROM_PORT \\
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    success "systemd 服务文件创建成功"

    info "正在启动服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now prometheus
    success "Prometheus 服务已启动并设置为开机自启"
}

# --- 创建 launchd 服务（macOS） ---
setup_launchd_service() {
    # 创建目录
    sudo mkdir -p /etc/prometheus "$PROM_DATA_DIR"

    # 写入默认配置（如果不存在）
    if [[ ! -f "$PROM_CONFIG" ]]; then
        info "正在创建默认配置 $PROM_CONFIG ..."
        sudo tee "$PROM_CONFIG" >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF
        success "默认配置已创建"
    else
        info "配置文件 $PROM_CONFIG 已存在，跳过创建"
    fi

    info "正在创建 macOS 服务..."
    sudo tee "$PROM_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PROM_PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PROM_BIN}</string>
        <string>--config.file=${PROM_CONFIG}</string>
        <string>--storage.tsdb.path=${PROM_DATA_DIR}</string>
        <string>--web.listen-address=0.0.0.0:${PROM_PORT}</string>
        <string>--web.enable-lifecycle</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/prometheus.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/prometheus.log</string>
</dict>
</plist>
EOF
    success "LaunchDaemon 服务文件创建成功"

    info "正在启动服务..."
    if sudo launchctl list 2>/dev/null | grep -q "$PROM_PLIST_LABEL"; then
        info "服务已在运行中"
    else
        if sudo launchctl bootstrap system "$PROM_PLIST" 2>/dev/null; then
            success "Prometheus 服务已启动"
        else
            warn "bootstrap 命令失败，尝试使用 load 命令"
            sudo launchctl load "$PROM_PLIST" 2>/dev/null || true
        fi
    fi
}

# --- 验证安装 ---
verify_install() {
    info "正在验证安装..."
    sleep 3

    if service_is_active prometheus "$PROM_PLIST_LABEL"; then
        success "服务运行正常"
        sleep 2
        if curl -s "http://localhost:${PROM_PORT}/-/healthy" >/dev/null; then
            success "端口 ${PROM_PORT} 响应正常"
        else
            warn "端口 ${PROM_PORT} 暂时无响应，可能需要等待几秒钟"
        fi
    else
        error "服务未正常运行"
        info "可以使用以下命令查看状态和日志："
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo "  sudo systemctl status prometheus"
            echo "  sudo journalctl -u prometheus -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            echo "  sudo launchctl list | grep prometheus"
            echo "  tail -f /var/log/prometheus.log"
        fi
    fi
}

# --- 打印安装结果 ---
print_install_summary() {
    local ip_addr
    ip_addr=$(get_local_ip)

    echo
    echo "========================================"
    success "Prometheus 安装完成！"
    echo
    info "服务信息："
    echo "  - 监听地址：http://0.0.0.0:${PROM_PORT}"
    echo "  - Web UI：http://${ip_addr}:${PROM_PORT}"
    echo "  - 配置文件：$PROM_CONFIG"
    echo "  - 数据目录：$PROM_DATA_DIR"
    echo
    info "默认采集任务："
    echo "  - prometheus: localhost:9090（自身指标）"
    echo "  - node_exporter: localhost:9100（系统指标）"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - 服务状态：sudo systemctl status prometheus"
        echo "  - 查看日志：sudo journalctl -u prometheus -f"
        echo "  - 重启服务：sudo systemctl restart prometheus"
        echo "  - 检查配置：promtool check config $PROM_CONFIG"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - 服务状态：sudo launchctl list | grep prometheus"
        echo "  - 查看日志：tail -f /var/log/prometheus.log"
        echo "  - 重启服务：sudo launchctl kickstart -k system/$PROM_PLIST_LABEL"
        echo "  - 检查配置：promtool check config $PROM_CONFIG"
    fi
}

# --- 安装主逻辑 ---
install_prometheus() {
    detect_os
    check_commands curl tar

    info "Prometheus 跨平台安装脚本"
    echo "=========================================="

    handle_existing_installation
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
    info "即将安装 Prometheus v$latest"
    info "安装位置：$PROM_BIN, $PROMTOOL_BIN"
    info "服务端口：$PROM_PORT"
    echo
    if ! yes_no "确认继续安装？"; then
        info "安装已取消"
        return 0
    fi

    # 下载并解压
    info "正在下载和解压..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    download_and_extract "$latest" "$arch_suffix" "$tmpdir" || return 1

    # 安装二进制
    install_binaries "$latest" "$arch_suffix" "$tmpdir" || return 1

    # 创建服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        setup_linux_dirs_and_config || return 1
        setup_systemd_service || return 1
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        setup_launchd_service || return 1
    fi

    # 验证与清理
    verify_install
    rm -rf "$tmpdir"
    trap - EXIT

    print_install_summary
}

# 卸载
uninstall_prometheus() {
    detect_os
    require_sudo
    info "正在卸载 Prometheus..."

    # 停止服务
    service_stop prometheus "$PROM_PLIST"

    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo rm -f /etc/systemd/system/prometheus.service
        sudo systemctl daemon-reload &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo rm -f "$PROM_PLIST"
        sudo rm -f /var/log/prometheus.log /var/log/prometheus.err
    fi

    # 删除二进制
    sudo rm -f "$PROM_BIN" "$PROMTOOL_BIN"

    # 删除用户（Linux）
    if [[ "$OS_TYPE" == "linux" ]] && id -u "$PROM_USER" &>/dev/null; then
        sudo userdel "$PROM_USER" 2>/dev/null || true
    fi

    # 询问是否删除配置和数据
    if yes_no "是否删除配置目录 /etc/prometheus？"; then
        sudo rm -rf /etc/prometheus
        success "配置目录已删除"
    else
        info "保留配置目录 /etc/prometheus"
    fi

    if yes_no "是否删除数据目录 ${PROM_DATA_DIR}（历史监控数据将丢失）？"; then
        sudo rm -rf "$PROM_DATA_DIR"
        success "数据目录已删除"
    else
        info "保留数据目录 $PROM_DATA_DIR"
    fi

    success "Prometheus 已成功卸载！"
}

# 状态
status_prometheus() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v prometheus &>/dev/null || [[ -f "$PROM_BIN" ]]; then
        is_installed=true
        version=$(prometheus --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知版本")
    fi
    if service_is_active prometheus "$PROM_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC} (v$version)"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  已安装但未运行${NC} (v$version)"
        fi
        emit_version "$version"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装或更新 Prometheus（默认动作）
  uninstall   卸载 Prometheus
  status      查看安装与运行状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_prometheus ;;
        uninstall) uninstall_prometheus ;;
        status)    status_prometheus ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
