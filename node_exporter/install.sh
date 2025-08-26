#!/usr/bin/env bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 全局变量
OS_TYPE=""

# 检查操作系统
check_os() {
    os_name=$(uname -s)
    if [[ "$os_name" == "Darwin" ]]; then
        OS_TYPE="darwin"
        print_info "检测到操作系统：macOS"
    elif [[ "$os_name" == "Linux" ]]; then
        OS_TYPE="linux"
        print_info "检测到操作系统：Linux"
    else
        print_error "不支持的操作系统：$os_name"
        exit 1
    fi
}

# 检查权限
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        print_error "请不要使用 root 用户运行此脚本"
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        print_info "此脚本需要 sudo 权限，请输入密码："
        sudo -v || { print_error "无法获取 sudo 权限"; exit 1; }
    fi
}

# 检查必要命令
check_dependencies() {
    local deps=("curl" "tar")
    # Linux 系统需要 systemctl
    if [[ "$OS_TYPE" == "linux" ]]; then
        deps+=("systemctl")
    fi
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "缺少必要命令：$dep"
            exit 1
        fi
    done
}

# 检查是否已安装
check_existing_installation() {
    if command -v node_exporter &> /dev/null; then
        local current_version
        current_version=$(node_exporter --version 2>&1 | grep -o 'version [0-9.]*' | cut -d' ' -f2 2>/dev/null || echo "未知版本")
        print_warning "检测到已安装 node_exporter v$current_version"
        read -r -p "是否继续并覆盖安装最新版本？[y/N]: " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "安装已取消"
            exit 0
        fi
        
        print_info "正在停止现有服务..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo systemctl stop node_exporter &>/dev/null || true
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            # 检查是否有通过 launchctl 管理的服务
            if sudo launchctl list | grep -q "node_exporter"; then
                sudo launchctl bootout system /Library/LaunchDaemons/node_exporter.plist &>/dev/null || true
            fi
            # 检查是否有通过 Homebrew 安装的服务
            if command -v brew &> /dev/null && brew services list | grep -q "node_exporter"; then
                brew services stop node_exporter &>/dev/null || true
            fi
        fi
    fi
}

print_info "🚀 Node Exporter 跨平台安装脚本"
echo "=========================================="

# 执行检查
check_os
check_permissions
check_dependencies
check_existing_installation

# 获取最新版本号
print_info "正在获取最新版本信息..."
latest=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')

if [[ -z "$latest" ]]; then
    print_error "无法获取最新版本信息，请检查网络连接"
    exit 1
fi

print_success "最新版本：v$latest"

# 确定架构和下载地址
arch=$(uname -m)
arch_suffix=""
case "$OS_TYPE" in
  "linux")
    case "$arch" in
      x86_64) arch_suffix=linux-amd64;;
      aarch64|arm64) arch_suffix=linux-arm64;;
      armv7l) arch_suffix=linux-armv7;;
      *) print_error "不支持的 Linux 架构：$arch"; exit 1;;
    esac
    ;;
  "darwin")
    case "$arch" in
      x86_64) arch_suffix=darwin-amd64;;
      arm64) arch_suffix=darwin-arm64;;
      *) print_error "不支持的 macOS 架构：$arch"; exit 1;;
    esac
    ;;
esac

print_info "检测到架构：$arch -> $arch_suffix"

# 确认安装
echo
print_info "即将安装 Node Exporter v$latest"
if [[ "$OS_TYPE" == "linux" ]]; then
    print_info "安装位置：/usr/local/bin/node_exporter"
elif [[ "$OS_TYPE" == "darwin" ]]; then
    print_info "安装位置：/usr/local/bin/node_exporter"
fi
print_info "服务端口：9100"
echo
read -r -p "确认继续安装？[y/N]: " -n 1
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "安装已取消"
    exit 0
fi

# 下载并解压
print_info "正在下载和解压..."
tmpdir=$(mktemp -d)

url="https://github.com/prometheus/node_exporter/releases/download/v${latest}/node_exporter-${latest}.${arch_suffix}.tar.gz"
print_info "下载地址：$url"

if ! curl -SL "$url" -o "$tmpdir/node_exporter.tar.gz"; then
    print_error "下载失败"
    rm -rf "$tmpdir"
    exit 1
fi

if ! tar -xzf "$tmpdir/node_exporter.tar.gz" -C "$tmpdir"; then
    print_error "解压失败"
    rm -rf "$tmpdir"
    exit 1
fi

print_success "下载和解压完成"

# 安装 node_exporter 二进制
print_info "正在安装二进制文件..."
if sudo mv "$tmpdir/node_exporter-${latest}.${arch_suffix}/node_exporter" /usr/local/bin/; then
    sudo chmod 755 /usr/local/bin/node_exporter
    # 根据操作系统设置正确的文件所有权
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel /usr/local/bin/node_exporter
    elif [[ "$OS_TYPE" == "linux" ]]; then
        sudo chown root:root /usr/local/bin/node_exporter
    fi
    print_success "二进制文件安装完成"
else
    print_error "二进制文件安装失败"
    rm -rf "$tmpdir"
    exit 1
fi

# 根据操作系统创建服务
if [[ "$OS_TYPE" == "linux" ]]; then
    # Linux 系统：创建 node_exporter 用户和 systemd 服务
    print_info "正在创建系统用户..."
    if ! id -u node_exporter &>/dev/null; then
        if sudo useradd --no-create-home --shell /bin/false node_exporter; then
            print_success "用户 node_exporter 创建成功"
        else
            print_error "用户创建失败"
            rm -rf "$tmpdir"
            exit 1
        fi
    else
        print_info "用户 node_exporter 已存在"
    fi

    # 创建 systemd 服务
    print_info "正在创建 systemd 服务..."
    if sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<EOF; then
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=":9100"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        print_success "systemd 服务文件创建成功"
    else
        print_error "systemd 服务文件创建失败"
        rm -rf "$tmpdir"
        exit 1
    fi

    # 重载 systemd 并启动服务
    print_info "正在启动服务..."
    if sudo systemctl daemon-reload; then
        print_success "systemd 配置已重载"
    else
        print_error "systemd 重载失败"
        rm -rf "$tmpdir"
        exit 1
    fi

    if sudo systemctl enable --now node_exporter; then
        print_success "node_exporter 服务已启动并设置为开机自启"
    else
        print_error "服务启动失败"
        rm -rf "$tmpdir"
        exit 1
    fi

elif [[ "$OS_TYPE" == "darwin" ]]; then
    # macOS 系统：创建 launchd 服务
    print_info "正在创建 macOS 服务..."
    if sudo tee /Library/LaunchDaemons/com.prometheus.node_exporter.plist >/dev/null <<EOF; then
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.prometheus.node_exporter</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node_exporter</string>
        <string>--web.listen-address=:9100</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/node_exporter.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/node_exporter.log</string>
</dict>
</plist>
EOF
        print_success "LaunchDaemon 服务文件创建成功"
    else
        print_error "LaunchDaemon 服务文件创建失败"
        rm -rf "$tmpdir"
        exit 1
    fi

    # 启动服务
    print_info "正在启动服务..."
    # 先检查服务是否已经在运行
    if sudo launchctl list | grep -q "com.prometheus.node_exporter"; then
        print_info "服务已在运行中"
        print_success "node_exporter 服务已启动并设置为开机自启"
    else
        # 尝试 bootstrap 启动服务
        if sudo launchctl bootstrap system /Library/LaunchDaemons/com.prometheus.node_exporter.plist; then
            print_success "node_exporter 服务已启动并设置为开机自启"
        else
            print_warning "bootstrap 命令失败，尝试使用 load 命令作为备选方案"
            if sudo launchctl load /Library/LaunchDaemons/com.prometheus.node_exporter.plist 2>/dev/null; then
                print_success "node_exporter 服务已启动（使用 load 命令）"
            else
                print_warning "自动启动失败，但服务文件已安装"
                print_info "您可以手动启动服务：sudo launchctl bootstrap system /Library/LaunchDaemons/com.prometheus.node_exporter.plist"
                print_info "或者重启系统后服务将自动启动"
            fi
        fi
    fi
fi

# 验证安装
print_info "正在验证安装..."
sleep 3
service_active=false

if [[ "$OS_TYPE" == "linux" ]]; then
    if systemctl is-active --quiet node_exporter; then
        service_active=true
    fi
elif [[ "$OS_TYPE" == "darwin" ]]; then
    if sudo launchctl list | grep -q "com.prometheus.node_exporter"; then
        service_active=true
    fi
fi

if $service_active; then
    print_success "服务运行正常"
    
    # 测试端口连接
    sleep 2
    if curl -s http://localhost:9100/metrics > /dev/null; then
        print_success "端口 9100 响应正常"
    else
        print_warning "端口 9100 暂时无响应，可能需要等待几秒钟"
    fi
else
    print_error "服务未正常运行"
    print_info "可以使用以下命令查看状态和日志："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status node_exporter"
        echo "  sudo journalctl -u node_exporter -f"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  sudo launchctl list | grep node_exporter"
        echo "  tail -f /var/log/node_exporter.log"
        echo "  tail -f /var/log/node_exporter.err"
    fi
fi

# 获取IP地址
ip_addr=""
if [[ "$OS_TYPE" == "linux" ]]; then
    ip_addr=$(hostname -I | awk '{print $1}')
elif [[ "$OS_TYPE" == "darwin" ]]; then
    # 尝试 en0 (以太网/Wi-Fi), en1, ...
    for iface in en0 en1 en2; do
        ip_addr=$(ipconfig getifaddr $iface 2>/dev/null)
        if [ -n "$ip_addr" ]; then
            break
        fi
    done
fi
# 如果找不到，则回退到 localhost
if [ -z "$ip_addr" ]; then
    ip_addr="127.0.0.1"
    print_warning "无法自动检测 IP 地址，请使用 http://127.0.0.1:9100 访问"
fi

# 清理临时文件
rm -rf "$tmpdir"

echo
echo "========================================"
print_success "🎉 Node Exporter v$latest 安装完成！"
echo
print_info "服务信息："
echo "  - 监听地址：http://0.0.0.0:9100"
echo "  - 指标地址：http://${ip_addr}:9100/metrics"
echo "  - 状态页面：http://${ip_addr}:9100"
echo
print_info "常用命令："
if [[ "$OS_TYPE" == "linux" ]]; then
    echo "  - 服务状态：sudo systemctl status node_exporter"
    echo "  - 查看日志：sudo journalctl -u node_exporter -f"
    echo "  - 停止服务：sudo systemctl stop node_exporter"
    echo "  - 启动服务：sudo systemctl start node_exporter"
    echo "  - 重启服务：sudo systemctl restart node_exporter"
elif [[ "$OS_TYPE" == "darwin" ]]; then
    echo "  - 服务状态：sudo launchctl list | grep node_exporter"
    echo "  - 查看日志：tail -f /var/log/node_exporter.log"
    echo "  - 查看错误：tail -f /var/log/node_exporter.err"
    echo "  - 停止服务：sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist"
    echo "  - 启动服务：sudo launchctl bootstrap system /Library/LaunchDaemons/com.prometheus.node_exporter.plist"
fi
echo
print_info "您可以访问 http://${ip_addr}:9100 来查看 Node Exporter 状态页面"