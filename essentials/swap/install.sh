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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

SWAP_FILE="/swapfile"
SWAP_SIZE_GB=""

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "swap $(_tf 'The configuration is Linux only. Current: %s' "$OS_TYPE")"
        exit 1
    fi
    require_sudo
}

# 根据物理内存自动计算建议 swap 大小（GB）：<=2G 内存给 2 倍，否则给与内存等量（上限 8G）
suggest_size() {
    local mem_kb mem_gb
    # grep 在无 /proc/meminfo（某些容器）时返回非零；pipefail 下用 || true 兜底，mem_kb 留空后续处理
    mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || true)
    mem_kb="${mem_kb:-0}"
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
        info "$(_tf 'No size specified, based on the memory the suggestion is: %sGB' "${size_gb}")"
    fi

    if swapon --show 2>/dev/null | grep -q .; then
        warn "$(_t 'There is already a swap:')"
        swapon --show
        if ! yes_no "$(_t 'Disable it and rebuild the swap?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
        sudo swapoff "$SWAP_FILE" 2>/dev/null || sudo swapoff -a 2>/dev/null || true
    fi

    info "$(_tf '💾 Creating a %sGB swap file (%s)' "${size_gb}" "${SWAP_FILE}")"
    # fallocate 更快；不支持则回退 dd
    if ! sudo fallocate -l "${size_gb}G" "$SWAP_FILE" 2>/dev/null; then
        warn "fallocate $(_t 'Not supported, using dd (slower)...')"
        sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((size_gb * 1024)) status=progress
    fi
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE" >/dev/null
    sudo swapon "$SWAP_FILE"

    # 写入 /etc/fstab 持久化
    if ! grep -q "^$SWAP_FILE " /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
        success "$(_t 'Written to /etc/fstab (mounted automatically at boot)')"
    fi

    # swappiness：有 swap 时倾向少用（10），避免频繁交换
    if ! grep -q "vm.swappiness" /etc/sysctl.d/99-swap.conf 2>/dev/null; then
        echo "vm.swappiness = 10" | sudo tee /etc/sysctl.d/99-swap.conf >/dev/null
        sudo sysctl -p /etc/sysctl.d/99-swap.conf >/dev/null 2>&1 || true
    fi

    info "$(_t 'Verifying:')"
    free -h
    success "$(_t '🎉 The swap has been created')"
}

uninstall_swap() {
    preflight
    if ! swapon --show 2>/dev/null | grep -q "$SWAP_FILE"; then
        warn "$(_tf '%s was not found' "$SWAP_FILE")"
        return 0
    fi
    if ! yes_no "$(_tf 'Confirm disabling and deleting %s?' "${SWAP_FILE}")"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    sudo swapoff "$SWAP_FILE"
    sudo rm -f "$SWAP_FILE"
    sudo sed -i "\#^$SWAP_FILE #d" /etc/fstab
    sudo rm -f /etc/sysctl.d/99-swap.conf
    success "swap $(_t 'It has been disabled and deleted')"
}

status_swap() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (Linux only)')${NC}"; return
    fi
    if swapon --show 2>/dev/null | grep -q .; then
        emit_status "configured" "${GREEN}$(_t '✅ The swap is enabled')${NC}"
        # swapon --show 输出多行表格：机器模式不输出（仅 STATE），人类模式照常打印
        if ! uxs_is_machine_mode; then
            swapon --show
        fi
    else
        emit_status "not_configured" "${RED}$(_t '❌ The swap is not enabled')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help} [--size <GB>]  (仅 Linux)

  install     $(_t 'Create a swap (the size is computed from the memory by default, --size sets the GB)')
  uninstall   $(_t 'Disable and delete the swap file')
  status      $(_t 'View the swap status')

$(_t 'Examples:')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
