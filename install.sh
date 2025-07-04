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
    print_header "🚀 一键安装脚本 - 服务管理工具"
    echo "========================================"
    show_system_info
    
    print_menu "请选择要安装的服务："
    echo
    echo "  1) Node Exporter     - Prometheus 系统监控数据收集器"
    echo "  2) DDNS-GO          - 动态域名解析服务"
    echo "  3) 查看已安装服务    - 检查当前系统中已安装的服务"
    echo "  4) 卸载服务         - 卸载已安装的服务"
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
            echo "✅ 已安装并运行 ($version)"
        else
            echo "⚠️  已安装但未运行 ($version)"
        fi
    else
        echo "❌ 未安装"
    fi
}

# 显示已安装服务状态
show_installed_services() {
    clear
    print_header "📊 已安装服务状态"
    echo "========================================"
    
    echo "Node Exporter:  $(check_service_status "node_exporter" "/usr/local/bin/node_exporter" "com.prometheus.node_exporter")"
    echo "DDNS-GO:        $(check_service_status "ddns-go" "/opt/ddns-go/ddns-go" "jeessy.ddns-go")"
    
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
    read -p "按回车键返回主菜单..."
}

# 卸载服务菜单
show_uninstall_menu() {
    clear
    print_header "🗑️  卸载服务"
    echo "========================================"
    
    print_warning "注意：卸载操作将完全移除服务及其配置文件！"
    echo
    
    echo "  1) 卸载 Node Exporter"
    echo "  2) 卸载 DDNS-GO"
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
        sudo rm -f /usr/local/bin/node_exporter
        sudo userdel node_exporter &>/dev/null || true
        sudo systemctl daemon-reload
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/com.prometheus.node_exporter.plist
        sudo rm -f /usr/local/bin/node_exporter
        sudo rm -f /var/log/node_exporter.log
        sudo rm -f /var/log/node_exporter.err
    fi
    
    print_success "Node Exporter 已成功卸载！"
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
    read -p "按回车键返回主菜单..."
}

# 主函数
main() {
    # 检查系统信息
    check_os
    check_arch
    
    while true; do
        show_main_menu
        
        read -p "请输入选项 [0-4]: " choice
        
        case $choice in
            1)
                run_install_script "./node_exporter/install.sh" "Node Exporter"
                ;;
            2)
                run_install_script "./ddns-go/install.sh" "DDNS-GO"
                ;;
            3)
                show_installed_services
                ;;
            4)
                while true; do
                    show_uninstall_menu
                    read -p "请输入选项 [0-2]: " uninstall_choice
                    
                    case $uninstall_choice in
                        1)
                            echo
                            read -p "确认卸载 Node Exporter？[y/N]: " -n 1 -r
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_node_exporter
                                echo
                                read -p "按回车键继续..."
                            fi
                            ;;
                        2)
                            echo
                            read -p "确认卸载 DDNS-GO？[y/N]: " -n 1 -r
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_ddns_go
                                echo
                                read -p "按回车键继续..."
                            fi
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

# 脚本入口点
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
