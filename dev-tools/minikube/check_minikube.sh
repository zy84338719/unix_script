#!/usr/bin/env bash

# 引入公共函数库（颜色码与打印函数统一）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"


# 检查 minikube 安装状态
check_minikube_installation() {
    header "minikube 安装检查"
    
    local install_dir="$HOME/.tools/minikube"
    local kubectl_path="$install_dir/bin/kubectl"
    local minikube_path="$install_dir/bin/minikube"
    
    # 检查安装目录
    if [[ -d "$install_dir" ]]; then
        success "安装目录存在: $install_dir"
    else
        error "安装目录不存在: $install_dir"
        return 1
    fi
    
    # 检查 kubectl
    if [[ -x "$kubectl_path" ]]; then
        kubectl_version=$("$kubectl_path" version --client --short 2>/dev/null | cut -d' ' -f3 || echo "未知")
        success "kubectl 已安装: $kubectl_version"
    else
        error "kubectl 未安装或不可执行"
    fi
    
    # 检查 minikube
    if [[ -x "$minikube_path" ]]; then
        minikube_version=$("$minikube_path" version --short 2>/dev/null || echo "未知")
        success "minikube 已安装: $minikube_version"
    else
        error "minikube 未安装或不可执行"
    fi
    
    # 检查环境变量
    if echo "$PATH" | grep -q "$install_dir/bin"; then
        success "PATH 配置正确"
    else
        warn "PATH 中未包含 minikube 目录"
        info "请添加以下行到您的 shell 配置文件："
        info "export PATH=\"$install_dir/bin:\$PATH\""
    fi
    
    # 检查系统 kubectl/minikube
    echo
    info "系统命令检查："
    
    if command -v kubectl >/dev/null 2>&1; then
        system_kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "未知")
        success "系统 kubectl: $system_kubectl_version"
    else
        warn "系统 kubectl 不可用"
    fi
    
    if command -v minikube >/dev/null 2>&1; then
        system_minikube_version=$(minikube version --short 2>/dev/null || echo "未知")
        success "系统 minikube: $system_minikube_version"
    else
        warn "系统 minikube 不可用"
    fi
}

# 检查 minikube 集群状态
check_cluster_status() {
    header "集群状态检查"
    
    if ! command -v minikube >/dev/null 2>&1; then
        error "minikube 命令不可用"
        return 1
    fi
    
    # 检查 minikube 状态
    if minikube status >/dev/null 2>&1; then
        success "minikube 集群正在运行"
        
        echo
        info "集群详细状态："
        minikube status
        
        # 检查节点
        if command -v kubectl >/dev/null 2>&1; then
            echo
            info "集群节点："
            kubectl get nodes 2>/dev/null || warn "无法获取节点信息"
            
            echo
            info "系统 Pod："
            kubectl get pods -n kube-system --no-headers 2>/dev/null | head -5 || warn "无法获取 Pod 信息"
        fi
    else
        warn "minikube 集群未运行"
        info "使用以下命令启动集群："
        info "minikube start"
        
        local install_dir="$HOME/.tools/minikube"
        if [[ -x "$install_dir/start-minikube.sh" ]]; then
            info "或使用: $install_dir/start-minikube.sh"
        fi
    fi
}

# 检查依赖
check_dependencies() {
    header "依赖检查"
    
    local deps=("docker" "curl" "wget")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            case "$dep" in
                docker)
                    if docker info >/dev/null 2>&1; then
                        success "$dep: 已安装且运行中"
                    else
                        warn "$dep: 已安装但未运行"
                    fi
                    ;;
                *)
                    success "$dep: 已安装"
                    ;;
            esac
        else
            missing+=("$dep")
            warn "$dep: 未安装"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        info "建议安装缺失的依赖项："
        case "$(uname -s)" in
            Darwin*)
                info "macOS: brew install ${missing[*]}"
                ;;
            Linux*)
                info "Ubuntu/Debian: sudo apt install -y ${missing[*]}"
                info "RHEL/CentOS: sudo yum install -y ${missing[*]}"
                ;;
        esac
    fi
}

# 显示有用的命令
show_useful_commands() {
    header "常用命令"
    
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
    info "检查完成"
}

# 运行主函数
main "$@"
