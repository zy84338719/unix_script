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

set -e

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
        error "nat 模块仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    require_sudo
}

# 确保 iptables 可用
ensure_iptables() {
    if ! command_exists iptables; then
        error "未找到 iptables 命令，请先安装："
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
    info "开启 IP forwarding..."
    # 立即生效
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    # 持久化
    echo "net.ipv4.ip_forward = 1" | sudo tee "$SYSCTL_FILE" >/dev/null
    success "IP forwarding 已开启"
}

disable_ip_forwarding() {
    info "关闭 IP forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
    sudo rm -f "$SYSCTL_FILE"
    success "IP forwarding 已关闭"
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
        error "目标格式错误，应为 IP:端口，如 192.168.1.100:443"
        exit 1
    fi

    # 验证端口号
    if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        error "外部端口无效：$port（应为 1-65535）"
        exit 1
    fi
    if ! [[ "$target_port" =~ ^[0-9]+$ ]] || ((target_port < 1 || target_port > 65535)); then
        error "目标端口无效：$target_port（应为 1-65535）"
        exit 1
    fi

    # 检查是否已存在
    if rule_exists "$port" "$proto"; then
        warn "端口 $port/$proto 已有转发规则，将覆盖"
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

    success "已添加转发：$port/$proto → $target"
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

    success "已删除转发：$port/$proto"
}

# 列出所有 DNAT 规则
list_dnat_rules() {
    info "=== DNAT 转发规则 ==="
    if [[ ! -f "$RULES_FILE" ]] || [[ ! -s "$RULES_FILE" ]]; then
        echo "  （无规则）"
        return
    fi
    printf "  %-8s %-6s %s\n" "端口" "协议" "目标"
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
        error "网卡 $iface 不存在。可用网卡："
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
        warn "网卡 $iface 已配置 MASQUERADE，将覆盖"
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

    success "已开启 MASQUERADE：网卡 $iface${source:+ (源 $source)}"
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

    success "已关闭 MASQUERADE：网卡 $iface"
}

# 列出网关配置
list_gateways() {
    info "=== MASQUERADE 网关 ==="
    if [[ ! -f "$GATEWAY_FILE" ]] || [[ ! -s "$GATEWAY_FILE" ]]; then
        echo "  （未配置）"
        return
    fi
    printf "  %-12s %s\n" "网卡" "源 CIDR"
    printf "  %-12s %s\n" "------------" "--------------------"
    while IFS=' ' read -r iface source; do
        [[ -z "$iface" || "$iface" == \#* ]] && continue
        printf "  %-12s %s\n" "$iface" "${source:-（全部）}"
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
    info "清除所有 nat-manager iptables 规则..."

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
    info "配置 systemd 持久化服务..."

    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=NAT Manager - 加载端口转发与 MASQUERADE 规则
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

    sudo systemctl daemon-reload
    sudo systemctl enable nat-manager.service
    success "nat-manager.service 已启用（开机自动加载规则）"
}

remove_systemd_service() {
    info "移除 systemd 持久化服务..."
    sudo systemctl disable nat-manager.service 2>/dev/null || true
    sudo systemctl stop nat-manager.service 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload
    success "nat-manager.service 已移除"
}

# ---------------- 安装 / 卸载 ----------------

do_install() {
    preflight
    ensure_iptables
    enable_ip_forwarding
    ensure_conf_dir
    install_systemd_service

    echo
    success "NAT 管理工具安装完成！"
    echo
    info "快速开始："
    echo "  $0 forward add 8443 192.168.1.100:443     # 端口转发"
    echo "  $0 gateway enable eth1 --source 192.168.1.0/24  # 共享上网"
    echo "  $0 forward list                            # 查看规则"
    echo "  $0 status                                  # 总览"
}

do_uninstall() {
    preflight

    if ! yes_no "确认卸载 NAT 管理工具？所有转发规则和网关配置将被清除。"; then
        info "已取消"
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
        if yes_no "是否删除配置目录 $CONF_DIR？（规则文件也会被删除）"; then
            sudo rm -rf "$CONF_DIR"
            success "配置目录 $CONF_DIR 已删除"
        else
            info "配置目录已保留：$CONF_DIR"
        fi
    fi

    success "NAT 管理工具已卸载"
}

# ---------------- 状态 ----------------

do_status() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}不适用（仅 Linux）${NC}"
        return
    fi

    # IP forwarding 状态
    local fwd
    fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
    if [[ "$fwd" == "1" ]]; then
        echo -e "IP forwarding: ${GREEN}已开启${NC}"
    else
        echo -e "IP forwarding: ${RED}未开启${NC}"
    fi

    # 规则文件状态
    local rule_count=0 gw_count=0
    if [[ -f "$RULES_FILE" ]]; then
        rule_count=$(grep -cvE '^\s*$|^\s*#' "$RULES_FILE" 2>/dev/null || echo 0)
    fi
    if [[ -f "$GATEWAY_FILE" ]]; then
        gw_count=$(grep -cvE '^\s*$|^\s*#' "$GATEWAY_FILE" 2>/dev/null || echo 0)
    fi
    echo -e "转发规则: ${rule_count} 条"
    echo -e "网关配置: ${gw_count} 个"

    # systemd 服务状态
    if systemctl is-enabled nat-manager.service >/dev/null 2>&1; then
        if systemctl is-active nat-manager.service >/dev/null 2>&1; then
            echo -e "持久化服务: ${GREEN}已启用并运行${NC}"
        else
            echo -e "持久化服务: ${YELLOW}已启用但未运行${NC}"
        fi
    else
        echo -e "持久化服务: ${RED}未启用${NC}"
    fi

    # 详细规则
    echo
    list_dnat_rules
    echo
    list_gateways
}

# ---------------- 帮助 ----------------

usage() {
    cat <<EOF
用法: $0 <子命令> [参数...]

NAT 端口转发与共享上网管理工具（仅 Linux）。

子命令:
  install                                     安装依赖、开启 IP forwarding、配置持久化
  uninstall                                   清除规则、关闭 IP forwarding、移除持久化
  forward add <端口> <目标:端口> [--proto P]   添加 DNAT 转发（默认 tcp）
  forward del <端口> [--proto P]               删除 DNAT 转发
  forward list                                列出所有转发规则
  gateway enable <网卡> [--source CIDR]        开启 MASQUERADE（共享上网）
  gateway disable <网卡>                       关闭 MASQUERADE
  status                                      总览
  help                                        显示本帮助

内部命令（systemd 调用，不直接使用）:
  _load                                       从配置文件加载所有规则
  _flush                                      清除所有 iptables 规则

示例:
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
            error "未知 forward 子命令: $action"
            echo "  可用: add, del, list"
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
                error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    # 验证必填参数
    if [[ "$action" == "add" ]]; then
        if [[ -z "$port" || -z "$target" ]]; then
            error "用法: $0 forward add <端口> <目标IP:端口> [--proto tcp|udp]"
            exit 1
        fi
        preflight
        ensure_iptables
        add_dnat_rule "$port" "$proto" "$target"
    elif [[ "$action" == "del" || "$action" == "delete" || "$action" == "remove" || "$action" == "rm" ]]; then
        if [[ -z "$port" ]]; then
            error "用法: $0 forward del <端口> [--proto tcp|udp]"
            exit 1
        fi
        preflight
        ensure_iptables
        if ! rule_exists "$port" "$proto"; then
            warn "未找到端口 $port/$proto 的转发规则"
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
                error "用法: $0 gateway enable <网卡> [--source CIDR]"
                exit 1
            fi
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --source|-s) source="$2"; shift 2 ;;
                    *) error "未知参数: $1"; exit 1 ;;
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
                error "用法: $0 gateway disable <网卡>"
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
            error "未知 gateway 子命令: $action"
            echo "  可用: enable, disable, list"
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
            error "未知操作: $action"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
