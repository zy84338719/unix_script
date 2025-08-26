#!/usr/bin/env bash
#
# DDNS-GO 安装脚本 - Linux 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 检查依赖
check_dependencies() {
    local deps=("curl" "tar" "systemctl")
    
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
            sudo systemctl stop ddns-go &>/dev/null || true
            sudo systemctl disable ddns-go &>/dev/null || true
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
        x86_64) echo "linux_x86_64";;
        aarch64|arm64) echo "linux_arm64";;
        armv7l) echo "linux_armv7";;
        armv6l) echo "linux_armv6";;
        *) print_error "不支持的 Linux 架构：$arch"; return 1;;
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
        sudo chown root:root /opt/ddns-go/ddns-go
        print_success "DDNS-GO 安装完成"
    else
        print_error "二进制文件安装失败"
        return 1
    fi
    
    return 0
}

# 创建系统用户
create_user() {
    print_info "正在创建系统用户..."
    if ! id -u ddns-go &>/dev/null; then
        if sudo useradd --system --no-create-home --shell /bin/false ddns-go; then
            print_success "用户 ddns-go 创建成功"
        else
            print_error "用户创建失败"
            return 1
        fi
    else
        print_info "用户 ddns-go 已存在"
    fi
    
    # 设置目录权限
    sudo chown -R ddns-go:ddns-go /opt/ddns-go
    return 0
}

# 创建systemd服务
create_systemd_service() {
    print_info "正在创建 systemd 服务..."
    
    local service_file="/etc/systemd/system/ddns-go.service"
    
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=DDNS-GO Dynamic DNS Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ddns-go
Group=ddns-go
ExecStart=/opt/ddns-go/ddns-go -l :9876
WorkingDirectory=/opt/ddns-go
Restart=always
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    if [[ $? -eq 0 ]]; then
        print_success "systemd 服务文件创建成功"
    else
        print_error "systemd 服务文件创建失败"
        return 1
    fi
    
    # 重载systemd并启用服务
    print_info "正在启用和启动服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable ddns-go
    
    if sudo systemctl start ddns-go; then
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
    
    # 检查 ufw
    if command_exists ufw && sudo ufw status | grep -q "Status: active"; then
        print_info "检测到 UFW 防火墙，正在开放端口 9876..."
        if sudo ufw allow 9876/tcp; then
            print_success "UFW 防火墙规则添加成功"
        else
            print_warning "UFW 防火墙规则添加失败，请手动配置"
        fi
    # 检查 firewalld
    elif command_exists firewall-cmd && sudo firewall-cmd --state &>/dev/null; then
        print_info "检测到 firewalld 防火墙，正在开放端口 9876..."
        if sudo firewall-cmd --permanent --add-port=9876/tcp && sudo firewall-cmd --reload; then
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
    
    # 检查服务状态
    if sudo systemctl is-active --quiet ddns-go; then
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
    print_header "🚀 安装 DDNS-GO - Linux 平台"
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
    
    if ! create_user; then
        return 1
    fi
    
    if ! create_systemd_service; then
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
    echo "  启动：sudo systemctl start ddns-go"
    echo "  停止：sudo systemctl stop ddns-go"
    echo "  重启：sudo systemctl restart ddns-go"
    echo "  状态：sudo systemctl status ddns-go"
    echo "  日志：sudo journalctl -u ddns-go -f"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_ddns_go
fi
