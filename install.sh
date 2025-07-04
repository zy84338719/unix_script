#!/usr/bin/env bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }
print_menu() { echo -e "${PURPLE}$1${NC}"; }

# 检查操作系统
check_os() {
    os_name=$(uname -s)
    case "$os_name" in
        "Darwin")
            OS_TYPE="macOS"
            ;;
        "Linux")
            OS_TYPE="Linux"
            ;;
        *)
            print_error "不支持的操作系统：$os_name"
            exit 1
            ;;
    esac
}

# 检查架构
check_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            ARCH_TYPE="x86_64"
            ;;
        aarch64|arm64)
            ARCH_TYPE="ARM64"
            ;;
        armv7l)
            ARCH_TYPE="ARMv7"
            ;;
        *)
            ARCH_TYPE="$arch"
            ;;
    esac
}

# 显示系统信息
show_system_info() {
    print_header "🖥️  系统信息"
    echo "───────────────────────────────"
    echo "操作系统: $OS_TYPE"
    echo "CPU架构:  $ARCH_TYPE"
    echo "───────────────────────────────"
    echo
}

# 显示主菜单
show_main_menu() {
    clear
    print_header "🚀 一键安装脚本 - 服务与环境管理工具"
    echo "========================================"
    show_system_info
    
    print_menu "请选择要安装的服务或配置环境："
    echo
    echo "  --- 服务安装 ---"
    echo "  1) Node Exporter     - Prometheus 系统监控数据收集器"
    echo "  2) DDNS-GO           - 动态域名解析服务"
    echo "  3) WireGuard         - 现代、快速、安全的 VPN"
    echo
    echo "  --- 开发环境配置 ---"
    echo "  4) Zsh & Oh My Zsh   - 自动配置 Zsh 开发环境"
    echo
    echo "  --- 系统工具 ---"
    echo "  5) 自动关机管理     - 设置临时或每日定时关机"
    echo
    echo "  --- 管理 ---"
    echo "  8) 查看已安装状态    - 检查服务和环境的安装情况"
    echo "  9) 卸载服务/环境     - 移除已安装的服务或环境"
    echo "  0) 退出"
    echo
    echo "========================================"
}

# 检查服务是否已安装
check_service_status() {
    local service_name="$1"
    local binary_path="$2"
    local service_file="$3"
    
    local is_installed=false
    local is_running=false
    local version=""
    
    # 检查二进制文件是否存在
    if command -v "$service_name" &> /dev/null || [ -f "$binary_path" ]; then
        is_installed=true
        if command -v "$service_name" &> /dev/null; then
            version=$($service_name --version 2>/dev/null | head -1 || echo "未知版本")
        fi
    fi
    
    # 检查服务是否运行
    if [[ "$OS_TYPE" == "Linux" ]]; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            is_running=true
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        if sudo launchctl list | grep -q "$service_file" 2>/dev/null; then
            is_running=true
        fi
    fi
    
    # 返回状态
    if $is_installed; then
        if $is_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($version)"
        else
            echo -e "${YELLOW}⚠️  已安装但未运行${NC} ($version)"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 检查每日关机任务是否已配置
check_shutdown_timer_status() {
    local is_configured=false
    if [[ "$OS_TYPE" == "macOS" ]]; then
        if [ -f "/Library/LaunchDaemons/com.user.dailyshutdown.plist" ]; then
            is_configured=true
        fi
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        # crontab -l 在没有 crontab 时会返回非零退出码
        if crontab -l 2>/dev/null | grep -q "# AUTO_SHUTDOWN_SCRIPT"; then
            is_configured=true
        fi
    fi

    if $is_configured; then
        echo -e "${GREEN}✅ 已配置每日定时关机${NC}"
    else
        echo -e "${RED}❌ 未配置${NC}"
    fi
}

# 检查 WireGuard 是否已安装
check_wireguard_status() {
    local wg_installed=false
    local service_running=false
    local interface="wg0"

    if command -v wg &> /dev/null; then
        wg_installed=true
    fi

    if [[ "$OS_TYPE" == "Linux" ]]; then
        if systemctl is-active --quiet "wg-quick@${interface}" 2>/dev/null; then
            service_running=true
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        if sudo launchctl list | grep -q "com.wireguard.${interface}" 2>/dev/null; then
            service_running=true
        fi
    fi

    if $wg_installed; then
        if $service_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} (接口: ${interface})"
        else
            echo -e "${YELLOW}⚠️  已安装但服务未运行${NC}"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 管理 WireGuard 的子菜单
manage_wireguard() {
    local script_path="./wireguard/install.sh"

    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        sleep 2
        return
    fi
    chmod +x "$script_path"

    while true; do
        clear
        print_header "🔧 WireGuard 管理"
        echo "========================================"
        echo "当前状态:"
        echo "  - WireGuard 工具: $(command -v wg &>/dev/null && echo -e "${GREEN}✅ 已安装${NC}" || echo -e "${RED}❌ 未安装${NC}")"
        local wg_status_output
        wg_status_output=$(check_wireguard_status)
        if [[ $wg_status_output == *"运行"* ]]; then
            echo -e "  - 开机自启服务: ${GREEN}✅ 已配置并运行${NC}"
        elif [[ $wg_status_output == *"未运行"* ]]; then
            echo -e "  - 开机自启服务: ${YELLOW}⚠️  已配置但未运行${NC}"
        else
            echo -e "  - 开机自启服务: ${RED}❌ 未配置${NC}"
        fi
        echo
        print_menu "请选择操作:"
        echo "  1) 安装/更新 WireGuard 工具"
        echo "  2) 配置/重置开机自启服务"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-2]: " wg_choice

        case $wg_choice in
            1)
                print_info "正在调用 WireGuard 工具安装脚本..."
                "$script_path" install_tools
                echo
                read -r -p "按回车键继续..."
                ;;
            2)
                print_info "正在调用 WireGuard 服务配置脚本..."
                "$script_path" configure_service
                echo
                read -r -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选项，请重新输入！"
                sleep 1
                ;;
        esac
    done
}

# 检查 Zsh 和 Oh My Zsh 是否已安装
check_zsh_status() {
    local zsh_installed=false
    local omz_installed=false
    
    if command -v zsh &> /dev/null; then
        zsh_installed=true
    fi
    
    if [ -d "$HOME/.oh-my-zsh" ]; then
        omz_installed=true
    fi
    
    if $zsh_installed && $omz_installed; then
        echo -e "${GREEN}✅ Zsh & Oh My Zsh 已安装${NC}"
    elif $zsh_installed; then
        echo -e "${YELLOW}⚠️  已安装 Zsh，但未安装 Oh My Zsh${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}


# 显示已安装服务状态
show_installed_services() {
    clear
    print_header "📊 已安装状态"
    echo "========================================"
    
    echo "--- 服务 ---"
    echo "Node Exporter:  $(check_service_status "node_exporter" "/usr/local/bin/node_exporter" "com.prometheus.node_exporter")"
    echo "DDNS-GO:        $(check_service_status "ddns-go" "/opt/ddns-go/ddns-go" "jeessy.ddns-go")"
    echo "WireGuard:      $(check_wireguard_status)"
    echo
    echo "--- 开发环境 ---"
    echo "Zsh 环境:       $(check_zsh_status)"
    echo
    echo "--- 系统工具 ---"
    echo "自动关机任务: $(check_shutdown_timer_status)"

    echo
    echo "========================================"
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        print_info "Linux 服务管理命令："
        echo "  查看状态: sudo systemctl status <service-name>"
        echo "  查看日志: sudo journalctl -u <service-name> -f"
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        print_info "macOS 服务管理命令："
        echo "  查看状态: sudo launchctl list | grep <service>"
        echo "  查看日志: tail -f /var/log/<service>.log"
    fi
    
    echo
    read -r -p "按回车键返回主菜单..."
}

# 卸载服务菜单
show_uninstall_menu() {
    clear
    print_header "🗑️  卸载服务与环境"
    echo "========================================"
    
    print_warning "注意：卸载操作将完全移除服务及其配置文件！"
    echo
    
    echo "  1) 卸载 Node Exporter"
    echo "  2) 卸载 DDNS-GO"
    echo "  3) 卸载 WireGuard (服务和配置)"
    echo "  4) 卸载 Zsh & Oh My Zsh (查看说明)"
    echo "  5) 取消每日自动关机任务"
    echo "  0) 返回主菜单"
    echo
    echo "========================================"
}

# 卸载 Node Exporter
uninstall_node_exporter() {
    print_info "正在卸载 Node Exporter..."
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        sudo systemctl stop node_exporter &>/dev/null || true
        sudo systemctl disable node_exporter &>/dev/null || true
        sudo rm -f /etc/systemd/system/node_exporter.service
        sudo systemctl daemon-reload &>/dev/null || true
        sudo rm -f /usr/local/bin/node_exporter
        # 只有当用户存在时才尝试删除
        if id "node_exporter" &>/dev/null; then
            sudo userdel node_exporter
        fi
        print_success "Node Exporter 已卸载。"
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/com.prometheus.node_exporter.plist
        sudo rm -f /usr/local/bin/node_exporter
        sudo rm -f /var/log/node_exporter.log
        sudo rm -f /var/log/node_exporter.err
    fi
    
    print_success "Node Exporter 已成功卸载！"
}

# 取消每日自动关机
uninstall_shutdown_timer() {
    print_info "正在取消每日自动关机任务..."
    local script_path="./shutdown_timer/shutdown_timer.sh"
    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        return
    fi
    # 使用脚本自身的取消功能
    chmod +x "$script_path"
    # 非交互式地调用取消功能
    "$script_path" cancel_daily_shutdown_internal
}

# 卸载 DDNS-GO
uninstall_ddns_go() {
    print_info "正在卸载 DDNS-GO..."
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        sudo systemctl stop ddns-go &>/dev/null || true
        sudo systemctl disable ddns-go &>/dev/null || true
        sudo rm -rf /opt/ddns-go
        sudo systemctl daemon-reload
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/jeessy.ddns-go.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/jeessy.ddns-go.plist
        sudo rm -rf /opt/ddns-go
    fi
    
    print_success "DDNS-GO 已成功卸载！"
}

# 卸载 WireGuard
uninstall_wireguard() {
    local script_path="./wireguard/install.sh"
    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        return
    fi

    print_info "正在卸载 WireGuard 开机自启服务..."
    "$script_path" uninstall_service

    echo
    read -r -p "是否删除 /etc/wireguard/ 目录下的 .conf 配置文件？[y/N]: " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$OS_TYPE" == "Linux" ]]; then
            sudo rm -f /etc/wireguard/*.conf
        elif [[ "$OS_TYPE" == "macOS" ]]; then
            sudo rm -f /usr/local/etc/wireguard/*.conf
        fi
        print_success "配置文件已删除。"
    fi

    print_warning "服务已移除。要完全卸载，请使用包管理器 (e.g., apt, brew) 手动移除 'wireguard-tools'。"
    print_success "WireGuard 卸载完成！"
}

# 卸载 Zsh & Oh My Zsh (提供说明)
uninstall_zsh_omz() {
    print_warning "卸载 Zsh 和 Oh My Zsh 是一个敏感操作，建议手动执行以避免风险。"
    print_info "Oh My Zsh 官方提供了一个卸载脚本，您可以运行它："
    echo "  uninstall_oh_my_zsh"
    echo
    print_info "卸载 Zsh 本身，请使用系统的包管理器，例如："
    echo "  - Ubuntu/Debian: sudo apt-get remove --purge zsh"
    echo "  - CentOS/RHEL:   sudo yum remove zsh"
    echo "  - macOS (Homebrew): brew uninstall zsh"
    echo
    print_warning "在卸载 Zsh 之前，请务必将您的默认 shell 切换回 bash 或其他 shell！"
    echo "  chsh -s /bin/bash"
    echo
    print_info "更多详细信息，请参考项目的 README.md 文档。"
}


# 执行安装脚本
run_install_script() {
    local script_path="$1"
    local service_name="$2"
    
    if [ ! -f "$script_path" ]; then
        print_error "安装脚本不存在：$script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        print_info "设置脚本执行权限..."
        chmod +x "$script_path"
    fi
    
    print_info "开始安装 $service_name..."
    echo
    
    if "$script_path"; then
        echo
        print_success "$service_name 安装完成！"
    else
        echo
        print_error "$service_name 安装失败！"
        return 1
    fi
    
    echo
    read -r -p "按回车键返回主菜单..."
}

# 主函数
main() {
    # 检查系统信息
    check_os
    check_arch
    
    while true; do
        show_main_menu
        
        read -r -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1)
                run_install_script "./node_exporter/install.sh" "Node Exporter"
                ;;
            2)
                run_install_script "./ddns-go/install.sh" "DDNS-GO"
                ;;
            3)
                manage_wireguard
                ;;
            4)
                run_install_script "./zsh_setup/install.sh" "Zsh & Oh My Zsh"
                ;;
            5)
                manage_shutdown_timer
                ;;
            8)
                show_installed_services
                ;;
            9)
                while true; do
                    show_uninstall_menu
                    read -r -p "请输入选项 [0-5]: " uninstall_choice
                    
                    case $uninstall_choice in
                        1)
                            echo
                            read -r -p "确认卸载 Node Exporter？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_node_exporter
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        2)
                            echo
                            read -r -p "确认卸载 DDNS-GO？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_ddns_go
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        3)
                            echo
                            read -r -p "确认卸载 WireGuard 服务和相关配置？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_wireguard
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        4)
                            print_warning "卸载 Zsh & Oh My Zsh 是一个敏感操作，建议您按照 README 中的说明手动执行。"
                            read -r -p "按回车键返回..."
                            ;;
                        5)
                            uninstall_shutdown_timer
                            read -r -p "按回车键继续..."
                            ;;
                        0)
                            break
                            ;;
                        *)
                            print_error "无效选项，请重新输入！"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            0)
                print_info "感谢使用！再见！"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新输入！"
                sleep 1
                ;;
        esac
    done
}

# 管理自动关机脚本
manage_shutdown_timer() {
    local script_path="./shutdown_timer/shutdown_timer.sh"
    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        sleep 2
        return
    fi
    chmod +x "$script_path"
    # 直接执行脚本，进入其交互式菜单
    clear
    "$script_path"
    print_info "已从自动关机管理返回主菜单。"
    read -r -p "按回车键继续..."
}

# --- 脚本入口 ---
main
