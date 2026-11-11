#!/usr/bin/env bash
#
# nat/install.sh
#
# NAT 端口转发与共享上网管理工具（仅 Linux）。
#
# 功能：
#   - DNAT 端口转发：外部端口 → 本机/内网机器的端口
#   - SNAT/MASQUERADE：让内网机器通过本机共享上网
#   - 规则持久化：systemd service 启动时自动加载
#
# 子命令：
#   install                              安装依赖、开启 IP forwarding、配置持久化
#   uninstall                            清除规则、关闭 IP forwarding、移除持久化
#   forward add <端口> <目标:端口> [--proto tcp|udp]  添加 DNAT 转发
#   forward del <端口> [--proto tcp|udp]               删除 DNAT 转发
#   forward list                                      列出所有转发规则
#   gateway enable <网卡> [--source CIDR]              开启 MASQUERADE
#   gateway disable <网卡>                             关闭 MASQUERADE
#   status                                            总览
#   help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# ---------------- 配置常量 ----------------
CONF_DIR="/etc/nat-manager"
RULES_FILE="$CONF_DIR/rules.conf"
GATEWAY_FILE="$CONF_DIR/gateway.conf"
SYSCTL_FILE="/etc/sysctl.d/99-nat-manager.conf"
SERVICE_FILE="/etc/systemd/system/nat-manager.service"
COMMENT_PREFIX="nat-manager"

# ---------------- 前置检查 ----------------
preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "nat $(_tf 'The nat module is Linux-only. Current: %s' "$OS_TYPE")"
        exit 1
    fi
    require_sudo
}

# 确保 iptables 可用
ensure_iptables() {
    if ! command_exists iptables; then
        error "$(_t 'The iptables command was not found, please install it first:')"
        echo "  apt-get install -y iptables    # Debian/Ubuntu"
        echo "  dnf install -y iptables         # CentOS/RHEL"
        exit 1
    fi
}

# 确保配置目录存在
ensure_conf_dir() {
    if [[ ! -d "$CONF_DIR" ]]; then
        sudo mkdir -p "$CONF_DIR"
    fi
}

# ---------------- IP Forwarding ----------------

enable_ip_forwarding() {
    info "$(_t 'Enabling IP forwarding...')"
    # 立即生效
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    # 持久化
    echo "net.ipv4.ip_forward = 1" | sudo tee "$SYSCTL_FILE" >/dev/null
    success "IP forwarding $(_t 'Enabled')"
}

disable_ip_forwarding() {
    info "$(_t 'Disabling IP forwarding...')"
    sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
    sudo rm -f "$SYSCTL_FILE"
    success "IP forwarding $(_t 'Disabled')"
}

# ---------------- 规则文件操作 ----------------

# 规则文件格式：每行 "端口 协议 目标IP:目标端口"
# 例：8443 tcp 192.168.1.100:443

# 检查规则是否存在
rule_exists() {
    local port="$1" proto="$2"
    [[ -f "$RULES_FILE" ]] && grep -qE "^${port}\s+${proto}\s+" "$RULES_FILE"
}

# 添加规则到文件
add_rule_to_file() {
    local port="$1" proto="$2" target="$3"
    ensure_conf_dir
    # 先删除旧的（如果有）
    remove_rule_from_file "$port" "$proto" 2>/dev/null || true
    echo "$port $proto $target" | sudo tee -a "$RULES_FILE" >/dev/null
}

# 从文件删除规则
remove_rule_from_file() {
    local port="$1" proto="$2"
    if [[ -f "$RULES_FILE" ]]; then
        sudo sed -i.bak "/^${port}\s\+${proto}\s\+/d" "$RULES_FILE"
        sudo rm -f "$RULES_FILE.bak"
    fi
}

# ---------------- iptables 规则操作 ----------------

# 添加 DNAT 规则
add_dnat_rule() {
    local port="$1" proto="$2" target="$3"

    # 解析目标 IP 和端口
    local target_ip target_port
    if [[ "$target" == *:* ]]; then
        target_ip="${target%%:*}"
        target_port="${target##*:}"
    else
        error "$(_t 'Invalid target format, it should be IP:port, for example 192.168.1.100:443')"
        exit 1
    fi

    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        error "$(_tf 'Invalid external port: %s (expected 1-65535)' "${port}")"
        exit 1
    fi
    if ! [[ "$target_port" =~ ^[0-9]+$ ]] || ((target_port < 1 || target_port > 65535)); then
        error "$(_tf 'Invalid target port: %s (expected 1-65535)' "${target_port}")"
        exit 1
    fi

    # 检查是否已存在
    if rule_exists "$port" "$proto"; then
        warn "$(_tf 'The port %s/%s already has a forwarding rule, it will be overwritten' "$port" "$proto")"
        remove_dnat_rule "$port" "$proto"
    fi

    local comment="${COMMENT_PREFIX}:${port}"

    # DNAT：外部请求 → 目标
    sudo iptables -t nat -A PREROUTING -p "$proto" --dport "$port" \
        -j DNAT --to-destination "$target" \
        -m comment --comment "$comment"

    # FORWARD：放行已建立的连接 + 新连接
    sudo iptables -A FORWARD -p "$proto" -d "$target_ip" --dport "$target_port" \
        -m comment --comment "$comment" -j ACCEPT

    # 保存到配置文件
    add_rule_to_file "$port" "$proto" "$target"

    success "$(_tf 'Forwarding added: %s/%s -> %s' "$port" "$proto" "$target")"
}

# 删除 DNAT 规则
remove_dnat_rule() {
    local port="$1" proto="$2"
    local comment="${COMMENT_PREFIX}:${port}"

    # 从 iptables 删除（循环删直到没有）
    while sudo iptables -t nat -D PREROUTING -p "$proto" --dport "$port" \
        -m comment --comment "$comment" -j DNAT 2>/dev/null; do :; done
    while sudo iptables -D FORWARD -m comment --comment "$comment" 2>/dev/null; do :; done

    # 从配置文件删除
    remove_rule_from_file "$port" "$proto"

    success "$(_tf 'Forwarding removed: %s/%s' "$port" "$proto")"
}

# 列出所有 DNAT 规则
list_dnat_rules() {
    info "=== DNAT $(_t 'Forwarding rules ===')"
    if [[ ! -f "$RULES_FILE" ]] || [[ ! -s "$RULES_FILE" ]]; then
        echo "  $(_t '(no rules)')"
        return
    fi
    printf "  %-8s %-6s %s\n" "$(_t 'Port')" "$(_t 'Protocol')" "$(_t 'Target')"
    printf "  %-8s %-6s %s\n" "--------" "------" "--------------------"
    while IFS=' ' read -r port proto target; do
        [[ -z "$port" || "$port" == \#* ]] && continue
        printf "  %-8s %-6s %s\n" "$port" "$proto" "$target"
    done < "$RULES_FILE"
}

# ---------------- MASQUERADE 网关 ----------------

# 开启 MASQUERADE
enable_gateway() {
    local iface="$1" source="$2"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        error "$(_tf 'The interface %s does not exist. Available network interfaces:' "$iface")"
        ip -br link show | awk '{print "  " $1}' >&2
        exit 1
    fi

    local comment="${COMMENT_PREFIX}:gw:${iface}"
    local rule_line="$iface"

    # 构建 iptables 参数
    local src_args=()
    if [[ -n "$source" ]]; then
        src_args=(-s "$source")
        rule_line="$iface $source"
    fi

    # 检查是否已存在
    if [[ -f "$GATEWAY_FILE" ]] && grep -q "^${iface}" "$GATEWAY_FILE"; then
        warn "$(_tf 'The interface %s already has a MASQUERADE rule, it will be overwritten' "$iface")"
        disable_gateway "$iface"
    fi

    # 添加 MASQUERADE 规则
    sudo iptables -t nat -A POSTROUTING "${src_args[@]}" -o "$iface" \
        -j MASQUERADE -m comment --comment "$comment"

    # FORWARD 放行
    sudo iptables -A FORWARD -i "$iface" -m comment --comment "$comment" -j ACCEPT
    sudo iptables -A FORWARD -o "$iface" -m comment --comment "$comment" -j ACCEPT

    # 保存配置
    ensure_conf_dir
    echo "$rule_line" | sudo tee -a "$GATEWAY_FILE" >/dev/null

    success "$(_tf 'MASQUERADE enabled: interface %s%s' "$iface" "${source:+ ($(_t 'source') $source)}")"
}

# 关闭 MASQUERADE
disable_gateway() {
    local iface="$1"
    local comment="${COMMENT_PREFIX}:gw:${iface}"

    # 删除 iptables 规则
    while sudo iptables -t nat -D POSTROUTING -o "$iface" \
        -j MASQUERADE -m comment --comment "$comment" 2>/dev/null; do :; done
    while sudo iptables -D FORWARD -m comment --comment "$comment" 2>/dev/null; do :; done

    # 从配置文件删除
    if [[ -f "$GATEWAY_FILE" ]]; then
        sudo sed -i.bak "/^${iface}/d" "$GATEWAY_FILE"
        sudo rm -f "$GATEWAY_FILE.bak"
    fi

    success "$(_tf 'MASQUERADE disabled: interface %s' "$iface")"
}

# 列出网关配置
list_gateways() {
    info "=== MASQUERADE $(_t 'Gateway ===')"
    if [[ ! -f "$GATEWAY_FILE" ]] || [[ ! -s "$GATEWAY_FILE" ]]; then
        echo "  $(_t '(not configured)')"
        return
    fi
    printf "  %-12s %s\n" "$(_t 'Interface')" "$(_t 'Source CIDR')"
    printf "  %-12s %s\n" "------------" "--------------------"
    while IFS=' ' read -r iface source; do
        [[ -z "$iface" || "$iface" == \#* ]] && continue
        printf "  %-12s %s\n" "$iface" "${source:-$(_t 'all')}"
    done < "$GATEWAY_FILE"
}

# ---------------- 加载规则（systemd 调用） ----------------

# 从配置文件重建所有 iptables 规则（启动时调用）
load_all_rules() {
    # 加载 DNAT 转发规则
    if [[ -f "$RULES_FILE" ]]; then
        while IFS=' ' read -r port proto target; do
            [[ -z "$port" || "$port" == \#* ]] && continue
            local comment="${COMMENT_PREFIX}:${port}"

            local target_ip target_port
            target_ip="${target%%:*}"
            target_port="${target##*:}"

            # DNAT
            iptables -t nat -A PREROUTING -p "$proto" --dport "$port" \
                -j DNAT --to-destination "$target" \
                -m comment --comment "$comment" 2>/dev/null || true

            # FORWARD
            iptables -A FORWARD -p "$proto" -d "$target_ip" --dport "$target_port" \
                -m comment --comment "$comment" -j ACCEPT 2>/dev/null || true
        done < "$RULES_FILE"
    fi

    # 加载 MASQUERADE 规则
    if [[ -f "$GATEWAY_FILE" ]]; then
        while IFS=' ' read -r iface source; do
            [[ -z "$iface" || "$iface" == \#* ]] && continue
            local comment="${COMMENT_PREFIX}:gw:${iface}"
            local src_args=()
            [[ -n "$source" ]] && src_args=(-s "$source")

            iptables -t nat -A POSTROUTING "${src_args[@]}" -o "$iface" \
                -j MASQUERADE -m comment --comment "$comment" 2>/dev/null || true
            iptables -A FORWARD -i "$iface" -m comment --comment "$comment" -j ACCEPT 2>/dev/null || true
            iptables -A FORWARD -o "$iface" -m comment --comment "$comment" -j ACCEPT 2>/dev/null || true
        done < "$GATEWAY_FILE"
    fi
}

# 清除所有 nat-manager 规则（不清配置文件）
flush_all_rules() {
    info "$(_t 'Clearing all the nat-manager iptables rules...')"

    # 清除 DNAT 规则
    if [[ -f "$RULES_FILE" ]]; then
        while IFS=' ' read -r port proto target; do
            [[ -z "$port" || "$port" == \#* ]] && continue
            local comment="${COMMENT_PREFIX}:${port}"
            while sudo iptables -t nat -D PREROUTING -p "$proto" --dport "$port" \
                -m comment --comment "$comment" -j DNAT 2>/dev/null; do :; done
            while sudo iptables -D FORWARD -m comment --comment "$comment" 2>/dev/null; do :; done
        done < "$RULES_FILE"
    fi

    # 清除 MASQUERADE 规则
    if [[ -f "$GATEWAY_FILE" ]]; then
        while IFS=' ' read -r iface source; do
            [[ -z "$iface" || "$iface" == \#* ]] && continue
            local comment="${COMMENT_PREFIX}:gw:${iface}"
            while sudo iptables -t nat -D POSTROUTING -o "$iface" \
                -j MASQUERADE -m comment --comment "$comment" 2>/dev/null; do :; done
            while sudo iptables -D FORWARD -m comment --comment "$comment" 2>/dev/null; do :; done
        done < "$GATEWAY_FILE"
    fi
}

# ---------------- systemd 持久化 ----------------

install_systemd_service() {
    info "$(_t 'Configuring the systemd persistence service...')"

    install_systemd_unit nat-manager.service <<EOF
[Unit]
Description=NAT Manager - $(_t 'Load the port forwarding and MASQUERADE rules')
After=network-pre.target
Before=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPT_DIR/install.sh _load
ExecStop=$SCRIPT_DIR/install.sh _flush

[Install]
WantedBy=multi-user.target
EOF

    uxs_svc enable nat-manager.service
    success "nat-manager.service $(_t 'Enabled (the rules are loaded automatically at boot)')"
}

remove_systemd_service() {
    info "$(_t 'Removing the systemd persistence service...')"
    uxs_svc disable nat-manager.service 2>/dev/null || true
    uxs_svc stop nat-manager.service 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"
    uxs_svc daemon-reload
    success "nat-manager.service $(_t 'Removed')"
}

# ---------------- 安装 / 卸载 ----------------

do_install() {
    preflight
    ensure_iptables
    enable_ip_forwarding
    ensure_conf_dir
    install_systemd_service

    echo
    success "NAT $(_t 'NAT management tool installation complete!')"
    echo
    info "$(_t 'Quick start:')"
    echo "  $0 forward add 8443 192.168.1.100:443     # $(_t 'Port forwarding')"
    echo "  $0 gateway enable eth1 --source 192.168.1.0/24  # $(_t 'Shared internet access')"
    echo "  $0 forward list                            # $(_t 'Show the rules')"
    echo "  $0 status                                  # $(_t 'Overview')"
}

do_uninstall() {
    preflight

    if ! yes_no "$(_t 'Confirm uninstalling the NAT management tool? All forwarding rules and gateway settings will be cleared.')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    # 清除 iptables 规则
    flush_all_rules

    # 移除 systemd 服务
    remove_systemd_service

    # 关闭 IP forwarding
    disable_ip_forwarding

    # 删除配置文件
    if [[ -d "$CONF_DIR" ]]; then
        if yes_no "$(_tf 'Delete the configuration directory %s? (the rule files will be deleted too)' "${CONF_DIR}")"; then
            sudo rm -rf "$CONF_DIR"
            success "$(_tf 'Configuration directory %s deleted' "$CONF_DIR")"
        else
            info "$(_tf 'Configuration directory kept: %s' "$CONF_DIR")"
        fi
    fi

    success "NAT $(_t 'NAT management tool uninstalled')"
}

# ---------------- 状态 ----------------

do_status() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}$(_t 'Not applicable (Linux only)')${NC}"
        return
    fi

    # ---- 先收集事实，用于聚合并计算主状态 ----
    local fwd
    fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
    local rule_count=0 gw_count=0
    if [[ -f "$RULES_FILE" ]]; then
        rule_count=$(grep -cvE '^\s*$|^\s*#' "$RULES_FILE" 2>/dev/null || echo 0)
    fi
    if [[ -f "$GATEWAY_FILE" ]]; then
        gw_count=$(grep -cvE '^\s*$|^\s*#' "$GATEWAY_FILE" 2>/dev/null || echo 0)
    fi
    local svc_state
    svc_state="$(_t 'Not enabled')"
    local svc_key="disabled"
    if uxs_svc is-enabled nat-manager.service >/dev/null 2>&1; then
        if uxs_svc is-active nat-manager.service >/dev/null 2>&1; then
            svc_state="$(_t 'Enabled and running')"
            svc_key="running"
        else
            svc_state="$(_t 'Enabled but not running')"
            svc_key="stopped"
        fi
    fi

    # ---- 聚合主状态：转发规则数>0 → configured；否则 not_configured ----
    if [[ ${rule_count:-0} -gt 0 ]]; then
        emit_status "configured" "${GREEN}$(_t '✅ NAT configured')${NC}$(_tf '(%s forwarding rules)' "$rule_count")"
    else
        emit_status "not_configured" "${YELLOW}$(_t '⚠️  NAT not configured')${NC}$(_t '(no forwarding rules)')"
    fi
    emit_extra "ip_forward=$fwd"
    emit_extra "rules=$rule_count"
    emit_extra "gateways=$gw_count"
    emit_extra "service=$svc_state"

    # ---- 人类模式：保留原始多行概览 + 详细规则表 ----
    if ! uxs_is_machine_mode; then
        # IP forwarding 状态
        if [[ "$fwd" == "1" ]]; then
            echo -e "IP forwarding: ${GREEN}$(_t 'Enabled')${NC}"
        else
            echo -e "IP forwarding: ${RED}$(_t 'Off')${NC}"
        fi

        # 规则文件状态
        echo -e "$(_tf 'Forwarding rules: %s' "${rule_count}")"
        echo -e "$(_tf 'Gateway settings: %s' "${gw_count}")"

        # systemd 服务状态
        case "$svc_key" in
            running) echo -e "$(_t 'Persistence service:') ${GREEN}$(_t 'Enabled and running')${NC}" ;;
            stopped) echo -e "$(_t 'Persistence service:') ${YELLOW}$(_t 'Enabled but not running')${NC}" ;;
            *) echo -e "$(_t 'Persistence service:') ${RED}$(_t 'Not enabled')${NC}" ;;
        esac

        # 详细规则
        echo
        list_dnat_rules
        echo
        list_gateways
    fi
}

# ---------------- 帮助 ----------------

usage() {
    cat <<EOF
用法: $0 <子命令> [参数...]

NAT $(_t 'NAT port forwarding and shared internet access management tool (Linux only).')

$(_t 'Subcommands:')
  install                                     $(_t 'Install the dependencies, enable IP forwarding and set up persistence')
  uninstall                                   $(_t 'Clear the rules, disable IP forwarding and remove the persistence')
  forward add <$(_t 'port> <target:port> [--proto P]   Add a DNAT forwarding rule (tcp by default)')
  forward del <$(_t 'port> [--proto P]               Delete a DNAT forwarding rule')
  forward list                                $(_t 'List all the forwarding rules')
  gateway enable <$(_t 'interface> [--source CIDR]        Enable MASQUERADE (shared internet access)')
  gateway disable <$(_t 'interface>                       Disable MASQUERADE')
  status                                      $(_t 'Overview')
  help                                        $(_t 'Show this help')

$(_t 'Internal commands (called by systemd, not used directly):')
  _load                                       $(_t 'Load all the rules from the configuration files')
  _flush                                      $(_t 'Clear all the iptables rules')

$(_t 'Examples:')
  $0 install
  $0 forward add 8443 192.168.1.100:443
  $0 forward add 5353 192.168.1.1:53 --proto udp
  $0 forward del 8443
  $0 gateway enable eth1 --source 192.168.1.0/24
  $0 gateway disable eth1
  $0 status
EOF
}

# ---------------- 主入口 ----------------

parse_forward_args() {
    local action="$1"; shift
    local port="" proto="tcp" target=""

    case "$action" in
        add)
            port="${1:-}"; target="${2:-}"; shift 2 2>/dev/null || true
            ;;
        del|delete|remove|rm)
            port="${1:-}"; shift 1 2>/dev/null || true
            ;;
        list|ls)
            list_dnat_rules
            return
            ;;
        *)
            error "$(_tf 'Unknown forward subcommand: %s' "$action")"
            echo "  $(_t 'Available: add, del, list')"
            exit 1
            ;;
    esac

    # 解析可选参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --proto|-p)
                proto="$2"; shift 2
                ;;
            *)
                error "$(_tf 'Unknown parameter: %s' "$1")"
                exit 1
                ;;
        esac
    done

    # 验证必填参数
    if [[ "$action" == "add" ]]; then
        if [[ -z "$port" || -z "$target" ]]; then
            error "$(_tf 'Usage: %s forward add <port> <targetIP:port> [--proto tcp|udp]' "$0")"
            exit 1
        fi
        preflight
        ensure_iptables
        add_dnat_rule "$port" "$proto" "$target"
    elif [[ "$action" == "del" || "$action" == "delete" || "$action" == "remove" || "$action" == "rm" ]]; then
        if [[ -z "$port" ]]; then
            error "$(_tf 'Usage: %s forward del <port> [--proto tcp|udp]' "$0")"
            exit 1
        fi
        preflight
        ensure_iptables
        if ! rule_exists "$port" "$proto"; then
            warn "$(_tf 'No forwarding rule found for the port %s/%s' "$port" "$proto")"
            return 0
        fi
        remove_dnat_rule "$port" "$proto"
    fi
}

parse_gateway_args() {
    local action="$1"; shift

    case "$action" in
        enable|on)
            local iface="${1:-}" source=""
            shift 1 2>/dev/null || true
            if [[ -z "$iface" ]]; then
                error "$(_tf 'Usage: %s gateway enable <interface> [--source CIDR]' "$0")"
                exit 1
            fi
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --source|-s) source="$2"; shift 2 ;;
                    *) error "$(_tf 'Unknown parameter: %s' "$1")"; exit 1 ;;
                esac
            done
            preflight
            ensure_iptables
            enable_ip_forwarding
            enable_gateway "$iface" "$source"
            ;;
        disable|off)
            local iface="${1:-}"
            if [[ -z "$iface" ]]; then
                error "$(_tf 'Usage: %s gateway disable <interface>' "$0")"
                exit 1
            fi
            preflight
            ensure_iptables
            disable_gateway "$iface"
            ;;
        list|ls)
            list_gateways
            ;;
        *)
            error "$(_tf 'Unknown gateway subcommand: %s' "$action")"
            echo "  $(_t 'Available: enable, disable, list')"
            exit 1
            ;;
    esac
}

main() {
    local action="${1:-help}"
    detect_os

    case "$action" in
        install)
            do_install
            ;;
        uninstall)
            do_uninstall
            ;;
        forward)
            shift
            parse_forward_args "$@"
            ;;
        gateway)
            shift
            parse_gateway_args "$@"
            ;;
        status)
            do_status
            ;;
        _load)
            # 内部命令：systemd 启动时加载规则
            load_all_rules
            ;;
        _flush)
            # 内部命令：systemd 停止时清除规则
            flush_all_rules
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "$(_tf 'Unknown action: %s' "$action")"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
