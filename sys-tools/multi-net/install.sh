#!/usr/bin/env bash
#
# multi-net/install.sh
#
# 多网卡策略路由：让指定的服务（按用户/端口）走指定的网卡出网。
# 仅 Linux。基于 策略路由(policy routing) + fwmark + iptables/ip rule。
#
# 子命令:
#   setup <网卡>          为某网卡初始化独立路由表（默认网关、脱离主表）
#   route-user <用户> <网卡>  让指定用户的所有流量走指定网卡
#   route-port <端口> <网卡>  让访问指定端口的流量走指定网卡
#   list                  查看当前策略路由规则
#   clear                 清除本脚本添加的所有策略路由规则与标记
#   status                总览
#   help
#
# 原理: 为每张网卡建独立路由表(用网卡名的 hash 作 table id),
#       用 ip rule + iptables fwmark 把目标流量导到对应表, 实现按网卡分流。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 本脚本使用的 fwmark 与路由表命名前缀
# /etc/iproute2/rt_tables 中的表名前缀
TABLE_PREFIX="multinet"
# iptables 规则注释（用于 clear 定位）
RULE_COMMENT="multinet"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "multi-net $(_tf 'Linux only. Current: %s' "$OS_TYPE")"
        exit 1
    fi
    require_sudo
    for cmd in ip iptables; do
        command_exists "$cmd" || { error "$(_tf 'The %s command is required, install iproute2 and iptables first' "$cmd")"; exit 1; }
    done
}

# 计算网卡的 table id：基于网卡名在 rt_tables 里登记的名字，用数字 id
# 简化：用网卡名的字符和作 id（落在 100-250 区间）
table_id_for() {
    local iface="$1"
    local sum=0 i ch
    for ((i=0; i<${#iface}; i++)); do
        ch=$(printf '%d' "'${iface:$i:1}")
        sum=$((sum + ch))
    done
    # 映射到 100-250
    echo $((100 + sum % 150))
}

# mark 值：每个网卡一个唯一 mark（基于 table id）
mark_for() {
    local iface="$1"
    printf '0x%x\n' "$(( $(table_id_for "$iface") << 8 ))"
}

# 确保 rt_tables 里有该网卡的表登记
ensure_rt_table() {
    local iface="$1" tid tname
    tid=$(table_id_for "$iface")
    tname="${TABLE_PREFIX}_${iface}"
    if ! grep -q "[[:space:]]$tname\$" /etc/iproute2/rt_tables 2>/dev/null; then
        echo "$tid $tname" >> /etc/iproute2/rt_tables
        info "$(_tf 'Registered routing table: %s %s' "$tid" "$tname")"
    fi
}

# 获取网卡的网关（默认路由下一跳）
gateway_for() {
    local iface="$1"
    ip route show dev "$iface" 2>/dev/null | grep default | awk '{print $3}' | head -1 || true
}

# setup <网卡>: 为网卡建独立路由表 + 默认路由
do_setup() {
    preflight
    local iface="${1:-}"
    if [[ -z "$iface" ]]; then
        error "$(_tf 'Usage: %s setup <interface>   For example: %s setup eth1' "$0" "$0")"
        exit 1
    fi
    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "$(_tf 'The interface %s does not exist. Available interfaces:' "$iface")"
        ip -br link show | awk '{print "  "$1}' >&2
        exit 1
    fi

    local tid gw mark
    tid=$(table_id_for "$iface")
    gw=$(gateway_for "$iface")
    mark=$(mark_for "$iface")

    if [[ -z "$gw" ]]; then
        error "$(_tf 'Cannot fetch the gateway of %s (the interface may have no IP/default route)' "$iface")"
        ip -br addr show "$iface" >&2
        exit 1
    fi

    ensure_rt_table "$iface"

    info "$(_tf 'Configuring an independent routing table for %s (table %s, gw %s, mark %s)' "$iface" "$tid" "$gw" "$mark")"
    # 表内默认路由：从该网卡经其网关出
    ip route replace default via "$gw" dev "$iface" table "$tid" 2>/dev/null || true
    # 确保本网卡网段直连在该表
    local net
    net=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -1)
    if [[ -n "$net" ]]; then
        ip route replace "$net" dev "$iface" table "$tid" 2>/dev/null || true
    fi

    # 规则：带该 mark 的包查该表
    if ! ip rule show 2>/dev/null | grep -q "fwmark $mark"; then
        ip rule add fwmark "$mark" table "$tid"
        info "$(_tf 'Rule added: fwmark %s -> table %s' "$mark" "$tid")"
    fi

    success "$iface $(_tf 'The policy routing table is ready (the traffic marked %s goes through %s)' "$mark" "${iface}")"
    info "$(_t 'Use route-user / route-port later to send the traffic through that interface')"
}

# route-user <用户> <网卡>: 让某用户的流量打上该网卡 mark
do_route_user() {
    preflight
    local user="${1:-}" iface="${2:-}"
    if [[ -z "$user" ]] || [[ -z "$iface" ]]; then
        error "$(_tf 'Usage: %s route-user <user> <interface>' "$0")"
        exit 1
    fi
    local uid
    uid=$(id -u "$user" 2>/dev/null) || { error "$(_tf 'The user %s does not exist' "$user")"; exit 1; }
    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "$(_tf 'The interface %s does not exist' "$iface")"; exit 1
    fi
    # 确保该网卡已 setup
    if ! ip rule show 2>/dev/null | grep -q "$(mark_for "$iface")"; then
        warn "$iface $(_t 'Not set up yet, run setup first')"
        do_setup "$iface"
    fi
    local mark tid
    mark=$(mark_for "$iface")
    tid=$(table_id_for "$iface")

    info "$(_tf 'Send the traffic of the user %s (uid %s) through %s' "$user" "$uid" "$iface")"
    iptables -t mangle -A OUTPUT -m owner --uid-owner "$uid" -j MARK --set-mark "$mark" \
        -m comment --comment "$RULE_COMMENT"
    # 回程包也标记（POSTROUTING 不需要，OUTPUT 标记已够路由决策）
    success "$(_tf 'Set: the outbound traffic of the user %s goes through %s' "$user" "$iface")"
    info "$(_tf 'Verify: run curl ifconfig.me as %s, it should show the public IP of %s' "$user" "$iface")"
}

# route-port <端口> <网卡>: 让访问指定目的端口的流量走指定网卡
do_route_port() {
    preflight
    local port="${1:-}" iface="${2:-}"
    if [[ -z "$port" ]] || [[ -z "$iface" ]]; then
        error "$(_tf 'Usage: %s route-port <destination port> <interface>   For example: %s route-port 443 eth1' "$0" "$0")"
        exit 1
    fi
    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "$(_tf 'The interface %s does not exist' "$iface")"; exit 1
    fi
    if ! ip rule show 2>/dev/null | grep -q "$(mark_for "$iface")"; then
        warn "$iface $(_t 'Not set up yet, run setup first')"
        do_setup "$iface"
    fi
    local mark
    mark=$(mark_for "$iface")

    info "$(_tf 'Send the outbound traffic to the destination port %s through %s' "$port" "$iface")"
    iptables -t mangle -A OUTPUT -p tcp --dport "$port" -j MARK --set-mark "$mark" \
        -m comment --comment "$RULE_COMMENT"
    success "$(_tf 'Set: the outbound traffic to the destination port %s goes through %s' "$port" "$iface")"
}

do_list() {
    preflight
    info "=== $(_t 'Policy routing rules (ip rule) ===')"
    ip rule show | grep -E "fwmark|$(table_id_for eth0 2>/dev/null)" 2>/dev/null || ip rule show
    echo
    info "=== mangle $(_t 'Table MARK rules (iptables) ===')"
    iptables -t mangle -L OUTPUT -v -n 2>/dev/null | grep -E "MARK|$RULE_COMMENT" || echo "  $(_t '(none)')"
}

# clear: 清除本脚本添加的所有规则
do_clear() {
    preflight
    if ! yes_no "$(_t 'Confirm clearing all the multi-net policy routing rules and marks?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    info "$(_t 'Clearing the iptables mangle MARK rules...')"
    while iptables -t mangle -D OUTPUT -m comment --comment "$RULE_COMMENT" 2>/dev/null; do :; done
    # 循环删除所有带该 comment 的规则（不同 mark）
    info "$(_t 'Clearing the ip rule fwmark rules...')"
    local tid
    for tid in $(seq 100 250); do
        ip rule del table "$tid" 2>/dev/null || true
        ip rule del fwmark "0x$((tid << 8))" 2>/dev/null || true
    done 2>/dev/null || true
    # 更精确：从 ip rule 输出里提取 fwmark 删除
    ip rule show 2>/dev/null | grep "fwmark" | while read -r line; do
        local m
        m=$(echo "$line" | grep -oE 'fwmark 0x[0-9a-f]+' | awk '{print $2}')
        if [[ -n "$m" ]]; then
            ip rule del fwmark "$m" 2>/dev/null || true
        fi
    done
    success "$(_t 'The multi-net rules are cleared (the routing table entries are kept, setup can reuse them)')"
}

status_multinet() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (Linux only)')${NC}"; return 0
    fi
    local rules=0 marks=0
    rules=$(ip rule show 2>/dev/null | grep -c "fwmark" || true)
    marks=$(iptables -t mangle -L OUTPUT 2>/dev/null | grep -c "$RULE_COMMENT" || true)
    if [[ ${rules:-0} -gt 0 ]] || [[ ${marks:-0} -gt 0 ]]; then
        emit_status "configured" "${GREEN}$(_t '✅ Configured')${NC}$(_tf '(%s routing rules, %s mark rules)' "$rules" "$marks")"
    else
        emit_status "not_configured" "${RED}$(_t '❌ Not configured')${NC}"
    fi
    emit_extra "rules=$rules"
    emit_extra "marks=$marks"
}

usage() {
    cat <<EOF
用法: $0 {setup|route-user|route-port|list|clear|status|help}  (仅 Linux)

$(_t 'Multi-NIC policy routing: send the traffic of a given service/user/port through a given interface.')

  setup <$(_t 'interface>               initialize an independent routing table for the interface')
  route-user <$(_t 'user> <interface>   send all the traffic of a user through the given interface')
  route-port <$(_t 'port> <interface>   send the traffic to the given destination port through the given interface')
  list                       $(_t 'Show the current policy routing rules')
  clear                      $(_t 'Clear all the rules added by this script')
  status                     $(_t 'Overview')

$(_t 'Examples:')
  $0 setup eth1                       $(_t '# Initialize the eth1 policy routing')
  $0 route-user www-data eth1         $(_t '# www-data The user traffic goes through eth1')
  $0 route-port 443 eth1              $(_t '# The traffic to port 443 goes through eth1')
EOF
}

main() {
    local action="${1:-help}"
    detect_os
    case "$action" in
        setup)      shift; do_setup "$@" ;;
        route-user) shift; do_route_user "$@" ;;
        route-port) shift; do_route_port "$@" ;;
        list)       do_list ;;
        clear)      do_clear ;;
        # 等价 clear：移除全部 multinet iptables/ip-rule 规则
        uninstall)  do_clear ;;
        status)     status_multinet ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
