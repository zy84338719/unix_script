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
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# 全局变量
OS_TYPE=""
ARCH=""
INSTALL_DIR="$HOME/.tools/minikube"
KUBECTL_VERSION=""
MINIKUBE_VERSION=""
# 非交互标志（--yes）
NON_INTERACTIVE=false
# 推荐驱动（auto-detect）
PREFERRED_DRIVER="auto"

# 检查操作系统和架构
check_system() {
    print_info "检测系统信息..."
    
    case "$(uname -s)" in
        Darwin*)
            OS_TYPE="darwin"
            print_info "检测到 macOS 系统"
            ;;
        Linux*)
            OS_TYPE="linux"
            print_info "检测到 Linux 系统"
            ;;
        *)
            print_error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac
    
    case "$(uname -m)" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            print_error "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac
    
    print_success "系统: $OS_TYPE-$ARCH"
}

# 解析参数（支持 --yes 和 --driver）
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                NON_INTERACTIVE=true
                shift
                ;;
            --driver)
                PREFERRED_DRIVER="$2"
                shift 2
                ;;
            --driver=*)
                PREFERRED_DRIVER="${1#*=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖项..."
    
    local missing_deps=()
    
    # 检查基本工具
    for cmd in curl wget; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺少依赖项: ${missing_deps[*]}"
        print_info "请先安装这些工具"
        
        if [[ "$OS_TYPE" == "darwin" ]]; then
            print_info "在 macOS 上，您可以使用 Homebrew 安装："
            print_info "brew install ${missing_deps[*]}"
        elif [[ "$OS_TYPE" == "linux" ]]; then
            print_info "在 Linux 上，您可以使用包管理器安装："
            print_info "sudo apt update && sudo apt install -y ${missing_deps[*]}"
            print_info "或者: sudo yum install -y ${missing_deps[*]}"
        fi
        exit 1
    fi
    
    print_success "所有依赖项都已安装"
}

# 自动检测可用驱动
detect_driver() {
    # 返回驱动名称或 "docker" 为默认
    if [[ "$PREFERRED_DRIVER" != "auto" ]]; then
        echo "$PREFERRED_DRIVER"
        return
    fi

    if command -v docker >/dev/null 2>&1; then
        echo "docker"
        return
    fi

    # macOS hyperkit
    if [[ "$OS_TYPE" == "darwin" ]] && command -v hyperkit >/dev/null 2>&1; then
        echo "hyperkit"
        return
    fi

    # Linux kvm2
    if [[ "$OS_TYPE" == "linux" ]] && command -v virsh >/dev/null 2>&1; then
        echo "kvm2"
        return
    fi

    # fallback
    echo "docker"
}

# 获取最新版本号
get_latest_versions() {
    print_info "获取最新版本信息..."
    
    # 获取 kubectl 最新版本
    if command -v curl >/dev/null 2>&1; then
        KUBECTL_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    else
        KUBECTL_VERSION=$(wget -qO- https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    fi
    
    if [[ -z "$KUBECTL_VERSION" ]]; then
        print_warning "无法获取 kubectl 最新版本，使用默认版本 v1.28.0"
        KUBECTL_VERSION="v1.28.0"
    fi
    
    # 获取 minikube 最新版本
    if command -v curl >/dev/null 2>&1; then
        MINIKUBE_VERSION=$(curl -s https://api.github.com/repos/kubernetes/minikube/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        MINIKUBE_VERSION=$(wget -qO- https://api.github.com/repos/kubernetes/minikube/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    
    if [[ -z "$MINIKUBE_VERSION" ]]; then
        print_warning "无法获取 minikube 最新版本，使用默认版本 v1.32.0"
        MINIKUBE_VERSION="v1.32.0"
    fi
    
    print_success "kubectl 版本: $KUBECTL_VERSION"
    print_success "minikube 版本: $MINIKUBE_VERSION"
}

# 创建安装目录
create_install_dir() {
    print_info "创建安装目录..."
    
    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/config"
    
    print_success "安装目录已创建: $INSTALL_DIR"
}

# 安装 kubectl
install_kubectl() {
    print_header "安装 kubectl"
    
    local kubectl_url="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$OS_TYPE/$ARCH/kubectl"
    local kubectl_path="$INSTALL_DIR/bin/kubectl"
    
    print_info "下载 kubectl $KUBECTL_VERSION..."
    
    if command -v curl >/dev/null 2>&1; then
        curl -L "$kubectl_url" -o "$kubectl_path"
    else
        wget -O "$kubectl_path" "$kubectl_url"
    fi
    
    chmod +x "$kubectl_path"
    
    # 验证安装
    if "$kubectl_path" version --client >/dev/null 2>&1; then
        print_success "kubectl 安装成功"
    else
        print_error "kubectl 安装失败"
        exit 1
    fi
}

# 安装 minikube
install_minikube() {
    print_header "安装 minikube"
    local minikube_url="https://github.com/kubernetes/minikube/releases/download/$MINIKUBE_VERSION/minikube-$OS_TYPE-$ARCH"
    local minikube_path="$INSTALL_DIR/bin/minikube"

    print_info "下载 minikube $MINIKUBE_VERSION..."

    if command -v curl >/dev/null 2>&1; then
        curl -L "$minikube_url" -o "$minikube_path"
    else
        wget -O "$minikube_path" "$minikube_url"
    fi

    chmod +x "$minikube_path"

    # 验证安装
    if "$minikube_path" version >/dev/null 2>&1; then
        print_success "minikube 安装成功"
    else
        print_error "minikube 安装失败"
        exit 1
    fi

    # 如果指定或检测到驱动，建议用户在启动时使用该驱动
    local detected_driver
    detected_driver=$(detect_driver)
    print_info "建议的驱动: $detected_driver (可使用 --driver 参数覆盖)"
}

# 配置环境变量
setup_environment() {
    print_header "配置环境变量"
    
    local shell_rc=""
    case "$SHELL" in
        */zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        */bash)
            shell_rc="$HOME/.bashrc"
            ;;
        *)
            shell_rc="$HOME/.profile"
            ;;
    esac
    
    # 检查 PATH 是否已经包含安装目录
    if ! echo "$PATH" | grep -q "$INSTALL_DIR/bin"; then
        print_info "添加 $INSTALL_DIR/bin 到 PATH..."
        
        echo "" >> "$shell_rc"
        echo "# minikube 和 kubectl 路径" >> "$shell_rc"
        echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$shell_rc"
        
        print_success "环境变量已添加到 $shell_rc"
        print_warning "请运行 'source $shell_rc' 或重新打开终端以生效"
    else
        print_info "PATH 中已包含 minikube 安装目录"
    fi
}

# 创建启动脚本
create_start_script() {
    print_header "创建启动脚本"
    
    cat > "$INSTALL_DIR/start-minikube.sh" << 'EOF'
#!/usr/bin/env bash
set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 minikube 是否正在运行
if minikube status >/dev/null 2>&1; then
    print_info "minikube 已在运行中"
    minikube status
    exit 0
fi

print_info "启动 minikube..."

# 启动 minikube（使用推荐配置）
DRIVER_ARG="$(detect_driver)"
if [[ "$PREFERRED_DRIVER" != "auto" ]]; then
    DRIVER_ARG="$PREFERRED_DRIVER"
fi

if [[ "$NON_INTERACTIVE" == true ]]; then
    minikube start --cpus=2 --memory=4096 --disk-size=20g --driver="$DRIVER_ARG"
else
    minikube start \
        --cpus=2 \
        --memory=4096 \
        --disk-size=20g \
        --driver="$DRIVER_ARG"
fi

if [ $? -eq 0 ]; then
    print_success "minikube 启动成功！"
    print_info "集群状态："
    minikube status
    
    print_info "可用命令："
    echo "  minikube dashboard  # 打开 Kubernetes 仪表板"
    echo "  minikube stop       # 停止集群"
    echo "  minikube delete     # 删除集群"
    echo "  kubectl get nodes   # 查看节点"
else
    print_error "minikube 启动失败"
    exit 1
fi
EOF
    
    chmod +x "$INSTALL_DIR/start-minikube.sh"
    print_success "启动脚本已创建: $INSTALL_DIR/start-minikube.sh"
}

# 创建状态检查脚本
create_status_script() {
    print_header "创建状态检查脚本"
    
    cat > "$INSTALL_DIR/check-status.sh" << 'EOF'
#!/usr/bin/env bash

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== Kubernetes 开发环境状态 ==="

# 检查 kubectl
echo
print_info "检查 kubectl..."
if command -v kubectl >/dev/null 2>&1; then
    kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3)
    print_success "kubectl: $kubectl_version"
else
    print_error "kubectl 未安装"
fi

# 检查 minikube
echo
print_info "检查 minikube..."
if command -v minikube >/dev/null 2>&1; then
    minikube_version=$(minikube version --short)
    print_success "minikube: $minikube_version"
    
    # 检查 minikube 状态
    echo
    print_info "minikube 集群状态："
    if minikube status 2>/dev/null; then
        echo
        print_info "集群节点："
        kubectl get nodes 2>/dev/null || print_warning "无法连接到集群"
    else
        print_warning "minikube 集群未运行"
        print_info "使用 'minikube start' 启动集群"
    fi
else
    print_error "minikube 未安装"
fi

# 检查 Docker
echo
print_info "检查 Docker..."
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
        print_success "Docker: $docker_version (运行中)"
    else
        print_warning "Docker 已安装但未运行"
    fi
else
    print_warning "Docker 未安装 (minikube 可能需要其他驱动)"
fi

echo
EOF
    
    chmod +x "$INSTALL_DIR/check-status.sh"
    print_success "状态检查脚本已创建: $INSTALL_DIR/check-status.sh"
}

# 创建卸载脚本
create_uninstall_script() {
    print_header "创建卸载脚本"
    
    cat > "$INSTALL_DIR/uninstall.sh" << EOF
#!/usr/bin/env bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "\${BLUE}[INFO]\${NC} \$1"; }
print_success() { echo -e "\${GREEN}[SUCCESS]\${NC} \$1"; }
print_warning() { echo -e "\${YELLOW}[WARNING]\${NC} \$1"; }
print_error() { echo -e "\${RED}[ERROR]\${NC} \$1"; }

echo "=== minikube 卸载工具 ==="
echo

print_warning "这将完全删除 minikube 和 kubectl 安装"
read -p "确定要继续吗？ (y/N): " -n 1 -r
echo
if [[ ! \$REPLY =~ ^[Yy]\$ ]]; then
    print_info "取消卸载"
    exit 0
fi

# 停止并删除 minikube 集群
if command -v minikube >/dev/null 2>&1; then
    print_info "停止并删除 minikube 集群..."
    minikube stop 2>/dev/null || true
    minikube delete 2>/dev/null || true
    print_success "minikube 集群已删除"
fi

# 删除安装目录
if [[ -d "$INSTALL_DIR" ]]; then
    print_info "删除安装目录..."
    rm -rf "$INSTALL_DIR"
    print_success "安装目录已删除"
fi

# 提示用户手动删除 PATH 配置
echo
print_warning "请手动从以下文件中删除 PATH 配置："
echo "  ~/.zshrc"
echo "  ~/.bashrc" 
echo "  ~/.profile"
echo
print_warning "删除这一行："
echo "  export PATH=\"$INSTALL_DIR/bin:\\\$PATH\""
echo

print_success "minikube 卸载完成"
EOF
    
    chmod +x "$INSTALL_DIR/uninstall.sh"
    print_success "卸载脚本已创建: $INSTALL_DIR/uninstall.sh"
}

# 验证安装
verify_installation() {
    print_header "验证安装"
    
    local kubectl_path="$INSTALL_DIR/bin/kubectl"
    local minikube_path="$INSTALL_DIR/bin/minikube"
    
    # 验证 kubectl
    if [[ -x "$kubectl_path" ]]; then
        kubectl_version=$("$kubectl_path" version --client --short 2>/dev/null | cut -d' ' -f3)
        print_success "kubectl: $kubectl_version"
    else
        print_error "kubectl 验证失败"
        return 1
    fi
    
    # 验证 minikube
    if [[ -x "$minikube_path" ]]; then
        minikube_version=$("$minikube_path" version --short 2>/dev/null)
        print_success "minikube: $minikube_version"
    else
        print_error "minikube 验证失败"
        return 1
    fi
    
    print_success "所有组件验证通过"
}

# 显示使用说明
show_usage() {
    print_header "安装完成"
    
    echo
    print_success "minikube 和 kubectl 已成功安装到: $INSTALL_DIR"
    echo
    print_info "接下来的步骤："
    echo "1. 重新加载环境变量："
    
    case "$SHELL" in
        */zsh)
            echo "   source ~/.zshrc"
            ;;
        */bash)
            echo "   source ~/.bashrc"
            ;;
        *)
            echo "   source ~/.profile"
            ;;
    esac
    
    echo
    echo "2. 启动 minikube："
    echo "   $INSTALL_DIR/start-minikube.sh"
    echo "   或者: minikube start"
    echo
    echo "3. 检查状态："
    echo "   $INSTALL_DIR/check-status.sh"
    echo
    echo "4. 常用命令："
    echo "   minikube status       # 查看集群状态"
    echo "   minikube dashboard    # 打开仪表板"
    echo "   kubectl get nodes     # 查看节点"
    echo "   kubectl get pods      # 查看 Pod"
    echo
    echo "5. 卸载 (如需要):"
    echo "   $INSTALL_DIR/uninstall.sh"
    echo
}

# 主函数
main() {
    print_header "minikube 安装工具"
    echo "此工具将为您安装 Kubernetes 开发环境"
    echo
    
    check_system
    check_dependencies
    get_latest_versions
    create_install_dir
    install_kubectl
    install_minikube
    setup_environment
    create_start_script
    create_status_script
    create_uninstall_script
    verify_installation
    show_usage
    
    print_success "安装完成！"
}

# 运行主函数
main "$@"
