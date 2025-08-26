#!/usr/bin/env bash
#
# DDNS-GO 安装脚本 - macOS 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 检查依赖
check_dependencies() {
    local deps=("curl" "tar")
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            print_error "缺少必要命令：$dep"
            return 1
        fi
    done
    
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

# 检查现有安装
check_existing_installation() {
    if [[ -f "/opt/ddns-go/ddns-go" ]]; then
        local current_version
        current_version=$(/opt/ddns-go/ddns-go --version 2>&1 | head -1)
        print_warning "检测到已安装 DDNS-GO: $current_version"
        
        if confirm "是否继续并覆盖安装最新版本？" "n"; then
            print_info "正在停止现有服务..."
            # 停止 launchd 服务
            if sudo launchctl list | grep -q "com.ddns-go.service"; then
                sudo launchctl bootout system /Library/LaunchDaemons/com.ddns-go.service.plist &>/dev/null || true
            fi
            return 0
        else
            print_info "安装已取消"
            return 1
        fi
    fi
    return 0
}

# 获取最新版本
get_latest_version() {
    print_info "正在获取最新版本信息..."
    local api_url="https://api.github.com/repos/jeessy2/ddns-go/releases/latest"
    local latest
    latest=$(curl -s "$api_url" | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
    
    if [[ -z "$latest" ]]; then
        print_error "无法获取最新版本信息，请检查网络连接"
        return 1
    fi
    
    echo "$latest"
}

# 确定架构
get_arch_suffix() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "darwin_x86_64";;
        arm64) echo "darwin_arm64";;
        *) print_error "不支持的 macOS 架构：$arch"; return 1;;
    esac
}

# 下载和安装
download_and_install() {
    local version="$1"
    local arch_suffix="$2"
    
    print_info "正在下载 DDNS-GO v$version..."
    
    local tmpdir=$(mktemp -d)
    setup_cleanup "$tmpdir"
    
    local url="https://github.com/jeessy2/ddns-go/releases/download/v${version}/ddns-go_${version}_${arch_suffix}.tar.gz"
    
    if ! safe_download "$url" "$tmpdir/ddns-go.tar.gz"; then
        return 1
    fi
    
    print_info "正在解压..."
    if ! tar -xzf "$tmpdir/ddns-go.tar.gz" -C "$tmpdir"; then
        print_error "解压失败"
        return 1
    fi
    
    print_info "正在安装..."
    # 创建安装目录
    sudo mkdir -p /opt/ddns-go
    
    # 移动二进制文件
    if sudo mv "$tmpdir/ddns-go" /opt/ddns-go/; then
        sudo chmod 755 /opt/ddns-go/ddns-go
        sudo chown root:wheel /opt/ddns-go/ddns-go
        print_success "DDNS-GO 安装完成"
    else
        print_error "二进制文件安装失败"
        return 1
    fi
    
    return 0
}

# 创建 launchd 服务
create_launchd_service() {
    print_info "正在创建 launchd 服务..."
    
    local plist_file="/Library/LaunchDaemons/com.ddns-go.service.plist"
    local log_dir="/var/log"
    
    # 确保日志目录存在
    ensure_dir "$log_dir"
    
    sudo tee "$plist_file" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ddns-go.service</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/ddns-go/ddns-go</string>
        <string>-l</string>
        <string>:9876</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/ddns-go.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/ddns-go.err</string>
    <key>UserName</key>
    <string>nobody</string>
    <key>GroupName</key>
    <string>nobody</string>
    <key>WorkingDirectory</key>
    <string>/opt/ddns-go</string>
</dict>
</plist>
EOF

    if [[ $? -eq 0 ]]; then
        print_success "launchd 服务文件创建成功"
    else
        print_error "launchd 服务文件创建失败"
        return 1
    fi
    
    # 设置权限
    sudo chown root:wheel "$plist_file"
    sudo chmod 644 "$plist_file"
    
    # 加载并启动服务
    print_info "正在启用和启动服务..."
    if sudo launchctl load "$plist_file"; then
        print_success "DDNS-GO 服务启动成功"
    else
        print_error "DDNS-GO 服务启动失败"
        return 1
    fi
    
    return 0
}

# 配置防火墙
configure_firewall() {
    print_info "检查防火墙配置..."
    
    # macOS 通常使用应用程序防火墙，一般不需要特殊配置
    if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled"; then
        print_info "检测到应用程序防火墙已启用"
        print_info "如需从外部访问，请在 系统偏好设置 > 安全性与隐私 > 防火墙 中配置"
    else
        print_info "应用程序防火墙未启用"
    fi
}

# 验证安装
verify_installation() {
    print_info "正在验证安装..."
    
    # 检查服务状态
    if sudo launchctl list | grep -q "com.ddns-go.service"; then
        print_success "DDNS-GO 服务运行正常"
    else
        print_error "DDNS-GO 服务未运行"
        return 1
    fi
    
    # 检查端口
    sleep 3
    if check_port 9876; then
        print_success "DDNS-GO 监听端口 9876"
    else
        print_warning "端口 9876 未检测到监听，服务可能正在启动中"
    fi
    
    # 显示版本信息
    local version
    version=$(/opt/ddns-go/ddns-go --version 2>&1 | head -1)
    print_success "安装的版本：$version"
    
    return 0
}

# 主安装函数
install_ddns_go() {
    print_header "🚀 安装 DDNS-GO - macOS 平台"
    echo "========================================"
    
    # 执行安装步骤
    if ! check_dependencies; then
        return 1
    fi
    
    if ! check_existing_installation; then
        return 1
    fi
    
    local version
    version=$(get_latest_version)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local arch_suffix
    arch_suffix=$(get_arch_suffix)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    print_info "检测到架构：$(uname -m) -> $arch_suffix"
    
    # 确认安装
    echo
    print_info "即将安装 DDNS-GO v$version"
    print_info "安装位置：/opt/ddns-go/"
    print_info "Web界面端口：9876"
    echo
    
    if ! confirm "确认继续安装？" "n"; then
        print_info "安装已取消"
        return 1
    fi
    
    # 执行安装
    if ! download_and_install "$version" "$arch_suffix"; then
        return 1
    fi
    
    if ! create_launchd_service; then
        return 1
    fi
    
    configure_firewall
    
    if ! verify_installation; then
        return 1
    fi
    
    echo
    print_success "🎉 DDNS-GO 安装完成！"
    echo "========================================"
    print_info "Web 管理界面：http://localhost:9876"
    print_info "默认账户：admin"
    print_info "默认密码：admin"
    echo
    print_warning "首次登录后请及时修改默认密码！"
    echo
    print_info "服务管理："
    echo "  启动：sudo launchctl load /Library/LaunchDaemons/com.ddns-go.service.plist"
    echo "  停止：sudo launchctl unload /Library/LaunchDaemons/com.ddns-go.service.plist"
    echo "  状态：sudo launchctl list | grep ddns-go"
    echo "  日志：tail -f /var/log/ddns-go.log"
    echo "  错误：tail -f /var/log/ddns-go.err"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_ddns_go
fi
