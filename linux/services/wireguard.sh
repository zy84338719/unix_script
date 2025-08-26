#!/usr/bin/env bash
#
# WireGuard 安装脚本 - Linux 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 检查依赖
check_dependencies() {
    # 检查是否为root用户
    if is_root; then
        print_error "请不要使用 root 用户运行此脚本"
        return 1
    fi
    
    # 检查sudo权限
    if ! sudo -n true 2>/dev/null; then
        print_info "此脚本需要 sudo 权限，请输入密码："
        sudo -v || { print_error "无法获取 sudo 权限"; return 1; }
    fi
    
    return 0
}

# 检测包管理器
detect_package_manager() {
    if command_exists apt-get; then
        echo "apt"
    elif command_exists yum; then
        echo "yum"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists pacman; then
        echo "pacman"
    elif command_exists zypper; then
        echo "zypper"
    else
        return 1
    fi
}

# 检查现有安装
check_existing_installation() {
    if command_exists wg; then
        local version
        version=$(wg --version | head -1)
        print_warning "检测到已安装 WireGuard: $version"
        
        if confirm "是否继续重新配置？" "n"; then
            return 0
        else
            print_info "安装已取消"
            return 1
        fi
    fi
    return 0
}

# 安装 WireGuard 工具
install_wireguard_tools() {
    local pkg_manager="$1"
    
    print_info "正在安装 WireGuard 工具..."
    
    case "$pkg_manager" in
        "apt")
            print_info "使用 APT 包管理器..."
            sudo apt-get update -y
            if sudo apt-get install -y wireguard-tools; then
                print_success "WireGuard 工具安装成功"
            else
                print_error "WireGuard 工具安装失败"
                return 1
            fi
            ;;
        "yum")
            print_info "使用 YUM 包管理器..."
            # 安装 EPEL 仓库（如果需要）
            if ! rpm -q epel-release &>/dev/null; then
                print_info "正在安装 EPEL 仓库..."
                sudo yum install -y epel-release
            fi
            if sudo yum install -y wireguard-tools; then
                print_success "WireGuard 工具安装成功"
            else
                print_error "WireGuard 工具安装失败"
                return 1
            fi
            ;;
        "dnf")
            print_info "使用 DNF 包管理器..."
            if sudo dnf install -y wireguard-tools; then
                print_success "WireGuard 工具安装成功"
            else
                print_error "WireGuard 工具安装失败"
                return 1
            fi
            ;;
        "pacman")
            print_info "使用 Pacman 包管理器..."
            if sudo pacman -S --noconfirm wireguard-tools; then
                print_success "WireGuard 工具安装成功"
            else
                print_error "WireGuard 工具安装失败"
                return 1
            fi
            ;;
        "zypper")
            print_info "使用 Zypper 包管理器..."
            if sudo zypper install -y wireguard-tools; then
                print_success "WireGuard 工具安装成功"
            else
                print_error "WireGuard 工具安装失败"
                return 1
            fi
            ;;
        *)
            print_error "不支持的包管理器：$pkg_manager"
            return 1
            ;;
    esac
    
    return 0
}

# 创建配置目录
create_config_directory() {
    print_info "正在创建配置目录..."
    
    local config_dir="/etc/wireguard"
    
    if sudo mkdir -p "$config_dir"; then
        sudo chmod 700 "$config_dir"
        print_success "配置目录创建成功：$config_dir"
    else
        print_error "配置目录创建失败"
        return 1
    fi
    
    return 0
}

# 生成示例配置文件
generate_example_config() {
    local interface_name="${1:-wg0}"
    local config_file="/etc/wireguard/${interface_name}.conf"
    
    print_info "正在生成示例配置文件..."
    
    # 检查配置文件是否已存在
    if [[ -f "$config_file" ]]; then
        print_warning "配置文件已存在：$config_file"
        if ! confirm "是否覆盖现有配置文件？" "n"; then
            print_info "跳过配置文件生成"
            return 0
        fi
    fi
    
    # 生成密钥对
    local private_key
    local public_key
    
    print_info "正在生成密钥对..."
    private_key=$(wg genkey)
    public_key=$(echo "$private_key" | wg pubkey)
    
    # 创建示例配置
    sudo tee "$config_file" > /dev/null <<EOF
[Interface]
# 本机私钥
PrivateKey = $private_key
# 本机 VPN 内网 IP
Address = 10.0.0.1/24
# 监听端口
ListenPort = 51820
# 开启 IP 转发 (如果作为服务器)
# PostUp = echo 1 > /proc/sys/net/ipv4/ip_forward
# PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# 示例对等节点配置
#[Peer]
# 对等节点公钥
#PublicKey = <PEER_PUBLIC_KEY>
# 允许的 IP 范围
#AllowedIPs = 10.0.0.2/32
# 对等节点端点 (如果是客户端连接到服务器)
#Endpoint = <SERVER_IP>:51820
# 保持连接间隔 (秒)
#PersistentKeepalive = 25
EOF

    if [[ $? -eq 0 ]]; then
        sudo chmod 600 "$config_file"
        print_success "示例配置文件已创建：$config_file"
        echo
        print_info "生成的密钥信息："
        print_info "私钥：$private_key"
        print_info "公钥：$public_key"
        echo
        print_warning "请妥善保管私钥，并根据实际需求修改配置文件！"
    else
        print_error "配置文件创建失败"
        return 1
    fi
    
    return 0
}

# 启用 systemd 服务
enable_systemd_service() {
    local interface_name="${1:-wg0}"
    
    print_info "正在配置 systemd 服务..."
    
    # 启用并启动 WireGuard 服务
    if sudo systemctl enable "wg-quick@${interface_name}"; then
        print_success "WireGuard 服务已设置为开机自启"
    else
        print_error "WireGuard 服务配置失败"
        return 1
    fi
    
    # 询问是否立即启动
    if confirm "是否立即启动 WireGuard 服务？" "n"; then
        if sudo systemctl start "wg-quick@${interface_name}"; then
            print_success "WireGuard 服务启动成功"
        else
            print_error "WireGuard 服务启动失败"
            print_info "请检查配置文件并手动启动：sudo systemctl start wg-quick@${interface_name}"
        fi
    fi
    
    return 0
}

# 配置防火墙
configure_firewall() {
    local port="${1:-51820}"
    
    print_info "检查防火墙配置..."
    
    # 检查 ufw
    if command_exists ufw && sudo ufw status | grep -q "Status: active"; then
        print_info "检测到 UFW 防火墙，正在开放端口 $port..."
        if sudo ufw allow "$port/udp"; then
            print_success "UFW 防火墙规则添加成功"
        else
            print_warning "UFW 防火墙规则添加失败，请手动配置"
        fi
    # 检查 firewalld
    elif command_exists firewall-cmd && sudo firewall-cmd --state &>/dev/null; then
        print_info "检测到 firewalld 防火墙，正在开放端口 $port..."
        if sudo firewall-cmd --permanent --add-port="$port/udp" && sudo firewall-cmd --reload; then
            print_success "firewalld 防火墙规则添加成功"
        else
            print_warning "firewalld 防火墙规则添加失败，请手动配置"
        fi
    else
        print_info "未检测到活动的防火墙或防火墙已关闭"
    fi
}

# 验证安装
verify_installation() {
    print_info "正在验证安装..."
    
    # 检查 WireGuard 工具
    if command_exists wg && command_exists wg-quick; then
        local version
        version=$(wg --version | head -1)
        print_success "WireGuard 工具安装成功：$version"
    else
        print_error "WireGuard 工具验证失败"
        return 1
    fi
    
    # 检查配置目录
    if [[ -d "/etc/wireguard" ]]; then
        print_success "配置目录已创建：/etc/wireguard"
    else
        print_warning "配置目录不存在"
    fi
    
    return 0
}

# 主安装函数
install_wireguard() {
    print_header "🚀 安装 WireGuard - Linux 平台"
    echo "========================================"
    
    # 执行安装步骤
    if ! check_dependencies; then
        return 1
    fi
    
    if ! check_existing_installation; then
        return 1
    fi
    
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    if [[ $? -ne 0 ]]; then
        print_error "未检测到支持的包管理器"
        print_info "支持的包管理器：apt, yum, dnf, pacman, zypper"
        return 1
    fi
    
    print_info "检测到包管理器：$pkg_manager"
    
    # 确认安装
    echo
    print_info "即将安装 WireGuard VPN 工具"
    print_info "这将安装 wireguard-tools 包"
    echo
    
    if ! confirm "确认继续安装？" "n"; then
        print_info "安装已取消"
        return 1
    fi
    
    # 执行安装
    if ! install_wireguard_tools "$pkg_manager"; then
        return 1
    fi
    
    if ! create_config_directory; then
        return 1
    fi
    
    if ! generate_example_config "wg0"; then
        return 1
    fi
    
    if ! enable_systemd_service "wg0"; then
        return 1
    fi
    
    configure_firewall "51820"
    
    if ! verify_installation; then
        return 1
    fi
    
    echo
    print_success "🎉 WireGuard 安装完成！"
    echo "========================================"
    print_info "配置文件位置：/etc/wireguard/wg0.conf"
    print_info "请根据您的网络环境修改配置文件"
    echo
    print_info "常用命令："
    echo "  启动：sudo systemctl start wg-quick@wg0"
    echo "  停止：sudo systemctl stop wg-quick@wg0"
    echo "  重启：sudo systemctl restart wg-quick@wg0"
    echo "  状态：sudo systemctl status wg-quick@wg0"
    echo "  连接状态：sudo wg show"
    echo "  编辑配置：sudo nano /etc/wireguard/wg0.conf"
    echo
    print_warning "重要提示："
    echo "1. 请妥善保管生成的私钥"
    echo "2. 根据实际需求配置防火墙规则"
    echo "3. 如作为服务器使用，需要配置 IP 转发"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_wireguard
fi
