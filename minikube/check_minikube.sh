#!/usr/bin/env bash

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# 检查 minikube 安装状态
check_minikube_installation() {
    print_header "minikube 安装检查"
    
    local install_dir="$HOME/.tools/minikube"
    local kubectl_path="$install_dir/bin/kubectl"
    local minikube_path="$install_dir/bin/minikube"
    
    # 检查安装目录
    if [[ -d "$install_dir" ]]; then
        print_success "安装目录存在: $install_dir"
    else
        print_error "安装目录不存在: $install_dir"
        return 1
    fi
    
    # 检查 kubectl
    if [[ -x "$kubectl_path" ]]; then
        kubectl_version=$("$kubectl_path" version --client --short 2>/dev/null | cut -d' ' -f3 || echo "未知")
        print_success "kubectl 已安装: $kubectl_version"
    else
        print_error "kubectl 未安装或不可执行"
    fi
    
    # 检查 minikube
    if [[ -x "$minikube_path" ]]; then
        minikube_version=$("$minikube_path" version --short 2>/dev/null || echo "未知")
        print_success "minikube 已安装: $minikube_version"
    else
        print_error "minikube 未安装或不可执行"
    fi
    
    # 检查环境变量
    if echo "$PATH" | grep -q "$install_dir/bin"; then
        print_success "PATH 配置正确"
    else
        print_warning "PATH 中未包含 minikube 目录"
        print_info "请添加以下行到您的 shell 配置文件："
        print_info "export PATH=\"$install_dir/bin:\$PATH\""
    fi
    
    # 检查系统 kubectl/minikube
    echo
    print_info "系统命令检查："
    
    if command -v kubectl >/dev/null 2>&1; then
        system_kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "未知")
        print_success "系统 kubectl: $system_kubectl_version"
    else
        print_warning "系统 kubectl 不可用"
    fi
    
    if command -v minikube >/dev/null 2>&1; then
        system_minikube_version=$(minikube version --short 2>/dev/null || echo "未知")
        print_success "系统 minikube: $system_minikube_version"
    else
        print_warning "系统 minikube 不可用"
    fi
}

# 检查 minikube 集群状态
check_cluster_status() {
    print_header "集群状态检查"
    
    if ! command -v minikube >/dev/null 2>&1; then
        print_error "minikube 命令不可用"
        return 1
    fi
    
    # 检查 minikube 状态
    if minikube status >/dev/null 2>&1; then
        print_success "minikube 集群正在运行"
        
        echo
        print_info "集群详细状态："
        minikube status
        
        # 检查节点
        if command -v kubectl >/dev/null 2>&1; then
            echo
            print_info "集群节点："
            kubectl get nodes 2>/dev/null || print_warning "无法获取节点信息"
            
            echo
            print_info "系统 Pod："
            kubectl get pods -n kube-system --no-headers 2>/dev/null | head -5 || print_warning "无法获取 Pod 信息"
        fi
    else
        print_warning "minikube 集群未运行"
        print_info "使用以下命令启动集群："
        print_info "minikube start"
        
        local install_dir="$HOME/.tools/minikube"
        if [[ -x "$install_dir/start-minikube.sh" ]]; then
            print_info "或使用: $install_dir/start-minikube.sh"
        fi
    fi
}

# 检查依赖
check_dependencies() {
    print_header "依赖检查"
    
    local deps=("docker" "curl" "wget")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            case "$dep" in
                docker)
                    if docker info >/dev/null 2>&1; then
                        print_success "$dep: 已安装且运行中"
                    else
                        print_warning "$dep: 已安装但未运行"
                    fi
                    ;;
                *)
                    print_success "$dep: 已安装"
                    ;;
            esac
        else
            missing+=("$dep")
            print_warning "$dep: 未安装"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        print_info "建议安装缺失的依赖项："
        case "$(uname -s)" in
            Darwin*)
                print_info "macOS: brew install ${missing[*]}"
                ;;
            Linux*)
                print_info "Ubuntu/Debian: sudo apt install -y ${missing[*]}"
                print_info "RHEL/CentOS: sudo yum install -y ${missing[*]}"
                ;;
        esac
    fi
}

# 显示有用的命令
show_useful_commands() {
    print_header "常用命令"
    
    echo "集群管理："
    echo "  minikube start           # 启动集群"
    echo "  minikube stop            # 停止集群"
    echo "  minikube delete          # 删除集群"
    echo "  minikube status          # 查看状态"
    echo "  minikube dashboard       # 打开仪表板"
    echo "  minikube ssh             # SSH 到节点"
    echo
    echo "kubectl 命令："
    echo "  kubectl get nodes        # 查看节点"
    echo "  kubectl get pods         # 查看 Pod"
    echo "  kubectl get services     # 查看服务"
    echo "  kubectl get namespaces   # 查看命名空间"
    echo
    echo "便捷脚本："
    local install_dir="$HOME/.tools/minikube"
    if [[ -d "$install_dir" ]]; then
        echo "  $install_dir/start-minikube.sh    # 启动脚本"
        echo "  $install_dir/check-status.sh      # 状态检查"
        echo "  $install_dir/uninstall.sh         # 卸载脚本"
    fi
}

# 主函数
main() {
    echo "=== minikube 环境状态检查 ==="
    echo "检查时间: $(date)"
    echo
    
    check_minikube_installation
    echo
    check_dependencies
    echo
    check_cluster_status
    echo
    show_useful_commands
    
    echo
    print_info "检查完成"
}

# 运行主函数
main "$@"
