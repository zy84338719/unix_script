#!/usr/bin/env bash
set -euo pipefail

# 引入公共函数库（颜色码与打印函数统一：info/success/warn/error/header）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

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
    info "$(_t 'Detecting system information...')"
    
    case "$(uname -s)" in
        Darwin*)
            OS_TYPE="darwin"
            info "$(_t 'macOS detected')"
            ;;
        Linux*)
            OS_TYPE="linux"
            info "$(_t 'Linux detected')"
            ;;
        *)
            error "$(_tf 'Unsupported operating system: %s' "$(uname -s)")"
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
            error "$(_tf 'Unsupported architecture: %s (uname -m)' "$(uname -m)")"
            exit 1
            ;;
    esac
    
    success "$(_tf 'System: %s-%s' "$OS_TYPE" "$ARCH")"
}

# 解析参数（支持 --yes 和 --driver）
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                # NON_INTERACTIVE 供本脚本生成的 start-minikube.sh 在运行时读取（SC2034 误报）
                # shellcheck disable=SC2034
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
    info "$(_t 'Checking dependencies...')"
    
    local missing_deps=()
    
    # 检查基本工具
    for cmd in curl wget; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "$(_tf 'Missing dependencies: %s' "${missing_deps[*]}")"
        info "$(_t 'Please install these tools first')"
        
        if [[ "$OS_TYPE" == "darwin" ]]; then
            info "$(_t 'On macOS you can install them with Homebrew:')"
            info "brew install ${missing_deps[*]}"
        elif [[ "$OS_TYPE" == "linux" ]]; then
            info "$(_t 'On Linux you can install them with the package manager:')"
            info "sudo apt update && sudo apt install -y ${missing_deps[*]}"
            info "$(_tf 'Or: sudo yum install -y %s' "${missing_deps[*]}")"
        fi
        exit 1
    fi
    
    success "$(_t 'All dependencies are installed')"
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
    info "$(_t 'Fetching the latest version information...')"
    
    # 获取 kubectl 最新版本
    if command -v curl >/dev/null 2>&1; then
        KUBECTL_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    else
        KUBECTL_VERSION=$(wget -qO- https://storage.googleapis.com/kubernetes-release/release/stable.txt)
    fi
    
    if [[ -z "$KUBECTL_VERSION" ]]; then
        warn "$(_t 'Cannot get the latest kubectl version, using the default v1.28.0')"
        KUBECTL_VERSION="v1.28.0"
    fi
    
    # 获取 minikube 最新版本（复用 common.sh 的 http_github_latest_tag：jq 优先 + grep 回退 + 认证）
    MINIKUBE_VERSION="v$(http_github_latest_tag "kubernetes/minikube")"

    if [[ -z "$MINIKUBE_VERSION" || "$MINIKUBE_VERSION" == "v" ]]; then
        warn "$(_t 'Cannot get the latest minikube version, using the default v1.32.0')"
        MINIKUBE_VERSION="v1.32.0"
    fi
    
    success "kubectl $(_tf 'kubectl version: %s' "$KUBECTL_VERSION")"
    success "minikube $(_tf 'minikube version: %s' "$MINIKUBE_VERSION")"
}

# 创建安装目录
create_install_dir() {
    info "$(_t 'Creating the install directory...')"
    
    mkdir -p "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/config"
    
    success "$(_tf 'Install directory created: %s' "$INSTALL_DIR")"
}

# 安装 kubectl
install_kubectl() {
    header "$(_t 'Installing kubectl')"
    
    local kubectl_url="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$OS_TYPE/$ARCH/kubectl"
    local kubectl_path="$INSTALL_DIR/bin/kubectl"
    
    info "$(_tf 'Downloading kubectl %s...' "$KUBECTL_VERSION")"
    
    if command -v curl >/dev/null 2>&1; then
        curl -L "$kubectl_url" -o "$kubectl_path"
    else
        wget -O "$kubectl_path" "$kubectl_url"
    fi
    
    chmod +x "$kubectl_path"
    
    # 验证安装
    if "$kubectl_path" version --client >/dev/null 2>&1; then
        success "kubectl $(_t 'Installed successfully')"
    else
        error "kubectl $(_t 'Installation failed')"
        exit 1
    fi
}

# 安装 minikube
install_minikube() {
    header "$(_t 'Installing minikube')"
    local minikube_url="https://github.com/kubernetes/minikube/releases/download/$MINIKUBE_VERSION/minikube-$OS_TYPE-$ARCH"
    local minikube_path="$INSTALL_DIR/bin/minikube"

    info "$(_tf 'Downloading minikube %s...' "$MINIKUBE_VERSION")"

    if command -v curl >/dev/null 2>&1; then
        curl -L "$minikube_url" -o "$minikube_path"
    else
        wget -O "$minikube_path" "$minikube_url"
    fi

    chmod +x "$minikube_path"

    # 验证安装
    if "$minikube_path" version >/dev/null 2>&1; then
        success "minikube $(_t 'Installed successfully')"
    else
        error "minikube $(_t 'Installation failed')"
        exit 1
    fi

    # 如果指定或检测到驱动，建议用户在启动时使用该驱动
    local detected_driver
    detected_driver=$(detect_driver)
    info "$(_tf 'Suggested driver: %s (override it with the --driver option)' "$detected_driver")"
}

# 配置环境变量
setup_environment() {
    header "$(_t 'Configuring environment variables')"
    
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
        info "$(_tf 'Adding %s/bin to PATH...' "$INSTALL_DIR")"
        
        {
            echo ""
            echo "# minikube $(_t 'and the kubectl path')"
            echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\""
        } >> "$shell_rc"
        
        success "$(_tf 'Environment variables added to %s' "$shell_rc")"
        warn "$(_tf 'Run source %s or reopen the terminal to apply' "$shell_rc")"
    else
        info "PATH $(_t 'already contains the minikube install directory')"
    fi
}

# 创建启动脚本
create_start_script() {
    header "$(_t 'Creating the start script')"
    
    # 生成到用户目录的脚本运行时没有 unix_script 的 _t
    # ⇒ 译文在安装时用 uxs_i18n_localize_file 烘进去（与 safe-rm / pm 脚本同一口径）
    local _tmp="$INSTALL_DIR/.start-minikube.sh.tmp"
    cat > "$_tmp" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

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
    print_info "$(_t 'minikube is already running')"
    minikube status
    exit 0
fi

print_info "$(_t 'Starting minikube...')"

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
    print_success "$(_t 'minikube started successfully!')"
    print_info "$(_t 'Cluster status:')"
    minikube status

    print_info "$(_t 'Available commands:')"
    echo "  minikube dashboard  # $(_t 'Open the Kubernetes dashboard')"
    echo "  minikube stop       # $(_t 'Stop the cluster')"
    echo "  minikube delete     # $(_t 'Delete the cluster')"
    echo "  kubectl get nodes   # $(_t 'List the nodes')"
else
    print_error "$(_t 'Failed to start minikube')"
    exit 1
fi
EOF
    uxs_i18n_localize_file "$_tmp" "$INSTALL_DIR/start-minikube.sh"
    rm -f "$_tmp"
    chmod +x "$INSTALL_DIR/start-minikube.sh"
    print_success "$(_tf 'Start script created: %s/start-minikube.sh' "$INSTALL_DIR")"
}

# 创建状态检查脚本
create_status_script() {
    print_header "$(_t 'Creating the status check script')"
    
    # 生成到用户目录的脚本运行时没有 unix_script 的 _t
    # ⇒ 译文在安装时用 uxs_i18n_localize_file 烘进去（与 safe-rm / pm 脚本同一口径）
    local _tmp="$INSTALL_DIR/.check-status.sh.tmp"
    cat > "$_tmp" << 'EOF'
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

echo "=== Kubernetes $(_t 'development environment status') ==="

# 检查 kubectl
echo
print_info "$(_t 'Checking kubectl...')"
if command -v kubectl >/dev/null 2>&1; then
    kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3)
    print_success "kubectl: $kubectl_version"
else
    print_error "kubectl $(_t 'Not installed')"
fi

# 检查 minikube
echo
print_info "$(_t 'Checking minikube...')"
if command -v minikube >/dev/null 2>&1; then
    minikube_version=$(minikube version --short)
    print_success "minikube: $minikube_version"

    # 检查 minikube 状态
    echo
    print_info "$(_t 'Cluster status:')"
    if minikube status 2>/dev/null; then
        echo
        print_info "$(_t 'Cluster nodes:')"
        kubectl get nodes 2>/dev/null || print_warning "$(_t 'Cannot connect to the cluster')"
    else
        print_warning "$(_t 'The cluster is not running')"
        print_info "$(_t 'Use minikube start to launch the cluster')"
    fi
else
    print_error "minikube $(_t 'Not installed')"
fi

# 检查 Docker
echo
print_info "$(_t 'Checking Docker...')"
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
        print_success "Docker: $docker_version $(_t '(running)')"
    else
        print_warning "$(_t 'Installed but not running')"
    fi
else
    print_warning "$(_t 'Not installed (minikube may need another driver)')"
fi

echo
EOF
    uxs_i18n_localize_file "$_tmp" "$INSTALL_DIR/check-status.sh"
    rm -f "$_tmp"
    chmod +x "$INSTALL_DIR/check-status.sh"
    print_success "$(_tf 'Status check script created: %s/check-status.sh' "$INSTALL_DIR")"
}

# 创建卸载脚本
create_uninstall_script() {
    print_header "$(_t 'Creating the uninstall script')"
    
    cat > "$INSTALL_DIR/uninstall.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} \$1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} \$1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} \$1"; }
print_error() { echo -e "${RED}[ERROR]${NC} \$1"; }

echo "=== minikube $(_t 'uninstall tool') ==="
echo

print_warning "$(_t 'This will completely remove the minikube and kubectl installation')"
read -p "$(_t 'Are you sure you want to continue? (y/N):') " -n 1 -r
echo
if [[ ! \$REPLY =~ ^[Yy]\$ ]]; then
    print_info "$(_t 'Uninstall cancelled')"
    exit 0
fi

# 停止并删除 minikube 集群
if command -v minikube >/dev/null 2>&1; then
    print_info "$(_t 'Stopping and deleting the minikube cluster...')"
    minikube stop 2>/dev/null || true
    minikube delete 2>/dev/null || true
    print_success "minikube $(_t 'cluster deleted')"
fi

# 删除安装目录
if [[ -d "\$INSTALL_DIR" ]]; then
    print_info "$(_t 'Deleting the install directory...')"
    rm -rf "\$INSTALL_DIR"
    print_success "$(_t 'Install directory deleted')"
fi

# 提示用户手动删除 PATH 配置
echo
print_warning "$(_t 'Please remove the PATH configuration from the following files manually:')"
echo "  ~/.zshrc"
echo "  ~/.bashrc" 
echo "  ~/.profile"
echo
print_warning "$(_t 'Remove this line:')"
echo "  export PATH=\"\$INSTALL_DIR/bin:\\\$PATH\""
echo

print_success "minikube $(_t 'uninstall complete')"
EOF
    
    chmod +x "$INSTALL_DIR/uninstall.sh"
    print_success "$(_tf 'Uninstall script created: %s/uninstall.sh' "$INSTALL_DIR")"
}

# 验证安装
verify_installation() {
    print_header "$(_t 'Verifying the installation')"
    
    local kubectl_path="$INSTALL_DIR/bin/kubectl"
    local minikube_path="$INSTALL_DIR/bin/minikube"
    
    # 验证 kubectl
    if [[ -x "$kubectl_path" ]]; then
        kubectl_version=$("$kubectl_path" version --client --short 2>/dev/null | cut -d' ' -f3)
        print_success "kubectl: $kubectl_version"
    else
        print_error "kubectl $(_t 'Verification failed')"
        return 1
    fi
    
    # 验证 minikube
    if [[ -x "$minikube_path" ]]; then
        minikube_version=$("$minikube_path" version --short 2>/dev/null)
        print_success "minikube: $minikube_version"
    else
        print_error "minikube $(_t 'Verification failed')"
        return 1
    fi
    
    print_success "$(_t 'All components verified')"
}

# 显示使用说明
show_usage() {
    print_header "$(_t 'Installation complete')"
    
    echo
    print_success "minikube $(_tf 'and kubectl have been installed to: %s' "$INSTALL_DIR")"
    echo
    print_info "$(_t 'What to do next:')"
    echo "1. $(_t 'Reload the environment variables:')"
    
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
    echo "2. $(_t 'Start minikube:')"
    echo "   $INSTALL_DIR/start-minikube.sh"
    echo "   $(_t 'Or: minikube start')"
    echo
    echo "3. $(_t 'Check the status:')"
    echo "   $INSTALL_DIR/check-status.sh"
    echo
    echo "4. $(_t 'Common commands:')"
    echo "   minikube status       # $(_t 'Check the cluster status')"
    echo "   minikube dashboard    # $(_t 'Open the dashboard')"
    echo "   kubectl get nodes     # $(_t 'List the nodes')"
    echo "   kubectl get pods      # $(_t 'List the pods')"
    echo
    echo "5. $(_t 'Uninstall (if needed):')"
    echo "   $INSTALL_DIR/uninstall.sh"
    echo
}

# 执行完整安装流程
do_install() {
    print_header "minikube $(_t 'install tool')"
    printf '%s\n' "$(_t 'This tool installs a Kubernetes development environment for you')"
    echo

    check_system
    parse_args "$@"
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

    print_success "$(_t 'Installation complete!')"
}

# 查询安装/运行状态（供主菜单“查看状态”调用）
do_status() {
    local install_dir="$HOME/.tools/minikube"
    if [[ -x "$install_dir/bin/minikube" ]] && [[ -x "$install_dir/bin/kubectl" ]]; then
        if echo "$PATH" | grep -q "$install_dir/bin"; then
            uxs_emit_status "installed" "${GREEN}✅ $(_t 'Installed and configured')${NC}"
        else
            uxs_emit_status "installed" "${YELLOW}⚠️  $(_t 'Installed but PATH is not configured')${NC}"
            uxs_emit_extra "path=unconfigured"
        fi
        local mk_ver
        # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE(141)；grep 无匹配时退出 1。
        # 两者在 pipefail 下都会让整条管道非 0，set -e 会让 status 子命令整体中止
        # （违反「状态子命令恒 0」契约）。改用 sed 取首行（sed 读完整个输入才退出），
        # 取不到版本号就回落成空值。
        mk_ver=$("$install_dir/bin/minikube" version --short 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | sed -n '1p') || mk_ver=""
        # 收尾用 if 而不是 `[[ -n "$mk_ver" ]] && ...`：后者在版本号为空时返回 1，
        # 会让 status 子命令整体退出 1（同样是「status 恒 0」契约）。
        if [[ -n "$mk_ver" ]]; then
            uxs_emit_version "$mk_ver"
        fi
    else
        uxs_emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"
    fi
    return 0
}

# 卸载（委托给安装时生成的卸载脚本）
do_uninstall() {
    local uninstall_script="$HOME/.tools/minikube/uninstall.sh"
    if [[ -x "$uninstall_script" ]]; then
        "$uninstall_script"
    else
        warn "$(_tf 'Uninstall script not found (%s), it may not be installed yet.' "${uninstall_script}")"
        if [[ -d "$HOME/.tools/minikube" ]]; then
            rm -rf "$HOME/.tools/minikube" && success "$(_tf 'Removed %s/.tools/minikube' "$HOME")"
        fi
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help} [--yes] [--driver <驱动>]

  install     $(_t 'Install minikube + kubectl (default action)')
  uninstall   $(_t 'Uninstall minikube')
  status      $(_t 'Show the installation and running status')
  help        $(_t 'Show this help')

$(_t 'Options (install only):')
  --yes, -y             $(_t 'Non-interactive mode')
  --driver <$(_t 'Driver>       minikube driver (docker/hyperkit/kvm2, default auto)')
EOF
}

# 主函数：子命令分发
main() {
    local action="${1:-install}"
    # 兼容旧调用：第一个参数若为选项（--yes/--driver），视为 install 的参数
    if [[ "$action" == --* || "$action" == -* ]]; then
        do_install "$@"
        return
    fi
    case "$action" in
        install)   shift; do_install "$@" ;;
        uninstall) do_uninstall ;;
        status)    do_status ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

# 运行主函数
main "$@"
