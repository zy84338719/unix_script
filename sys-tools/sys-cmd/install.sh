#!/usr/bin/env bash
#
# sys-cmd/install.sh
#
# 系统诊断命令集 —— 常用运维命令的快捷封装，一眼看清系统状态。
# Linux + macOS。不安装任何东西，纯函数封装。
#
# 子命令:
#   cpu       CPU 占用 TOP10 进程
#   mem       内存占用 TOP10 进程
#   port      占用指定端口的进程（需参数：端口号）
#   ports     所有监听端口一览
#   disk      磁盘空间使用情况（df）
#   du        当前目录磁盘占用 TOP10（du）
#   net       网络连接状态统计
#   top       系统实时概览（top 快照）
#   logs      关键系统日志入口提示
#   all       依次展示 cpu/mem/disk/net/ports
#   status    查看本工具状态
#   help      帮助
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# ---- CPU 占用 TOP10 ----
cmd_cpu() {
    header "$(_t '🔥 CPU usage TOP10')"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        ps -Arceo pid,%cpu,%mem,comm | head -11 || true
    else
        ps -eo pid,ppid,%cpu,%mem,comm --sort=-%cpu | head -11 || true
    fi
}

# ---- 内存占用 TOP10 ----
cmd_mem() {
    header "$(_t '💾 Memory usage TOP10')"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        ps -Amceo pid,%mem,rss,comm | head -11 || true
    else
        ps -eo pid,ppid,%mem,rss,comm --sort=-%mem | head -11 || true
    fi
}

# ---- 占用端口的进程 ----
cmd_port() {
    local port="$1"
    if [[ -z "$port" ]]; then
        error "$(_tf 'Usage: %s port <port>, for example: %s port 8080' "$0" "$0")"
        return 1
    fi
    header "$(_tf '🔌 Processes using port %s' "$port")"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo lsof -i ":$port" -P -n 2>/dev/null || lsof -i ":$port" -P -n 2>/dev/null || warn "$(_tf 'No process is using port %s, or sudo is required' "$port")"
    else
        # 先试 ss（现代），再试 netstat（老系统）
        if command_exists ss; then
            ss -tlnp "sport = :$port" 2>/dev/null || ss -tlnp | grep ":$port"
        elif command_exists netstat; then
            netstat -tlnp 2>/dev/null | grep ":$port"
        else
            warn "$(_t 'No ss/netstat command found')"
        fi
    fi
}

# ---- 所有监听端口 ----
cmd_ports() {
    header "$(_t '🌐 All listening ports')"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | head -30 || true
    else
        if command_exists ss; then
            ss -tlnp 2>/dev/null | head -30 || true
        elif command_exists netstat; then
            netstat -tlnp 2>/dev/null | head -30 || true
        else
            warn "$(_t 'No ss/netstat command found')"
        fi
    fi
}

# ---- 磁盘空间 ----
cmd_disk() {
    header "$(_t '💽 Disk space (df -h)')"
    echo "-----------------------------------------------"
    df -h 2>/dev/null || df
}

# ---- 目录磁盘占用 TOP10 ----
cmd_du() {
    header "$(_t '📦 Directory usage TOP10 (current directory)')"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS du 不支持 --max-depth，用 -d 1
        du -sh -d 1 . 2>/dev/null | sort -rh | head -11 || true
    else
        du -sh --max-depth=1 . 2>/dev/null | sort -rh | head -11 || true
    fi
}

# ---- 网络连接统计 ----
cmd_net() {
    header "$(_t '🌍 Network connection statistics')"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local total estab listen
        total=$(netstat -an 2>/dev/null | grep -c tcp || echo 0)
        estab=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
        listen=$(netstat -an 2>/dev/null | grep -c LISTEN || echo 0)
        printf '%s\n' "TCP $(_tf 'Total connections: %s' "$total")"
        echo "ESTABLISHED: $estab"
        echo "LISTEN: $listen"
        echo
        printf '%s\n' "$(_t 'Active connections TOP10:')"
        netstat -an 2>/dev/null | grep ESTABLISHED | head -10 || true
    else
        if command_exists ss; then
            printf '%s\n' "TCP $(_t 'Connection state statistics:')"
            ss -s 2>/dev/null
            echo
            echo "ESTABLISHED TOP10:"
            ss -tunap state established 2>/dev/null | head -11 || true
        elif command_exists netstat; then
            printf '%s\n' "TCP $(_t 'Connection state statistics:')"
            netstat -ant 2>/dev/null | awk '{print $6}' | sort | uniq -c | sort -rn
            echo
            echo "ESTABLISHED TOP10:"
            netstat -antp 2>/dev/null | grep ESTABLISHED | head -10 || true
        fi
    fi
}

# ---- 系统概览快照 ----
cmd_top() {
    header "$(_t '📊 System overview snapshot')"
    echo "-----------------------------------------------"
    # uptime + 负载
    uptime 2>/dev/null
    echo
    # 内存
    local ncpu
    if [[ "$OS_TYPE" == "darwin" ]]; then
        vm_stat 2>/dev/null | head -5 || true
        echo
        ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo '?')
        printf '%s\n' "$(_tf 'CPU cores: %s' "$ncpu")"
    else
        free -h 2>/dev/null || free
        echo
        ncpu=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo) || true
        printf '%s\n' "$(_tf 'CPU cores: %s' "$ncpu")"
    fi
}

# ---- 日志入口提示 ----
cmd_logs() {
    header "$(_t '📋 System log entry points')"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "linux" ]]; then
        printf '%s\n' "$(_t 'View systemd service logs:')"
        printf '%s\n' "  sudo journalctl -u <$(_t 'service name')> -f       # $(_t 'real-time follow')"
        printf '%s\n' "  sudo journalctl -u <$(_t 'service name')> --since today"
        printf '%s\n' "  sudo journalctl -p err -b            # $(_t 'errors since this boot')"
        echo
        printf '%s\n' "$(_t 'Common service log files:')"
        printf '%s\n' "  /var/log/syslog $(_t 'or') /var/log/messages  # $(_t 'system log')"
        printf '%s\n' "  /var/log/auth.log $(_t 'or') /var/log/secure  # $(_t 'auth log')"
        echo "  /var/log/nginx/                        # Nginx"
        echo "  /var/log/fail2ban.log                  # Fail2ban"
    else
        printf '%s\n' "$(_t 'macOS logs:')"
        printf '%s\n' "  log show --predicate 'processImagePath contains \"<$(_t 'keyword')>\"' --last 1h"
        printf '%s\n' "  log stream                             # $(_t 'real-time stream')"
        printf '%s\n' "  Console.app                            # $(_t 'graphical interface')"
        echo
        printf '%s\n' "$(_t 'Common log files:')"
        echo "  /var/log/system.log"
        echo "  /var/log/install.log"
    fi
}

# ---- 全部展示 ----
cmd_all() {
    cmd_top
    echo
    cmd_cpu
    echo
    cmd_mem
    echo
    cmd_disk
    echo
    cmd_net
    echo
    cmd_ports
}

status_sys_cmd() {
    detect_os
    emit_status "installed" "${GREEN}$(_t '✅ Available')${NC}$(_t '(pure command wrapper, nothing to install)')"
    emit_extra "type=builtin"
}

# ---- 交互式菜单 ----
interactive_menu() {
    while true; do
        clear
        header "$(_t '🔍 System diagnostic commands')"
        echo "========================================"
        printf '%s\n' "  1) $(_t 'System overview        - load/memory/CPU cores')"
        printf '%s\n' "  2) $(_t 'CPU usage TOP10')"
        printf '%s\n' "  3) $(_t 'Memory usage TOP10')"
        printf '%s\n' "  4) $(_t 'Disk space        - df -h')"
        printf '%s\n' "  5) $(_t 'Directory usage TOP10  - du (current directory)')"
        printf '%s\n' "  6) $(_t 'Network connection statistics')"
        printf '%s\n' "  7) $(_t 'Listening ports at a glance')"
        printf '%s\n' "  8) $(_t 'Check port usage      - port number required')"
        printf '%s\n' "  9) $(_t 'System log entry point tips')"
        printf '%s\n' "  a) $(_t 'Show everything')"
        printf '%s\n' "  0) $(_t 'Back to the main menu')"
        echo "========================================"
        read -r -p "$(_t 'Select [0-9/a]:') " choice
        echo
        case "$choice" in
            1) cmd_top ;;
            2) cmd_cpu ;;
            3) cmd_mem ;;
            4) cmd_disk ;;
            5) cmd_du ;;
            6) cmd_net ;;
            7) cmd_ports ;;
            8) read -r -p "$(_t 'Enter the port number:') " p; cmd_port "$p" ;;
            9) cmd_logs ;;
            a|A) cmd_all ;;
            0) break ;;
            *) error "$(_t 'Invalid option')"; sleep 1; continue ;;
        esac
        echo
        read -r -p "$(_t 'Press Enter to continue...')"
    done
}

usage() {
    cat <<EOF
用法: $0 {cpu|mem|port|ports|disk|du|net|top|logs|all|menu|status|help}

$(_t 'System diagnostic command set (Linux + macOS):')
  menu        $(_t 'Interactive menu (default action)')
  cpu         $(_t 'CPU usage TOP10 processes')
  mem         $(_t 'Memory usage TOP10 processes')
  port <$(_t 'port> processes using the given port (e.g. port 8080)')
  ports       $(_t 'Overview of all listening ports')
  disk        $(_t 'Disk space (df -h)')
  du          $(_t 'TOP10 usage of the current directory')
  net         $(_t 'Network connection state statistics')
  top         $(_t 'System overview snapshot (load/memory/CPU cores)')
  logs        $(_t 'System log entry point tips')
  all         $(_t 'Show top/cpu/mem/disk/net/ports in sequence')
EOF
}

main() {
    local action="${1:-menu}"
    detect_os
    case "$action" in
        cpu)    cmd_cpu ;;
        mem)    cmd_mem ;;
        port)   shift; cmd_port "$1" ;;
        ports)  cmd_ports ;;
        disk)   cmd_disk ;;
        du)     cmd_du ;;
        net)    cmd_net ;;
        top)    cmd_top ;;
        logs)   cmd_logs ;;
        all)    cmd_all ;;
        menu)   interactive_menu ;;
        status) status_sys_cmd ;;
        # 契约 no-op
        uninstall) info "$(_t 'sys-cmd is a read-only command wrapper, installs no components, nothing to uninstall')" ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
