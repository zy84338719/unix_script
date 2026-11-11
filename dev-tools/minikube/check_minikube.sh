#!/usr/bin/env bash

# 引入公共函数库（颜色码与打印函数统一）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"


# 检查 minikube 安装状态
check_minikube_installation() {
    header "minikube $(_t 'Installation check')"
    
    local install_dir="$HOME/.tools/minikube"
    local kubectl_path="$install_dir/bin/kubectl"
    local minikube_path="$install_dir/bin/minikube"
    
    # 检查安装目录
    if [[ -d "$install_dir" ]]; then
        success "$(_tf 'Install directory exists: %s' "$install_dir")"
    else
        error "$(_tf 'Install directory does not exist: %s' "$install_dir")"
        return 1
    fi
    
    # 检查 kubectl
    if [[ -x "$kubectl_path" ]]; then
        kubectl_version=$("$kubectl_path" version --client --short 2>/dev/null | cut -d' ' -f3 || printf '%s\n' "$(_t 'unknown')")
        success "kubectl $(_tf 'Installed: %s' "$kubectl_version")"
    else
        error "kubectl $(_t 'Not installed or not executable')"
    fi
    
    # 检查 minikube
    if [[ -x "$minikube_path" ]]; then
        minikube_version=$("$minikube_path" version --short 2>/dev/null || printf '%s\n' "$(_t 'unknown')")
        success "minikube $(_tf 'Installed: %s' "$minikube_version")"
    else
        error "minikube $(_t 'Not installed or not executable')"
    fi
    
    # 检查环境变量
    if echo "$PATH" | grep -q "$install_dir/bin"; then
        success "PATH $(_t 'Configured correctly')"
    else
        warn "PATH $(_t 'does not contain the minikube directory')"
        info "$(_t 'Please add the following line to your shell configuration file:')"
        info "export PATH=\"$install_dir/bin:\$PATH\""
    fi
    
    # 检查系统 kubectl/minikube
    echo
    info "$(_t 'System command check:')"
    
    if command -v kubectl >/dev/null 2>&1; then
        system_kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || printf '%s\n' "$(_t 'unknown')")
        success "$(_tf 'System kubectl: %s' "$system_kubectl_version")"
    else
        warn "$(_t 'System kubectl is not available')"
    fi
    
    if command -v minikube >/dev/null 2>&1; then
        system_minikube_version=$(minikube version --short 2>/dev/null || printf '%s\n' "$(_t 'unknown')")
        success "$(_tf 'System minikube: %s' "$system_minikube_version")"
    else
        warn "$(_t 'System minikube is not available')"
    fi
}

# 检查 minikube 集群状态
check_cluster_status() {
    header "$(_t 'Cluster status check')"
    
    if ! command -v minikube >/dev/null 2>&1; then
        error "minikube $(_t 'Command not available')"
        return 1
    fi
    
    # 检查 minikube 状态
    if minikube status >/dev/null 2>&1; then
        success "minikube $(_t 'The cluster is running')"
        
        echo
        info "$(_t 'Detailed cluster status:')"
        minikube status
        
        # 检查节点
        if command -v kubectl >/dev/null 2>&1; then
            echo
            info "$(_t 'Cluster nodes:')"
            kubectl get nodes 2>/dev/null || warn "$(_t 'Cannot get the node information')"
            
            echo
            info "$(_t 'System pods:')"
            kubectl get pods -n kube-system --no-headers 2>/dev/null | head -5 || warn "$(_t 'Cannot get the pod information')"
        fi
    else
        warn "minikube $(_t 'The cluster is not running')"
        info "$(_t 'Start the cluster with the following command:')"
        info "minikube start"
        
        local install_dir="$HOME/.tools/minikube"
        if [[ -x "$install_dir/start-minikube.sh" ]]; then
            info "$(_tf 'Or use: %s/start-minikube.sh' "$install_dir")"
        fi
    fi
}

# 检查依赖
check_dependencies() {
    header "$(_t 'Dependency check')"
    
    local deps=("docker" "curl" "wget")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            case "$dep" in
                docker)
                    if docker info >/dev/null 2>&1; then
                        success "$dep: $(_t 'Installed and running (dependency check)')"
                    else
                        warn "$dep: $(_t 'Installed but not running')"
                    fi
                    ;;
                *)
                    success "$dep: $(_t 'Installed')"
                    ;;
            esac
        else
            missing+=("$dep")
            warn "$dep: $(_t 'Not installed')"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        info "$(_t 'Install the missing dependencies:')"
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
    header "$(_t 'Common commands')"
    
    printf '%s\n' "$(_t 'Cluster management:')"
    echo "  minikube start           # $(_t 'Start the cluster')"
    echo "  minikube stop            # $(_t 'Stop the cluster')"
    echo "  minikube delete          # $(_t 'Delete the cluster')"
    echo "  minikube status          # $(_t 'Check the status')"
    echo "  minikube dashboard       # $(_t 'Open the dashboard')"
    echo "  minikube ssh             # SSH $(_t 'Switch to a node')"
    echo
    echo "kubectl $(_t 'Commands:')"
    echo "  kubectl get nodes        # $(_t 'List the nodes')"
    echo "  kubectl get pods         # $(_t 'List the pods')"
    echo "  kubectl get services     # $(_t 'List the services')"
    echo "  kubectl get namespaces   # $(_t 'List the namespaces')"
    echo
    printf '%s\n' "$(_t 'Convenience scripts:')"
    local install_dir="$HOME/.tools/minikube"
    if [[ -d "$install_dir" ]]; then
        echo "  $install_dir/start-minikube.sh    # $(_t 'Start script')"
        echo "  $install_dir/check-status.sh      # $(_t 'Status check')"
        echo "  $install_dir/uninstall.sh         # $(_t 'Uninstall script')"
    fi
}

# 主函数
main() {
    echo "=== minikube $(_t 'Environment status check ===')"
    printf '%s\n' "$(_t 'Check time'): $(date)"
    echo
    
    check_minikube_installation
    echo
    check_dependencies
    echo
    check_cluster_status
    echo
    show_useful_commands
    
    echo
    info "$(_t 'Check complete')"
}

# 运行主函数
main "$@"
