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
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "缺少必要命令：$dep"
            exit 1
        fi
    done
}

# 检查是否已安装
check_existing_installation() {
    if [ -f "/opt/ddns-go/ddns-go" ]; then
        local current_version
        current_version=$(/opt/ddns-go/ddns-go --version 2>&1)
        print_warning "检测到已安装 ddns-go $current_version"
        read -r -p "是否继续并覆盖安装最新版本？[y/N]: " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "安装已取消"
            exit 0
        fi
        
        print_info "正在停止并卸载现有服务..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo systemctl stop ddns-go &>/dev/null || true
        fi
        # ddns-go -s uninstall 会自动处理 launchctl unload
        sudo /opt/ddns-go/ddns-go -s uninstall &>/dev/null || true
    fi
}

print_info "🚀 ddns-go 跨平台安装脚本"
echo "=========================================="

# 执行检查
check_os
check_permissions
check_dependencies
check_existing_installation

# 获取最新版本号和下载地址
print_info "正在获取最新版本信息..."
api_url="https://api.github.com/repos/jeessy2/ddns-go/releases/latest"
release_info=$(curl -s "$api_url")

latest_tag=$(echo "$release_info" | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$latest_tag" ]]; then
    print_error "无法获取最新版本信息，请检查网络连接或 API 速率限制"
    exit 1
fi
print_success "最新版本：$latest_tag"

arch=$(uname -m)
arch_suffix=""
case "$OS_TYPE" in
  "linux")
    case "$arch" in
      x86_64) arch_suffix=linux_x86_64;;
      aarch64|arm64) arch_suffix=linux_arm64;;
      armv7l) arch_suffix=linux_armv7;;
      *) print_error "不支持的 Linux 架构：$arch"; exit 1;;
    esac
    ;;
  "darwin")
    case "$arch" in
      x86_64) arch_suffix=darwin_amd64;;
      arm64) arch_suffix=darwin_arm64;;
      *) print_error "不支持的 macOS 架构：$arch"; exit 1;;
    esac
    ;;
esac

download_url=$(echo "$release_info" | grep "browser_download_url" | grep "$arch_suffix.tar.gz" | cut -d '"' -f 4)
if [[ -z "$download_url" ]]; then
    print_error "无法找到适用于 $arch_suffix 的下载链接"
    exit 1
fi

# 确认安装
echo
print_info "即将安装 ddns-go $latest_tag"
print_info "安装位置：/opt/ddns-go"
print_info "服务端口：9876"
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
if ! curl -SL "$download_url" -o "$tmpdir/ddns-go.tar.gz"; then
    print_error "下载失败"
    rm -rf "$tmpdir"
    exit 1
fi

if ! tar -xzf "$tmpdir/ddns-go.tar.gz" -C "$tmpdir"; then
    print_error "解压失败"
    rm -rf "$tmpdir"
    exit 1
fi
print_success "下载和解压完成"

# 安装
print_info "正在安装 ddns-go..."
sudo mkdir -p /opt/ddns-go
sudo mv "$tmpdir/ddns-go" /opt/ddns-go/
sudo mv "$tmpdir/README.md" /opt/ddns-go/
sudo mv "$tmpdir/LICENSE" /opt/ddns-go/
# 根据操作系统设置正确的文件所有权
if [[ "$OS_TYPE" == "darwin" ]]; then
    sudo chown -R root:wheel /opt/ddns-go
elif [[ "$OS_TYPE" == "linux" ]]; then
    sudo chown -R root:root /opt/ddns-go
fi
sudo chmod +x /opt/ddns-go/ddns-go
print_success "文件安装完成"

# 安装服务
print_info "正在安装服务..."
if sudo /opt/ddns-go/ddns-go -s install; then
    print_success "服务安装成功"
else
    print_error "服务安装失败"
    rm -rf "$tmpdir"
    exit 1
fi

# 启动服务
print_info "正在启动服务..."
if [[ "$OS_TYPE" == "linux" ]]; then
    if sudo systemctl enable --now ddns-go; then
        print_success "ddns-go 服务已启动并设置为开机自启"
    else
        print_error "服务启动失败"
        rm -rf "$tmpdir"
        exit 1
    fi
elif [[ "$OS_TYPE" == "darwin" ]]; then
    # 在 macOS 上，先检查服务是否已经在运行
    if sudo launchctl list | grep -q "jeessy.ddns-go"; then
        print_info "服务已在运行中"
        print_success "ddns-go 服务已启动并设置为开机自启"
    else
        # 尝试 bootstrap 启动服务
        if sudo launchctl bootstrap system /Library/LaunchDaemons/jeessy.ddns-go.plist; then
            print_success "ddns-go 服务已启动并设置为开机自启"
        else
            print_warning "bootstrap 命令失败，尝试使用 load 命令作为备选方案"
            if sudo launchctl load /Library/LaunchDaemons/jeessy.ddns-go.plist 2>/dev/null; then
                print_success "ddns-go 服务已启动（使用 load 命令）"
            else
                print_warning "自动启动失败，但服务文件已安装"
                print_info "您可以手动启动服务：sudo launchctl bootstrap system /Library/LaunchDaemons/jeessy.ddns-go.plist"
                print_info "或者重启系统后服务将自动启动"
            fi
        fi
    fi
fi

# 清理临时文件
rm -rf "$tmpdir"

# 验证安装
print_info "正在验证安装..."
sleep 3
service_active=false
if [[ "$OS_TYPE" == "linux" ]]; then
    if systemctl is-active --quiet ddns-go; then
        service_active=true
    fi
elif [[ "$OS_TYPE" == "darwin" ]]; then
    if sudo launchctl list | grep -q "jeessy.ddns-go"; then
        service_active=true
    fi
fi

if $service_active; then
    print_success "服务运行正常"
else
    print_error "服务未正常运行"
    print_info "可以使用以下命令查看日志："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status ddns-go"
        echo "  sudo journalctl -u ddns-go -f"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  sudo launchctl list | grep ddns-go"
        echo "  日志文件通常位于 /var/log/ 或者通过 Console.app 查看"
    fi
fi

# 获取IP地址
ip_addr=""
if [[ "$OS_TYPE" == "linux" ]]; then
    ip_addr=$(hostname -I | awk '{print $1}')
elif [[ "$OS_TYPE" == "darwin" ]]; then
    # 尝试 en0 (以太网/Wi-Fi), en1, ...
    for iface in en0 en1 en2; do
        ip_addr=$(ipconfig getifaddr $iface)
        if [ -n "$ip_addr" ]; then
            break
        fi
    done
fi
# 如果找不到，则回退到 localhost
if [ -z "$ip_addr" ]; then
    ip_addr="127.0.0.1"
    print_warning "无法自动检测 IP 地址，请使用 http://127.0.0.1:9876 访问"
fi


echo
echo "=========================================="
print_success "🎉 ddns-go $latest_tag 安装完成！"
echo
print_info "服务信息："
echo "  - 访问地址：http://${ip_addr}:9876"
echo "  - 安装目录：/opt/ddns-go"
echo "  - 配置文件：/opt/ddns-go/.ddns_go_config.yaml (首次访问后自动创建)"
echo
print_info "常用命令："
if [[ "$OS_TYPE" == "linux" ]]; then
    echo "  - 服务状态：sudo systemctl status ddns-go"
    echo "  - 查看日志：sudo journalctl -u ddns-go -f"
    echo "  - 停止服务：sudo systemctl stop ddns-go"
    echo "  - 启动服务：sudo systemctl start ddns-go"
elif [[ "$OS_TYPE" == "darwin" ]]; then
    echo "  - 服务状态：sudo launchctl list | grep ddns-go"
    echo "  - 停止服务：sudo launchctl bootout system /Library/LaunchDaemons/jeessy.ddns-go.plist"
    echo "  - 启动服务：sudo launchctl bootstrap system /Library/LaunchDaemons/jeessy.ddns-go.plist"
fi
echo
print_warning "请务必在 Web 界面中设置您的 DNS 服务商信息和要更新的域名！"
