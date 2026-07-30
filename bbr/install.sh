#!/usr/bin/env bash
#
# bbr/install.sh
#
# 开启 TCP BBR 拥塞控制算法，提升网络吞吐（尤其高延迟/丢包链路）。仅 Linux。
# 要求内核 >= 4.9（BBR 自 4.9 起内置）。
#
# 子命令：install(enable) | uninstall(disable) | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SYSCTL_FILE=/etc/sysctl.d/99-bbr.conf

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "BBR 仅支持 Linux（内核功能）。当前：$OS_TYPE"
        exit 1
    fi
}

check_kernel() {
    local kver
    kver=$(uname -r | cut -d. -f1-2)
    local major minor
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)
    if [[ "$major" -lt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -lt 9 ]]; }; then
        error "内核版本 $kver 过低，BBR 需要内核 >= 4.9"
        exit 1
    fi
}

enable_bbr() {
    preflight
    require_sudo
    check_kernel
    info "🚀 开启 TCP BBR 拥塞控制"

    # 检查内核是否支持 bbr 模块
    if ! modprobe tcp_bbr 2>/dev/null && ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
        warn "tcp_bbr 模块加载失败，可能内核未编译 BBR 支持。将尝试写入配置并重载。"
    fi

    sudo tee "$SYSCTL_FILE" >/dev/null <<'EOF'
# 由 unix_script bbr 模块生成 —— 开启 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true

    local algo
    algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$algo" == "bbr" ]]; then
        success "BBR 已开启（当前拥塞控制算法：bbr）"
    else
        error "BBR 开启失败，当前算法仍为：$algo"
        return 1
    fi
    info "队列规则：$(sysctl -n net.core.default_qdisc 2>/dev/null)"
}

disable_bbr() {
    preflight
    require_sudo
    if [[ ! -f "$SYSCTL_FILE" ]]; then
        warn "未找到 BBR 配置文件，可能未启用 BBR"
        return 0
    fi
    sudo rm -f "$SYSCTL_FILE"
    # 恢复默认算法（cubic 是大多数发行版默认）
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    sudo sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || \
        sudo sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
    success "BBR 已关闭（恢复默认拥塞控制）"
}

status_bbr() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    local algo qdisc
    algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    if [[ "$algo" == "bbr" ]]; then
        echo -e "${GREEN}✅ BBR 已开启${NC}（qdisc=$qdisc）"
    else
        echo -e "${YELLOW}⚠️  未开启 BBR${NC}（当前算法：$algo）"
    fi
}

usage() {
    cat <<EOF
用法: $0 {enable|disable|status|help}  (仅 Linux, 内核 >= 4.9)

  enable, install    开启 TCP BBR
  disable, uninstall 关闭 BBR（恢复默认）
  status             查看当前拥塞控制算法
EOF
}

main() {
    local action="${1:-enable}"
    detect_os
    case "$action" in
        enable|install)    enable_bbr ;;
        disable|uninstall) disable_bbr ;;
        status)            status_bbr ;;
        help|--help|-h)    usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
