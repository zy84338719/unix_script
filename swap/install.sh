#!/usr/bin/env bash
#
# swap/install.sh
#
# 创建/调整 swap 交换文件，适合小内存 VPS 装机。仅 Linux。
#
# 子命令：install | uninstall | status | help
#
# install 支持 --size <GB> 指定大小（默认根据内存自动计算）。
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SWAP_FILE="/swapfile"
SWAP_SIZE_GB=""

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "swap 配置仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    require_sudo
}

# 根据物理内存自动计算建议 swap 大小（GB）：<=2G 内存给 2 倍，否则给与内存等量（上限 8G）
suggest_size() {
    local mem_kb mem_gb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_gb=$((mem_kb / 1024 / 1024))
    local swap_gb
    if [[ $mem_gb -le 2 ]]; then
        swap_gb=$((mem_gb * 2))
    else
        swap_gb=$mem_gb
    fi
    [[ $swap_gb -gt 8 ]] && swap_gb=8
    [[ $swap_gb -lt 1 ]] && swap_gb=1
    echo "$swap_gb"
}

install_swap() {
    preflight
    # 解析 --size
    local size_gb
    size_gb="$SWAP_SIZE_GB"
    if [[ -z "$size_gb" ]]; then
        size_gb=$(suggest_size)
        info "未指定大小，根据内存建议：${size_gb}GB"
    fi

    if swapon --show 2>/dev/null | grep -q .; then
        warn "当前已有 swap："
        swapon --show
        if ! yes_no "是否禁用并重建 swap？"; then
            info "已取消"; return 0
        fi
        sudo swapoff "$SWAP_FILE" 2>/dev/null || sudo swapoff -a 2>/dev/null || true
    fi

    info "💾 创建 ${size_gb}GB swap 文件（$SWAP_FILE）"
    # fallocate 更快；不支持则回退 dd
    if ! sudo fallocate -l "${size_gb}G" "$SWAP_FILE" 2>/dev/null; then
        warn "fallocate 不支持，使用 dd（较慢）..."
        sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((size_gb * 1024)) status=progress
    fi
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE" >/dev/null
    sudo swapon "$SWAP_FILE"

    # 写入 /etc/fstab 持久化
    if ! grep -q "^$SWAP_FILE " /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
        success "已写入 /etc/fstab（开机自动挂载）"
    fi

    # swappiness：有 swap 时倾向少用（10），避免频繁交换
    if ! grep -q "vm.swappiness" /etc/sysctl.d/99-swap.conf 2>/dev/null; then
        echo "vm.swappiness = 10" | sudo tee /etc/sysctl.d/99-swap.conf >/dev/null
        sudo sysctl -p /etc/sysctl.d/99-swap.conf >/dev/null 2>&1 || true
    fi

    info "验证："
    free -h
    success "🎉 swap 创建完成"
}

uninstall_swap() {
    preflight
    if ! swapon --show 2>/dev/null | grep -q "$SWAP_FILE"; then
        warn "未发现 $SWAP_FILE"
        return 0
    fi
    if ! yes_no "确认禁用并删除 $SWAP_FILE？"; then
        info "已取消"; return 0
    fi
    sudo swapoff "$SWAP_FILE"
    sudo rm -f "$SWAP_FILE"
    sudo sed -i "\#^$SWAP_FILE #d" /etc/fstab
    sudo rm -f /etc/sysctl.d/99-swap.conf
    success "swap 已禁用并删除"
}

status_swap() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if swapon --show 2>/dev/null | grep -q .; then
        echo -e "${GREEN}✅ 已启用 swap${NC}"
        swapon --show
    else
        echo -e "${RED}❌ 未启用 swap${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help} [--size <GB>]  (仅 Linux)

  install     创建 swap（默认根据内存自动计算大小，可用 --size 指定 GB）
  uninstall   禁用并删除 swap 文件
  status      查看 swap 状态

示例:
  $0 install --size 4
EOF
}

main() {
    local action="${1:-help}"
    shift || true
    # 解析剩余参数（--size）
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --size) SWAP_SIZE_GB="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    detect_os
    case "$action" in
        install)   install_swap ;;
        uninstall) uninstall_swap ;;
        status)    status_swap ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
