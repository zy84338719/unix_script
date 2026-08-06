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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 本脚本使用的 fwmark 与路由表命名前缀
TABLE_PREFIX="multinet"  # /etc/iproute2/rt_tables 中的表名前缀
RULE_COMMENT="multinet"  # iptables 规则注释（用于 clear 定位）

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "multi-net 仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    require_sudo
    for cmd in ip iptables; do
        command_exists "$cmd" || { error "需要 '$cmd' 命令，请先安装 iproute2 与 iptables"; exit 1; }
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
        info "已登记路由表: $tid $tname"
    fi
}

# 获取网卡的网关（默认路由下一跳）
gateway_for() {
    local iface="$1"
    ip route show dev "$iface" 2>/dev/null | grep default | awk '{print $3}' | head -1
}

# setup <网卡>: 为网卡建独立路由表 + 默认路由
do_setup() {
    preflight
    local iface="${1:-}"
    if [[ -z "$iface" ]]; then
        error "用法: $0 setup <网卡名>   例如: $0 setup eth1"
        exit 1
    fi
    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "网卡 $iface 不存在。可用网卡:"
        ip -br link show | awk '{print "  "$1}' >&2
        exit 1
    fi

    local tid gw mark
    tid=$(table_id_for "$iface")
    gw=$(gateway_for "$iface")
    mark=$(mark_for "$iface")

    if [[ -z "$gw" ]]; then
        error "无法获取 $iface 的网关（该网卡可能未配置 IP/默认路由）"
        ip -br addr show "$iface" >&2
        exit 1
    fi

    ensure_rt_table "$iface"

    info "为 $iface 配置独立路由表 (table $tid, gw $gw, mark $mark)"
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
        info "已添加规则: fwmark $mark -> table $tid"
    fi

    success "$iface 策略路由表已就绪（标记 $mark 的流量将走 $iface）"
    info "后续用 route-user / route-port 指定流量走该网卡"
}

# route-user <用户> <网卡>: 让某用户的流量打上该网卡 mark
do_route_user() {
    preflight
    local user="${1:-}" iface="${2:-}"
    if [[ -z "$user" ]] || [[ -z "$iface" ]]; then
        error "用法: $0 route-user <用户名> <网卡>"
        exit 1
    fi
    local uid
    uid=$(id -u "$user" 2>/dev/null) || { error "用户 $user 不存在"; exit 1; }
    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "网卡 $iface 不存在"; exit 1
    fi
    # 确保该网卡已 setup
    if ! ip rule show 2>/dev/null | grep -q "$(mark_for "$iface")"; then
        warn "$iface 尚未 setup，先执行 setup"
        do_setup "$iface"
    fi
    local mark tid
    mark=$(mark_for "$iface")
    tid=$(table_id_for "$iface")

    info "让用户 $user (uid $uid) 的流量走 $iface"
    iptables -t mangle -A OUTPUT -m owner --uid-owner "$uid" -j MARK --set-mark "$mark" \
        -m comment --comment "$RULE_COMMENT"
    # 回程包也标记（POSTROUTING 不需要，OUTPUT 标记已够路由决策）
    success "已设置: 用户 $user 的出站流量走 $iface"
    info "验证: 以 $user 身份 curl ifconfig.me，应显示 $iface 的公网 IP"
}

# route-port <端口> <网卡>: 让访问指定目的端口的流量走指定网卡
do_route_port() {
    preflight
    local port="${1:-}" iface="${2:-}"
    if [[ -z "$port" ]] || [[ -z "$iface" ]]; then
        error "用法: $0 route-port <目的端口> <网卡>   例如: $0 route-port 443 eth1"
        exit 1
    fi
    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "网卡 $iface 不存在"; exit 1
    fi
    if ! ip rule show 2>/dev/null | grep -q "$(mark_for "$iface")"; then
        warn "$iface 尚未 setup，先执行 setup"
        do_setup "$iface"
    fi
    local mark
    mark=$(mark_for "$iface")

    info "让目的端口 $port 的出站流量走 $iface"
    iptables -t mangle -A OUTPUT -p tcp --dport "$port" -j MARK --set-mark "$mark" \
        -m comment --comment "$RULE_COMMENT"
    success "已设置: 目的端口 $port 的出站流量走 $iface"
}

do_list() {
    preflight
    info "=== 策略路由规则 (ip rule) ==="
    ip rule show | grep -E "fwmark|$(table_id_for eth0 2>/dev/null)" 2>/dev/null || ip rule show
    echo
    info "=== mangle 表 MARK 规则 (iptables) ==="
    iptables -t mangle -L OUTPUT -v -n 2>/dev/null | grep -E "MARK|$RULE_COMMENT" || echo "  （无）"
}

# clear: 清除本脚本添加的所有规则
do_clear() {
    preflight
    if ! yes_no "确认清除所有 multi-net 策略路由规则与标记？"; then
        info "已取消"; return 0
    fi
    info "清除 iptables mangle MARK 规则..."
    while iptables -t mangle -D OUTPUT -m comment --comment "$RULE_COMMENT" 2>/dev/null; do :; done
    # 循环删除所有带该 comment 的规则（不同 mark）
    info "清除 ip rule fwmark 规则..."
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
    success "已清除 multi-net 规则（路由表条目保留，可重新 setup 复用）"
}

status_multinet() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return 0
    fi
    local rules=0 marks=0
    rules=$(ip rule show 2>/dev/null | grep -c "fwmark" || true)
    marks=$(iptables -t mangle -L OUTPUT 2>/dev/null | grep -c "$RULE_COMMENT" || true)
    if [[ ${rules:-0} -gt 0 ]] || [[ ${marks:-0} -gt 0 ]]; then
        emit_status "configured" "${GREEN}✅ 已配置${NC}（$rules 条路由规则, $marks 条标记规则）"
    else
        emit_status "not_configured" "${RED}❌ 未配置${NC}"
    fi
    emit_extra "rules=$rules"
    emit_extra "marks=$marks"
}

usage() {
    cat <<EOF
用法: $0 {setup|route-user|route-port|list|clear|status|help}  (仅 Linux)

多网卡策略路由: 让指定服务/用户/端口走指定网卡出网。

  setup <网卡>               为网卡初始化独立路由表
  route-user <用户> <网卡>   让某用户的所有流量走指定网卡
  route-port <端口> <网卡>   让访问指定目的端口的流量走指定网卡
  list                       查看当前策略路由规则
  clear                      清除本脚本添加的所有规则
  status                     总览

示例:
  $0 setup eth1                       # 初始化 eth1 策略路由
  $0 route-user www-data eth1         # www-data 用户的流量走 eth1
  $0 route-port 443 eth1              # 访问 443 端口的流量走 eth1
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
        status)     status_multinet ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
