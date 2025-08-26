#!/usr/bin/env bash
#
# Node Exporter 安装脚本 - macOS 平台
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
    if command_exists node_exporter; then
        local current_version
        current_version=$(node_exporter --version 2>&1 | grep -o 'version [0-9.]*' | cut -d' ' -f2 2>/dev/null || echo "未知版本")
        print_warning "检测到已安装 node_exporter v$current_version"
        
        if confirm "是否继续并覆盖安装最新版本？" "n"; then
            print_info "正在停止现有服务..."
            # 停止 launchd 服务
            if sudo launchctl list | grep -q "com.prometheus.node_exporter"; then
                sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist &>/dev/null || true
            fi
            # 停止 Homebrew 服务
            if command_exists brew && brew services list | grep -q "node_exporter"; then
                brew services stop node_exporter &>/dev/null || true
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
    local latest
    latest=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')
    
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
        x86_64) echo "darwin-amd64";;
        arm64) echo "darwin-arm64";;
        *) print_error "不支持的 macOS 架构：$arch"; return 1;;
    esac
}

# 下载和安装
download_and_install() {
    local version="$1"
    local arch_suffix="$2"
    
    print_info "正在下载 Node Exporter v$version..."
    
    local tmpdir=$(mktemp -d)
    setup_cleanup "$tmpdir"
    
    local url="https://github.com/prometheus/node_exporter/releases/download/v${version}/node_exporter-${version}.${arch_suffix}.tar.gz"
    
    if ! safe_download "$url" "$tmpdir/node_exporter.tar.gz"; then
        return 1
    fi
    
    print_info "正在解压..."
    if ! tar -xzf "$tmpdir/node_exporter.tar.gz" -C "$tmpdir"; then
        print_error "解压失败"
        return 1
    fi
    
    print_info "正在安装二进制文件..."
    if sudo mv "$tmpdir/node_exporter-${version}.${arch_suffix}/node_exporter" /usr/local/bin/; then
        sudo chmod 755 /usr/local/bin/node_exporter
        sudo chown root:wheel /usr/local/bin/node_exporter
        print_success "二进制文件安装完成"
    else
        print_error "二进制文件安装失败"
        return 1
    fi
    
    return 0
}

# 创建 launchd 服务
create_launchd_service() {
    print_info "正在创建 launchd 服务..."
    
    local plist_file="/Library/LaunchDaemons/com.prometheus.node_exporter.plist"
    local log_dir="/var/log"
    
    # 确保日志目录存在
    ensure_dir "$log_dir"
    
    sudo tee "$plist_file" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.prometheus.node_exporter</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node_exporter</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/node_exporter.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/node_exporter.err</string>
    <key>UserName</key>
    <string>nobody</string>
    <key>GroupName</key>
    <string>nobody</string>
</dict>
</plist>
EOF

    if [[ $? -eq 0 ]]; then
        print_success "launchd 服务文件创建成功"
    else
        print_error "launchd 服务文件创建失败"
        return 1
    fi
    
    # 加载并启动服务
    print_info "正在启用和启动服务..."
    if sudo launchctl load "$plist_file"; then
        print_success "Node Exporter 服务启动成功"
    else
        print_error "Node Exporter 服务启动失败"
        return 1
    fi
    
    return 0
}

# 验证安装
verify_installation() {
    print_info "正在验证安装..."
    
    # 检查服务状态
    if sudo launchctl list | grep -q "com.prometheus.node_exporter"; then
        print_success "Node Exporter 服务运行正常"
    else
        print_error "Node Exporter 服务未运行"
        return 1
    fi
    
    # 检查端口
    sleep 3
    if check_port 9100; then
        print_success "Node Exporter 监听端口 9100"
    else
        print_warning "端口 9100 未检测到监听，服务可能正在启动中"
    fi
    
    # 显示版本信息
    local version
    version=$(node_exporter --version 2>&1 | head -1)
    print_success "安装的版本：$version"
    
    return 0
}

# 主安装函数
install_node_exporter() {
    print_header "🚀 安装 Node Exporter - macOS 平台"
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
    print_info "即将安装 Node Exporter v$version"
    print_info "安装位置：/usr/local/bin/node_exporter"
    print_info "服务端口：9100"
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
    
    if ! verify_installation; then
        return 1
    fi
    
    echo
    print_success "🎉 Node Exporter 安装完成！"
    echo "========================================"
    print_info "访问地址：http://localhost:9100"
    print_info "服务管理："
    echo "  启动：sudo launchctl load /Library/LaunchDaemons/com.prometheus.node_exporter.plist"
    echo "  停止：sudo launchctl unload /Library/LaunchDaemons/com.prometheus.node_exporter.plist"
    echo "  状态：sudo launchctl list | grep node_exporter"
    echo "  日志：tail -f /var/log/node_exporter.log"
    echo "  错误：tail -f /var/log/node_exporter.err"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_node_exporter
fi
