#!/usr/bin/env bash
#
# uninstall.sh
#
# 一键卸载入口：遍历所有模块，逐个询问是否卸载。
#
# 用法:
#   ./uninstall.sh             # 交互式逐项询问
#   ./uninstall.sh --all       # 卸载全部（需二次确认）
#   ./uninstall.sh <模块名>    # 仅卸载指定模块（同 install.sh 的模块名）
#   ./uninstall.sh -h          # 帮助
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# 卸载单个模块（封装确认）
ask_and_uninstall() {
    local label="$1"; shift
    if yes_no "确认卸载 $label？"; then
        info "卸载 $label ..."
        "$@"
        success "$label 卸载流程结束。"
    else
        info "跳过 $label"
    fi
    echo
}

uninstall_all() {
    warn "⚠️  即将卸载所有已安装的服务与环境！此操作不可逆。"
    if ! yes_no "再次确认卸载全部？"; then
        info "已取消"
        exit 0
    fi
    uninstall_node_exporter_all
    uninstall_ddns_all
    uninstall_wireguard_all
    uninstall_tailscale_all
    uninstall_docker_all
    uninstall_fail2ban_all
    uninstall_shutdown_all
    uninstall_pm_all
    echo
    success "全部卸载流程结束。"
    info "Zsh & Oh My Zsh 为敏感操作，未自动卸载，请参考 README 手动处理。"
}

# 复用各模块/主菜单的卸载逻辑
uninstall_node_exporter_all() {
    if command -v node_exporter >/dev/null 2>&1 || [ -f /usr/local/bin/node_exporter ]; then
        # 通过主菜单 install.sh 的卸载函数不可直接调用，这里内联精简逻辑
        info "卸载 Node Exporter..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo systemctl stop node_exporter &>/dev/null || true
            sudo systemctl disable node_exporter &>/dev/null || true
            sudo rm -f /etc/systemd/system/node_exporter.service
            sudo systemctl daemon-reload &>/dev/null || true
            sudo rm -f /usr/local/bin/node_exporter
            id "node_exporter" &>/dev/null && sudo userdel node_exporter
        else
            sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist &>/dev/null || true
            sudo rm -f /Library/LaunchDaemons/com.prometheus.node_exporter.plist
            sudo rm -f /usr/local/bin/node_exporter /var/log/node_exporter.log /var/log/node_exporter.err
        fi
    fi
}

uninstall_ddns_all() {
    if [ -f /opt/ddns-go/ddns-go ]; then
        info "卸载 DDNS-GO..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo systemctl stop ddns-go &>/dev/null || true
            sudo systemctl disable ddns-go &>/dev/null || true
            sudo systemctl daemon-reload
        else
            sudo launchctl bootout system /Library/LaunchDaemons/jeessy.ddns-go.plist &>/dev/null || true
            sudo rm -f /Library/LaunchDaemons/jeessy.ddns-go.plist
        fi
        sudo rm -rf /opt/ddns-go
    fi
}

uninstall_wireguard_all() { [ -f "$SCRIPT_DIR/wireguard/install.sh" ] && bash "$SCRIPT_DIR/wireguard/install.sh" uninstall_service; }
uninstall_tailscale_all() { [ -f "$SCRIPT_DIR/tailscale/install.sh" ] && ask_and_uninstall "Tailscale" bash "$SCRIPT_DIR/tailscale/install.sh" uninstall; }
uninstall_docker_all()    { [ -f "$SCRIPT_DIR/docker/install.sh" ]    && ask_and_uninstall "Docker"    bash "$SCRIPT_DIR/docker/install.sh" uninstall; }
uninstall_fail2ban_all()  { [ -f "$SCRIPT_DIR/fail2ban/install.sh" ]  && ask_and_uninstall "Fail2ban"  bash "$SCRIPT_DIR/fail2ban/install.sh" uninstall; }
uninstall_shutdown_all()  {
    local sp="$SCRIPT_DIR/shutdown_timer/shutdown_timer.sh"
    [ -f "$sp" ] && chmod +x "$sp" && "$sp" cancel_daily_shutdown_internal
}
uninstall_pm_all() {
    [ -f "$SCRIPT_DIR/process_manager_tool/install_process_manager.sh" ] && \
        run_in_dir process_manager_tool install_process_manager.sh uninstall
}

show_usage() {
    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help    显示本帮助
  --all         卸载全部已安装项（需二次确认）

模块名:
  node_exporter | ddns-go | wireguard | tailscale | docker |
  fail2ban | shutdown_timer | process_manager

示例:
  $0                  # 逐项交互询问
  $0 docker           # 仅卸载 docker
  $0 --all            # 卸载全部
EOF
}

run_in_dir() { ( cd "$SCRIPT_DIR/$1" && shift && bash "$@" ); }

dispatch() {
    local name="$1"
    case "$name" in
        node_exporter|nodeexporter) uninstall_node_exporter_all ;;
        ddns-go|ddnsgo|ddns)        uninstall_ddns_all ;;
        wireguard|wg)               uninstall_wireguard_all ;;
        tailscale|ts)               ask_and_uninstall "Tailscale" bash "$SCRIPT_DIR/tailscale/install.sh" uninstall ;;
        docker)                     ask_and_uninstall "Docker"    bash "$SCRIPT_DIR/docker/install.sh" uninstall ;;
        fail2ban|f2b)               ask_and_uninstall "Fail2ban"  bash "$SCRIPT_DIR/fail2ban/install.sh" uninstall ;;
        shutdown|shutdown_timer)    uninstall_shutdown_all ;;
        process_manager|pm)         uninstall_pm_all ;;
        *) error "未知模块: $name"; show_usage; exit 1 ;;
    esac
}

interactive_all() {
    detect_os
    header "🗑️  一键卸载（逐项询问）"
    echo "========================================"
    echo
    if command -v node_exporter >/dev/null 2>&1 || [ -f /usr/local/bin/node_exporter ]; then
        ask_and_uninstall "Node Exporter" uninstall_node_exporter_all
    fi
    if [ -f /opt/ddns-go/ddns-go ]; then
        ask_and_uninstall "DDNS-GO" uninstall_ddns_all
    fi
    ask_and_uninstall "WireGuard 服务"  bash "$SCRIPT_DIR/wireguard/install.sh" uninstall_service
    ask_and_uninstall "Tailscale"       bash "$SCRIPT_DIR/tailscale/install.sh" uninstall
    ask_and_uninstall "Docker"          bash "$SCRIPT_DIR/docker/install.sh" uninstall
    ask_and_uninstall "Fail2ban"        bash "$SCRIPT_DIR/fail2ban/install.sh" uninstall
    uninstall_shutdown_all
    ask_and_uninstall "进程管理工具"    bash "$SCRIPT_DIR/process_manager_tool/install_process_manager.sh" uninstall
    echo
    success "卸载流程结束。"
}

main() {
    detect_os
    if [[ $# -eq 0 ]]; then
        interactive_all
        exit 0
    fi
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        --all)     uninstall_all ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)         dispatch "$1" ;;
    esac
}

main "$@"
