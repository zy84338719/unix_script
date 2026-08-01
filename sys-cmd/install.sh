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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# ---- CPU 占用 TOP10 ----
cmd_cpu() {
    header "🔥 CPU 占用 TOP10"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        ps -Arceo pid,%cpu,%mem,comm | head -11
    else
        ps -eo pid,ppid,%cpu,%mem,comm --sort=-%cpu | head -11
    fi
}

# ---- 内存占用 TOP10 ----
cmd_mem() {
    header "💾 内存占用 TOP10"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        ps -Amceo pid,%mem,rss,comm | head -11
    else
        ps -eo pid,ppid,%mem,rss,comm --sort=-%mem | head -11
    fi
}

# ---- 占用端口的进程 ----
cmd_port() {
    local port="$1"
    if [[ -z "$port" ]]; then
        error "用法: $0 port <端口号>，例如: $0 port 8080"
        return 1
    fi
    header "🔌 占用端口 $port 的进程"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo lsof -i ":$port" -P -n 2>/dev/null || lsof -i ":$port" -P -n 2>/dev/null || warn "无进程占用端口 $port 或需要 sudo"
    else
        # 先试 ss（现代），再试 netstat（老系统）
        if command_exists ss; then
            ss -tlnp "sport = :$port" 2>/dev/null || ss -tlnp | grep ":$port"
        elif command_exists netstat; then
            netstat -tlnp 2>/dev/null | grep ":$port"
        else
            warn "无 ss/netstat 命令"
        fi
    fi
}

# ---- 所有监听端口 ----
cmd_ports() {
    header "🌐 所有监听端口"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | head -30
    else
        if command_exists ss; then
            ss -tlnp 2>/dev/null | head -30
        elif command_exists netstat; then
            netstat -tlnp 2>/dev/null | head -30
        else
            warn "无 ss/netstat 命令"
        fi
    fi
}

# ---- 磁盘空间 ----
cmd_disk() {
    header "💽 磁盘空间（df -h）"
    echo "-----------------------------------------------"
    df -h 2>/dev/null || df
}

# ---- 目录磁盘占用 TOP10 ----
cmd_du() {
    header "📦 目录占用 TOP10（当前目录）"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS du 不支持 --max-depth，用 -d 1
        du -sh -d 1 . 2>/dev/null | sort -rh | head -11
    else
        du -sh --max-depth=1 . 2>/dev/null | sort -rh | head -11
    fi
}

# ---- 网络连接统计 ----
cmd_net() {
    header "🌍 网络连接统计"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local total estab listen
        total=$(netstat -an 2>/dev/null | grep -c tcp || echo 0)
        estab=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo 0)
        listen=$(netstat -an 2>/dev/null | grep -c LISTEN || echo 0)
        echo "TCP 总连接: $total"
        echo "ESTABLISHED: $estab"
        echo "LISTEN: $listen"
        echo
        echo "活跃连接 TOP10:"
        netstat -an 2>/dev/null | grep ESTABLISHED | head -10
    else
        if command_exists ss; then
            echo "TCP 连接状态统计:"
            ss -s 2>/dev/null
            echo
            echo "ESTABLISHED TOP10:"
            ss -tunap state established 2>/dev/null | head -11
        elif command_exists netstat; then
            echo "TCP 连接状态统计:"
            netstat -ant 2>/dev/null | awk '{print $6}' | sort | uniq -c | sort -rn
            echo
            echo "ESTABLISHED TOP10:"
            netstat -antp 2>/dev/null | grep ESTABLISHED | head -10
        fi
    fi
}

# ---- 系统概览快照 ----
cmd_top() {
    header "📊 系统概览快照"
    echo "-----------------------------------------------"
    # uptime + 负载
    uptime 2>/dev/null
    echo
    # 内存
    if [[ "$OS_TYPE" == "darwin" ]]; then
        vm_stat 2>/dev/null | head -5
        echo
        echo "CPU 核心: $(sysctl -n hw.ncpu 2>/dev/null || echo '?')"
    else
        free -h 2>/dev/null || free
        echo
        echo "CPU 核心: $(nproc 2>/dev/null || grep -c processor /proc/cpuinfo)"
    fi
}

# ---- 日志入口提示 ----
cmd_logs() {
    header "📋 系统日志入口"
    echo "-----------------------------------------------"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "查看 systemd 服务日志:"
        echo "  sudo journalctl -u <服务名> -f       # 实时跟踪"
        echo "  sudo journalctl -u <服务名> --since today"
        echo "  sudo journalctl -p err -b            # 本次启动的错误日志"
        echo
        echo "常见服务日志文件:"
        echo "  /var/log/syslog 或 /var/log/messages  # 系统日志"
        echo "  /var/log/auth.log 或 /var/log/secure  # 认证日志"
        echo "  /var/log/nginx/                        # Nginx"
        echo "  /var/log/fail2ban.log                  # Fail2ban"
    else
        echo "macOS 日志:"
        echo "  log show --predicate 'processImagePath contains \"<关键字>\"' --last 1h"
        echo "  log stream                             # 实时流"
        echo "  Console.app                            # 图形界面"
        echo
        echo "常见日志文件:"
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
    echo -e "${GREEN}✅ 可用${NC}（纯命令封装，无需安装）"
}

usage() {
    cat <<EOF
用法: $0 {cpu|mem|port|ports|disk|du|net|top|logs|all|status|help}

系统诊断命令集（Linux + macOS）:
  cpu         CPU 占用 TOP10 进程
  mem         内存占用 TOP10 进程
  port <端口> 占用指定端口的进程（如 port 8080）
  ports       所有监听端口一览
  disk        磁盘空间（df -h）
  du          当前目录占用 TOP10
  net         网络连接状态统计
  top         系统概览快照（负载/内存/CPU核心）
  logs        系统日志入口提示
  all         依次展示 top/cpu/mem/disk/net/ports
EOF
}

main() {
    local action="${1:-help}"
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
        status) status_sys_cmd ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
