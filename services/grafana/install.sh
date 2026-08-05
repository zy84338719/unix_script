#!/usr/bin/env bash
set -e

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
GRAFANA_PORT=3000
GRAFANA_PLIST="/Library/LaunchDaemons/com.grafana.grafana.plist"
GRAFANA_PLIST_LABEL="com.grafana.grafana"

# --- 添加 Grafana APT 仓库 ---
setup_apt_repo() {
    info "正在添加 Grafana APT 仓库..."

    # 安装依赖
    pkg_install apt-transport-https software-properties-common wget gnupg2 2>/dev/null || true

    # 添加 GPG 密钥
    if [[ ! -f /etc/apt/keyrings/grafana.gpg ]]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg >/dev/null
        success "GPG 密钥已添加"
    fi

    # 添加仓库
    if [[ ! -f /etc/apt/sources.list.d/grafana.list ]]; then
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list >/dev/null
        success "APT 仓库已添加"
    fi

    sudo apt-get update -y
}

# --- 添加 Grafana YUM/DNF 仓库 ---
setup_yum_repo() {
    info "正在添加 Grafana YUM/DNF 仓库..."

    if [[ ! -f /etc/yum.repos.d/grafana.repo ]]; then
        sudo tee /etc/yum.repos.d/grafana.repo >/dev/null <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=0
enabled=1
gpgcheck=0
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        success "YUM/DNF 仓库已添加"
    fi

    if command_exists dnf; then
        sudo dnf makecache
    else
        sudo yum makecache
    fi
}

# --- 安装 Grafana（Linux APT/YUM） ---
install_grafana_linux() {
    detect_pkg_manager

    case "$PKG_MANAGER" in
        apt-get)
            setup_apt_repo
            info "正在安装 Grafana..."
            sudo apt-get install -y grafana
            ;;
        dnf|yum)
            setup_yum_repo
            info "正在安装 Grafana..."
            if command_exists dnf; then
                sudo dnf install -y grafana
            else
                sudo yum install -y grafana
            fi
            ;;
        *)
            error "不支持的包管理器：$PKG_MANAGER"
            error "Grafana Linux 安装仅支持 APT 和 DNF/YUM"
            return 1
            ;;
    esac

    success "Grafana 软件包安装完成"

    # 启动服务
    info "正在启动 Grafana 服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now grafana-server
    success "Grafana 服务已启动并设置为开机自启"
}

# --- 安装 Grafana（macOS brew） ---
install_grafana_macos() {
    if ! command_exists brew; then
        error "macOS 上需要 Homebrew，请先安装 Homebrew"
        return 1
    fi

    info "正在通过 Homebrew 安装 Grafana..."
    brew install grafana

    info "正在启动 Grafana 服务..."
    brew services start grafana
    success "Grafana 服务已启动"
}

# --- 验证安装 ---
verify_install() {
    info "正在验证安装..."
    sleep 4

    local is_running=false
    if service_is_active grafana-server "$GRAFANA_PLIST_LABEL"; then
        is_running=true
    fi

    if $is_running; then
        success "服务运行正常"
        if curl -s "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null; then
            success "端口 ${GRAFANA_PORT} 响应正常"
        else
            warn "端口 ${GRAFANA_PORT} 暂时无响应，可能需要等待几秒钟"
        fi
    else
        error "服务未正常运行"
        if [[ "$OS_TYPE" == "linux" ]]; then
            info "查看日志：sudo journalctl -u grafana-server -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            info "查看日志：brew services log grafana"
        fi
    fi
}

# --- 打印安装结果 ---
print_install_summary() {
    local ip_addr
    ip_addr=$(get_local_ip)

    echo
    echo "========================================"
    success "Grafana 安装完成！"
    echo
    info "访问地址："
    echo "  - Web UI：http://${ip_addr}:${GRAFANA_PORT}"
    echo
    info "默认登录凭据："
    echo "  - 用户名：admin"
    echo "  - 密码：admin"
    echo "  （首次登录后会提示修改密码）"
    echo
    info "添加 Prometheus 数据源："
    echo "  1. 登录 Grafana 后，进入 Configuration -> Data Sources"
    echo "  2. 点击 \"Add data source\"，选择 Prometheus"
    echo "  3. URL 填写：http://localhost:9090"
    echo "  4. 点击 \"Save & Test\" 验证连接"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - 服务状态：sudo systemctl status grafana-server"
        echo "  - 查看日志：sudo journalctl -u grafana-server -f"
        echo "  - 重启服务：sudo systemctl restart grafana-server"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - 服务状态：brew services info grafana"
        echo "  - 查看日志：brew services log grafana"
        echo "  - 重启服务：brew services restart grafana"
    fi
}

# --- 安装主逻辑 ---
install_grafana() {
    detect_os

    info "Grafana 跨平台安装脚本"
    echo "=========================================="

    # 检查是否已安装
    if command_exists grafana-server || command_exists grafana; then
        warn "检测到已安装 Grafana"
        if ! yes_no "是否继续并覆盖安装？"; then
            info "安装已取消"
            return 0
        fi
    fi

    require_sudo

    # 确认安装
    echo
    info "即将安装 Grafana"
    info "服务端口：$GRAFANA_PORT"
    echo
    if ! yes_no "确认继续安装？"; then
        info "安装已取消"
        return 0
    fi

    # 根据平台安装
    if [[ "$OS_TYPE" == "darwin" ]]; then
        install_grafana_macos || return 1
    else
        install_grafana_linux || return 1
    fi

    # 验证
    verify_install

    # 打印结果
    print_install_summary
}

# 卸载
uninstall_grafana() {
    detect_os
    require_sudo
    info "正在卸载 Grafana..."

    # 停止服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop grafana-server &>/dev/null || true
        sudo systemctl disable grafana-server &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            brew services stop grafana 2>/dev/null || true
        fi
    fi

    # 卸载软件包
    if [[ "$OS_TYPE" == "linux" ]]; then
        pkg_remove grafana 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/grafana.list
        sudo rm -f /etc/apt/keyrings/grafana.gpg
        sudo rm -f /etc/yum.repos.d/grafana.repo
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            brew uninstall grafana 2>/dev/null || true
        fi
        sudo rm -f "$GRAFANA_PLIST"
    fi

    if yes_no "是否删除 Grafana 数据目录（/var/lib/grafana，仪表盘和数据源配置将丢失）？"; then
        sudo rm -rf /var/lib/grafana
        sudo rm -rf /etc/grafana
        success "数据目录已删除"
    else
        info "保留数据目录"
    fi

    success "Grafana 已成功卸载！"
}

# 状态
status_grafana() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v grafana-server &>/dev/null; then
        is_installed=true
        version=$(grafana-server --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知版本")
    elif command -v grafana &>/dev/null; then
        is_installed=true
        version=$(grafana --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知版本")
    elif [[ "$OS_TYPE" == "darwin" ]] && command_exists brew && brew list grafana &>/dev/null; then
        is_installed=true
        version=$(brew info grafana 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "未知版本")
    fi
    if service_is_active grafana-server "$GRAFANA_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} (v$version)"
        else
            echo -e "${YELLOW}⚠️  已安装但未运行${NC} (v$version)"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装或更新 Grafana（默认动作）
  uninstall   卸载 Grafana
  status      查看安装与运行状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_grafana ;;
        uninstall) uninstall_grafana ;;
        status)    status_grafana ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
