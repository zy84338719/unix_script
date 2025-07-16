#!/usr/bin/env bash
#
# macOS 平台系统工具集合
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# macOS 平台特定目录
MACOS_DIR="$(dirname "${BASH_SOURCE[0]}")"

# 显示主菜单
show_main_menu() {
    clear
    print_header "🍎 macOS 系统工具集合"
    echo "========================================"
    
    print_menu "请选择要安装的服务或配置环境："
    echo
    echo "  --- 服务安装 ---"
    echo "  1) Node Exporter     - Prometheus 系统监控数据收集器"
    echo "  2) DDNS-GO           - 动态域名解析服务"
    echo "  3) WireGuard         - 现代、快速、安全的 VPN"
    echo
    echo "  --- 开发环境配置 ---"
    echo "  4) Zsh & Oh My Zsh   - 自动配置 Zsh 开发环境"
    echo "  5) Homebrew          - macOS 包管理器"
    echo
    echo "  --- 系统工具 ---"
    echo "  6) 自动关机管理     - 设置临时或每日定时关机"
    echo "  7) 进程管理工具     - 智能搜索和管理系统进程"
    echo
    echo "  --- 管理 ---"
    echo "  8) 查看已安装状态    - 检查服务和环境的安装情况"
    echo "  9) 卸载服务/环境     - 移除已安装的服务或环境"
    echo "  0) 退出"
    echo
    echo "========================================"
}

# 处理用户选择
handle_choice() {
    local choice="$1"
    
    case $choice in
        1)
            print_info "启动 Node Exporter 安装..."
            source "${MACOS_DIR}/services/node_exporter.sh"
            ;;
        2)
            print_info "启动 DDNS-GO 安装..."
            source "${MACOS_DIR}/services/ddns_go.sh"
            ;;
        3)
            print_info "启动 WireGuard 安装..."
            source "${MACOS_DIR}/services/wireguard.sh"
            ;;
        4)
            print_info "启动 Zsh 环境配置..."
            source "${MACOS_DIR}/environments/zsh_setup.sh"
            ;;
        5)
            print_info "启动 Homebrew 安装..."
            source "${MACOS_DIR}/environments/homebrew.sh"
            ;;
        6)
            print_info "启动自动关机管理..."
            source "${MACOS_DIR}/tools/shutdown_timer.sh"
            ;;
        7)
            print_info "启动进程管理工具..."
            source "${MACOS_DIR}/tools/process_manager.sh"
            ;;
        8)
            print_info "检查已安装状态..."
            source "${MACOS_DIR}/management/status_check.sh"
            ;;
        9)
            print_info "启动卸载程序..."
            source "${MACOS_DIR}/management/uninstall.sh"
            ;;
        0)
            print_success "退出程序"
            exit 0
            ;;
        *)
            print_error "无效选择：$choice"
            wait_for_key
            ;;
    esac
}

# 主循环
main_loop() {
    while true; do
        show_main_menu
        echo -n "请输入选择 [0-9]: "
        read -r choice
        echo
        
        handle_choice "$choice"
        
        if [[ "$choice" != "0" ]]; then
            echo
            wait_for_key "按任意键返回主菜单..."
        fi
    done
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_loop "$@"
fi
