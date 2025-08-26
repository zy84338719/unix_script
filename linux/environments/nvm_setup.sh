#!/bin/bash

# NVM (Node Version Manager) 安装脚本 - Linux 版本
# 作者: unix_script
# 支持的发行版: Ubuntu, Debian, CentOS, Rocky Linux, Fedora, Arch Linux

set -euo pipefail

# 导入通用工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common/colors.sh"
source "${SCRIPT_DIR}/../../common/utils.sh"

# 配置变量
NVM_VERSION="${NVM_VERSION:-v0.39.7}"  # NVM 版本
NODE_LTS_VERSION="${NODE_LTS_VERSION:-lts}"  # Node.js 版本
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"  # NVM 安装目录
INSTALL_DIR="$HOME/.nvm"
PROFILE_FILE=""

# 显示脚本信息
show_info() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    NVM (Node Version Manager) 安装     ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}支持的功能:${NC}"
    echo -e "  • 自动下载并安装最新版本的 NVM"
    echo -e "  • 配置 Shell 环境 (bash/zsh)"
    echo -e "  • 安装 Node.js LTS 版本"
    echo -e "  • 自动配置环境变量"
    echo -e "${YELLOW}NVM 版本:${NC} ${NVM_VERSION}"
    echo -e "${YELLOW}Node.js 版本:${NC} ${NODE_LTS_VERSION}"
    echo ""
}

# 检查系统要求
check_system() {
    echo -e "${BLUE}[INFO]${NC} 检查系统要求..."
    
    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        echo -e "${RED}[ERROR]${NC} 此脚本仅支持 Linux 系统"
        exit 1
    fi
    
    # 检查必要命令
    local required_commands=("curl" "bash")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            echo -e "${RED}[ERROR]${NC} 缺少必要命令: $cmd"
            echo -e "${YELLOW}[INFO]${NC} 请先安装: $cmd"
            exit 1
        fi
    done
    
    echo -e "${GREEN}[SUCCESS]${NC} 系统要求检查通过"
}

# 检测并安装依赖
install_dependencies() {
    echo -e "${BLUE}[INFO]${NC} 检查和安装依赖包..."
    
    # 检查必要的工具是否已经存在
    local missing_tools=()
    local required_tools=("curl" "wget")
    
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    # 如果所有必要工具都存在，跳过安装
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} 所有必要工具已存在，跳过依赖安装"
        return 0
    fi
    
    echo -e "${YELLOW}[INFO]${NC} 缺少工具: ${missing_tools[*]}"
    
    # 检测包管理器并安装
    if command_exists apt-get; then
        # Ubuntu/Debian
        echo -e "${BLUE}[INFO]${NC} 使用 apt-get 安装依赖..."
        
        # 尝试更新包列表，如果失败则跳过
        if ! sudo apt-get update -qq 2>/dev/null; then
            echo -e "${YELLOW}[WARNING]${NC} 包列表更新失败，尝试使用现有包信息"
        fi
        
        # 尝试安装必要的包
        local apt_packages=()
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "curl") apt_packages+=("curl") ;;
                "wget") apt_packages+=("wget") ;;
            esac
        done
        
        if [[ ${#apt_packages[@]} -gt 0 ]]; then
            if sudo apt-get install -y "${apt_packages[@]}" 2>/dev/null; then
                echo -e "${GREEN}[SUCCESS]${NC} 依赖包安装成功"
            else
                echo -e "${YELLOW}[WARNING]${NC} 部分依赖包安装失败，继续尝试安装 NVM"
            fi
        fi
        
    elif command_exists yum; then
        # CentOS/RHEL/Rocky Linux (旧版本)
        echo -e "${BLUE}[INFO]${NC} 使用 yum 安装依赖..."
        sudo yum install -y curl wget gcc gcc-c++ make
    elif command_exists dnf; then
        # Fedora/CentOS/RHEL/Rocky Linux (新版本)
        echo -e "${BLUE}[INFO]${NC} 使用 dnf 安装依赖..."
        sudo dnf install -y curl wget gcc gcc-c++ make
    elif command_exists pacman; then
        # Arch Linux
        echo -e "${BLUE}[INFO]${NC} 使用 pacman 安装依赖..."
        sudo pacman -S --noconfirm curl wget base-devel
    elif command_exists zypper; then
        # openSUSE
        echo -e "${BLUE}[INFO]${NC} 使用 zypper 安装依赖..."
        sudo zypper install -y curl wget gcc gcc-c++ make
    else
        echo -e "${YELLOW}[WARNING]${NC} 未检测到支持的包管理器"
        echo -e "${YELLOW}[INFO]${NC} 请手动安装以下依赖: ${missing_tools[*]}"
        
        # 询问是否继续
        if ! confirm "是否继续安装 NVM (可能需要手动安装依赖)？" "y"; then
            echo -e "${YELLOW}[INFO]${NC} 取消安装"
            exit 0
        fi
    fi
    
    # 再次检查工具是否可用
    local still_missing=()
    for tool in "${missing_tools[@]}"; do
        if ! command_exists "$tool"; then
            still_missing+=("$tool")
        fi
    done
    
    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}[WARNING]${NC} 以下工具仍然缺失: ${still_missing[*]}"
        echo -e "${BLUE}[INFO]${NC} 尝试继续安装 NVM..."
    else
        echo -e "${GREEN}[SUCCESS]${NC} 所有依赖工具安装完成"
    fi
}

# 卸载现有的 NVM
uninstall_existing_nvm() {
    if [[ -d "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} 检测到已安装的 NVM"
        if confirm "是否卸载现有的 NVM 并重新安装？" "n"; then
            echo -e "${BLUE}[INFO]${NC} 卸载现有的 NVM..."
            rm -rf "$INSTALL_DIR"
            echo -e "${GREEN}[SUCCESS]${NC} 现有 NVM 已卸载"
        else
            echo -e "${YELLOW}[INFO]${NC} 取消安装"
            exit 0
        fi
    fi
}

# 确定 Shell 配置文件
detect_shell_profile() {
    echo -e "${BLUE}[INFO]${NC} 检测 Shell 环境..."
    
    # 检测当前 Shell
    local current_shell=$(basename "$SHELL")
    echo -e "${YELLOW}[INFO]${NC} 当前 Shell: $current_shell"
    
    # 确定配置文件
    case "$current_shell" in
        zsh)
            if [[ -f "$HOME/.zshrc" ]]; then
                PROFILE_FILE="$HOME/.zshrc"
            else
                PROFILE_FILE="$HOME/.zshrc"
                touch "$PROFILE_FILE"
            fi
            ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                PROFILE_FILE="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                PROFILE_FILE="$HOME/.bash_profile"
            else
                PROFILE_FILE="$HOME/.bashrc"
                touch "$PROFILE_FILE"
            fi
            ;;
        *)
            # 默认使用 .bashrc
            PROFILE_FILE="$HOME/.bashrc"
            if [[ ! -f "$PROFILE_FILE" ]]; then
                touch "$PROFILE_FILE"
            fi
            echo -e "${YELLOW}[WARNING]${NC} 未识别的 Shell，将使用 .bashrc"
            ;;
    esac
    
    echo -e "${GREEN}[SUCCESS]${NC} 将使用配置文件: $PROFILE_FILE"
}

# 下载并安装 NVM
install_nvm() {
    echo -e "${BLUE}[INFO]${NC} 开始安装 NVM ${NVM_VERSION}..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 下载 NVM 安装脚本
    local install_script_url="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
    echo -e "${BLUE}[INFO]${NC} 下载 NVM 安装脚本..."
    
    # 尝试多种下载方式
    local download_success=false
    
    # 方法1: 使用 curl (默认)
    if curl -fsSL "$install_script_url" -o /tmp/nvm_install.sh 2>/dev/null; then
        download_success=true
        echo -e "${GREEN}[SUCCESS]${NC} 使用 curl 下载成功"
    # 方法2: 使用 curl 忽略证书验证
    elif curl -fsSLk "$install_script_url" -o /tmp/nvm_install.sh 2>/dev/null; then
        download_success=true
        echo -e "${YELLOW}[WARNING]${NC} 使用 curl (忽略证书验证) 下载成功"
    # 方法3: 使用 wget
    elif command_exists wget && wget -q "$install_script_url" -O /tmp/nvm_install.sh 2>/dev/null; then
        download_success=true
        echo -e "${GREEN}[SUCCESS]${NC} 使用 wget 下载成功"
    # 方法4: 使用 wget 忽略证书验证
    elif command_exists wget && wget -q --no-check-certificate "$install_script_url" -O /tmp/nvm_install.sh 2>/dev/null; then
        download_success=true
        echo -e "${YELLOW}[WARNING]${NC} 使用 wget (忽略证书验证) 下载成功"
    fi
    
    if [ "$download_success" = true ]; then
        # 验证下载的脚本
        if [[ -f "/tmp/nvm_install.sh" && -s "/tmp/nvm_install.sh" ]]; then
            echo -e "${BLUE}[INFO]${NC} 执行 NVM 安装脚本..."
            if bash /tmp/nvm_install.sh; then
                echo -e "${GREEN}[SUCCESS]${NC} NVM 安装脚本执行成功"
                rm -f /tmp/nvm_install.sh
            else
                echo -e "${RED}[ERROR]${NC} NVM 安装脚本执行失败"
                rm -f /tmp/nvm_install.sh
                exit 1
            fi
        else
            echo -e "${RED}[ERROR]${NC} 下载的安装脚本无效"
            exit 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} 所有下载方法都失败了"
        echo -e "${YELLOW}[INFO]${NC} 请检查网络连接或手动下载安装脚本:"
        echo -e "  1. 访问: $install_script_url"
        echo -e "  2. 下载并保存为 nvm_install.sh"
        echo -e "  3. 运行: bash nvm_install.sh"
        exit 1
    fi
}

# 配置环境变量
configure_environment() {
    echo -e "${BLUE}[INFO]${NC} 配置环境变量..."
    
    # NVM 环境变量配置
    local nvm_config='
# NVM 配置
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion'
    
    # 检查是否已经配置
    if ! grep -q "NVM_DIR" "$PROFILE_FILE"; then
        echo "$nvm_config" >> "$PROFILE_FILE"
        echo -e "${GREEN}[SUCCESS]${NC} 环境变量配置已添加到 $PROFILE_FILE"
    else
        echo -e "${YELLOW}[INFO]${NC} 环境变量已存在，跳过配置"
    fi
}

# 加载 NVM 并安装 Node.js
install_nodejs() {
    echo -e "${BLUE}[INFO]${NC} 加载 NVM 并安装 Node.js..."
    
    # 加载 NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # 检查 NVM 是否成功加载
    if ! command_exists nvm; then
        echo -e "${RED}[ERROR]${NC} NVM 加载失败，请重新启动终端或运行: source $PROFILE_FILE"
        return 1
    fi
    
    echo -e "${BLUE}[INFO]${NC} 安装 Node.js ${NODE_LTS_VERSION}..."
    
    # 安装 Node.js LTS 版本
    if nvm install "$NODE_LTS_VERSION"; then
        nvm use "$NODE_LTS_VERSION"
        nvm alias default "$NODE_LTS_VERSION"
        echo -e "${GREEN}[SUCCESS]${NC} Node.js 安装成功"
        
        # 显示版本信息
        echo -e "${YELLOW}[INFO]${NC} Node.js 版本: $(node --version)"
        echo -e "${YELLOW}[INFO]${NC} npm 版本: $(npm --version)"
    else
        echo -e "${RED}[ERROR]${NC} Node.js 安装失败"
        return 1
    fi
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}[INFO]${NC} 验证安装..."
    
    # 重新加载环境
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # 检查 NVM
    if command_exists nvm; then
        echo -e "${GREEN}[SUCCESS]${NC} NVM 安装成功"
        echo -e "${YELLOW}[INFO]${NC} NVM 版本: $(nvm --version)"
    else
        echo -e "${RED}[ERROR]${NC} NVM 验证失败"
        return 1
    fi
    
    # 检查 Node.js
    if command_exists node; then
        echo -e "${GREEN}[SUCCESS]${NC} Node.js 安装成功"
        echo -e "${YELLOW}[INFO]${NC} Node.js 版本: $(node --version)"
    else
        echo -e "${YELLOW}[WARNING]${NC} Node.js 未安装或未加载，请运行: nvm install $NODE_LTS_VERSION"
    fi
    
    # 检查 npm
    if command_exists npm; then
        echo -e "${GREEN}[SUCCESS]${NC} npm 可用"
        echo -e "${YELLOW}[INFO]${NC} npm 版本: $(npm --version)"
    else
        echo -e "${YELLOW}[WARNING]${NC} npm 未找到"
    fi
}

# 显示使用说明
show_usage() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}           安装完成！                    ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}使用说明:${NC}"
    echo -e "  1. 重新启动终端或运行以下命令以加载 NVM:"
    echo -e "     ${GREEN}source $PROFILE_FILE${NC}"
    echo -e ""
    echo -e "  2. 常用 NVM 命令:"
    echo -e "     • 查看 NVM 版本:     ${GREEN}nvm --version${NC}"
    echo -e "     • 列出可用版本:     ${GREEN}nvm list-remote${NC}"
    echo -e "     • 安装指定版本:     ${GREEN}nvm install <version>${NC}"
    echo -e "     • 使用指定版本:     ${GREEN}nvm use <version>${NC}"
    echo -e "     • 查看已安装版本:   ${GREEN}nvm list${NC}"
    echo -e "     • 设置默认版本:     ${GREEN}nvm alias default <version>${NC}"
    echo -e ""
    echo -e "  3. Node.js 和 npm 已准备就绪:"
    echo -e "     • Node.js 版本: ${GREEN}$(node --version 2>/dev/null || echo "需要重新加载终端")${NC}"
    echo -e "     • npm 版本: ${GREEN}$(npm --version 2>/dev/null || echo "需要重新加载终端")${NC}"
    echo -e ""
    echo -e "${YELLOW}配置文件:${NC} $PROFILE_FILE"
    echo -e "${YELLOW}安装目录:${NC} $INSTALL_DIR"
}

# 主函数
main() {
    show_info
    
    if ! confirm "是否继续安装 NVM？"; then
        echo -e "${YELLOW}[INFO]${NC} 取消安装"
        exit 0
    fi
    
    echo -e "${BLUE}[INFO]${NC} 开始安装过程..."
    
    check_system
    install_dependencies
    uninstall_existing_nvm
    detect_shell_profile
    install_nvm
    configure_environment
    
    # 尝试安装 Node.js (可能失败，因为需要重新加载环境)
    if install_nodejs; then
        verify_installation
    else
        echo -e "${YELLOW}[WARNING]${NC} Node.js 安装需要重新加载终端环境"
    fi
    
    show_usage
    
    echo -e "${GREEN}[SUCCESS]${NC} NVM 安装脚本执行完成！"
}

# 执行主函数
main "$@"
