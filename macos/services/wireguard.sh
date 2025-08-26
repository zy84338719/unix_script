#!/usr/bin/env bash
#
# WireGuard 安装脚本 - macOS 平台
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
    
    # 检查 Homebrew
    if ! command_exists brew; then
        print_error "未检测到 Homebrew，WireGuard 需要通过 Homebrew 安装"
        print_info "请先安装 Homebrew：https://brew.sh/"
        print_info "或使用 App Store 安装 WireGuard 应用"
        return 1
    fi
    
    return 0
}

# 检查现有安装
check_existing_installation() {
    local wg_installed=false
    local wg_app_installed=false
    
    # 检查命令行工具
    if command_exists wg; then
        wg_installed=true
        local version
        version=$(wg --version | head -1)
        print_info "检测到 WireGuard 命令行工具：$version"
    fi
    
    # 检查 macOS 应用
    if [[ -d "/Applications/WireGuard.app" ]]; then
        wg_app_installed=true
        print_info "检测到 WireGuard macOS 应用"
    fi
    
    if $wg_installed || $wg_app_installed; then
        print_warning "检测到已安装的 WireGuard 组件"
        
        if confirm "是否继续安装/重新配置？" "n"; then
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
    print_info "正在通过 Homebrew 安装 WireGuard 工具..."
    
    # 更新 Homebrew
    print_info "正在更新 Homebrew..."
    if brew update; then
        print_success "Homebrew 更新成功"
    else
        print_warning "Homebrew 更新失败，继续安装..."
    fi
    
    # 安装 WireGuard 工具
    print_info "正在安装 wireguard-tools..."
    if brew install wireguard-tools; then
        print_success "WireGuard 命令行工具安装成功"
    else
        print_error "WireGuard 工具安装失败"
        return 1
    fi
    
    return 0
}

# 推荐安装 WireGuard 应用
recommend_wireguard_app() {
    print_info "推荐同时安装 WireGuard macOS 应用"
    echo
    print_info "WireGuard macOS 应用提供："
    echo "  • 图形化界面配置"
    echo "  • 更好的 macOS 集成"
    echo "  • 菜单栏快速控制"
    echo "  • 系统通知支持"
    echo
    
    if confirm "是否打开 App Store 安装 WireGuard 应用？" "y"; then
        print_info "正在打开 App Store..."
        open "macappstore://apps.apple.com/app/wireguard/id1451685025"
        print_info "请在 App Store 中手动安装 WireGuard 应用"
        wait_for_key "安装完成后按任意键继续..."
    fi
}

# 创建配置目录
create_config_directory() {
    print_info "正在创建配置目录..."
    
    local config_dir="/usr/local/etc/wireguard"
    
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
    local config_dir="/usr/local/etc/wireguard"
    local config_file="${config_dir}/${interface_name}.conf"
    
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
# DNS 服务器 (可选)
DNS = 8.8.8.8, 8.8.4.4

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

# 创建 launchd 服务
create_launchd_service() {
    local interface_name="${1:-wg0}"
    local plist_file="/Library/LaunchDaemons/com.wireguard.${interface_name}.plist"
    
    print_info "正在创建 launchd 服务..."
    
    # 检查服务文件是否已存在
    if [[ -f "$plist_file" ]]; then
        print_warning "服务文件已存在：$plist_file"
        if ! confirm "是否覆盖现有服务文件？" "n"; then
            print_info "跳过服务文件创建"
            return 0
        fi
        # 停止现有服务
        sudo launchctl bootout system "$plist_file" &>/dev/null || true
    fi
    
    sudo tee "$plist_file" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wireguard.$interface_name</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/wg-quick</string>
        <string>up</string>
        <string>/usr/local/etc/wireguard/$interface_name.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/var/log/wireguard-$interface_name.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/wireguard-$interface_name.err</string>
</dict>
</plist>
EOF

    if [[ $? -eq 0 ]]; then
        sudo chmod 644 "$plist_file"
        sudo chown root:wheel "$plist_file"
        print_success "launchd 服务文件创建成功"
    else
        print_error "launchd 服务文件创建失败"
        return 1
    fi
    
    # 询问是否启用自动启动
    if confirm "是否启用开机自动连接 WireGuard？" "n"; then
        if sudo launchctl load "$plist_file"; then
            print_success "WireGuard 服务已设置为开机自启"
        else
            print_error "WireGuard 服务配置失败"
            return 1
        fi
    else
        print_info "可以稍后手动启用：sudo launchctl load $plist_file"
    fi
    
    return 0
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
    if [[ -d "/usr/local/etc/wireguard" ]]; then
        print_success "配置目录已创建：/usr/local/etc/wireguard"
    else
        print_warning "配置目录不存在"
    fi
    
    return 0
}

# 主安装函数
install_wireguard() {
    print_header "🚀 安装 WireGuard - macOS 平台"
    echo "========================================"
    
    # 执行安装步骤
    if ! check_dependencies; then
        return 1
    fi
    
    if ! check_existing_installation; then
        return 1
    fi
    
    # 确认安装
    echo
    print_info "即将安装 WireGuard VPN 工具"
    print_info "这将通过 Homebrew 安装 wireguard-tools"
    echo
    
    if ! confirm "确认继续安装？" "n"; then
        print_info "安装已取消"
        return 1
    fi
    
    # 执行安装
    if ! install_wireguard_tools; then
        return 1
    fi
    
    recommend_wireguard_app
    
    if ! create_config_directory; then
        return 1
    fi
    
    if ! generate_example_config "wg0"; then
        return 1
    fi
    
    if ! create_launchd_service "wg0"; then
        return 1
    fi
    
    if ! verify_installation; then
        return 1
    fi
    
    echo
    print_success "🎉 WireGuard 安装完成！"
    echo "========================================"
    print_info "配置文件位置：/usr/local/etc/wireguard/wg0.conf"
    print_info "请根据您的网络环境修改配置文件"
    echo
    print_info "常用命令："
    echo "  启动：sudo wg-quick up wg0"
    echo "  停止：sudo wg-quick down wg0"
    echo "  连接状态：sudo wg show"
    echo "  编辑配置：sudo nano /usr/local/etc/wireguard/wg0.conf"
    echo
    print_info "launchd 服务管理："
    echo "  启用自启：sudo launchctl load /Library/LaunchDaemons/com.wireguard.wg0.plist"
    echo "  禁用自启：sudo launchctl unload /Library/LaunchDaemons/com.wireguard.wg0.plist"
    echo "  查看状态：sudo launchctl list | grep wireguard"
    echo
    print_warning "重要提示："
    echo "1. 请妥善保管生成的私钥"
    echo "2. macOS 可能需要授权 WireGuard 访问网络"
    echo "3. 推荐同时使用 WireGuard macOS 应用进行管理"
    echo "4. 首次运行可能需要在系统偏好设置中允许内核扩展"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_wireguard
fi
