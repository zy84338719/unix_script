#!/usr/bin/env bash
#
# Homebrew 安装脚本 - macOS 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 检查现有安装
check_existing_installation() {
    if command_exists brew; then
        local version
        version=$(brew --version | head -1)
        print_warning "检测到已安装 Homebrew: $version"
        
        if confirm "是否重新配置或更新 Homebrew？" "n"; then
            return 0
        else
            print_info "配置已取消"
            return 1
        fi
    fi
    return 0
}

# 检查系统要求
check_system_requirements() {
    print_info "检查系统要求..."
    
    # 检查 macOS 版本
    local macos_version
    macos_version=$(sw_vers -productVersion)
    print_info "macOS 版本: $macos_version"
    
    # 检查架构
    local arch=$(uname -m)
    print_info "CPU 架构: $arch"
    
    # 检查 Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        print_warning "未检测到 Xcode Command Line Tools"
        if confirm "是否安装 Xcode Command Line Tools？" "y"; then
            print_info "正在安装 Xcode Command Line Tools..."
            xcode-select --install
            print_info "请在弹出的对话框中完成安装，然后按任意键继续..."
            wait_for_key
        else
            print_error "Homebrew 需要 Xcode Command Line Tools"
            return 1
        fi
    else
        print_success "Xcode Command Line Tools 已安装"
    fi
    
    return 0
}

# 安装 Homebrew
install_homebrew() {
    if command_exists brew; then
        print_info "Homebrew 已安装"
        return 0
    fi
    
    print_info "正在安装 Homebrew..."
    
    # 下载并运行安装脚本
    local install_script="/tmp/install_homebrew.sh"
    setup_cleanup "$install_script"
    
    if safe_download "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$install_script"; then
        print_info "开始执行 Homebrew 安装脚本..."
        /bin/bash "$install_script"
        
        if [[ $? -eq 0 ]]; then
            print_success "Homebrew 安装成功"
        else
            print_error "Homebrew 安装失败"
            return 1
        fi
    else
        print_error "下载 Homebrew 安装脚本失败"
        return 1
    fi
    
    return 0
}

# 配置环境变量
configure_environment() {
    print_info "正在配置环境变量..."
    
    local arch=$(uname -m)
    local brew_path=""
    local shell_config=""
    
    # 确定 Homebrew 路径
    if [[ "$arch" == "arm64" ]]; then
        brew_path="/opt/homebrew"
    else
        brew_path="/usr/local"
    fi
    
    # 确定 shell 配置文件
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_config="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_config="$HOME/.bash_profile"
    else
        shell_config="$HOME/.profile"
    fi
    
    print_info "Homebrew 路径: $brew_path"
    print_info "Shell 配置文件: $shell_config"
    
    # 添加环境变量到 shell 配置
    local env_line="eval \"\$(${brew_path}/bin/brew shellenv)\""
    
    if [[ -f "$shell_config" ]] && grep -q "brew shellenv" "$shell_config"; then
        print_info "环境变量已配置"
    else
        print_info "添加环境变量到 $shell_config"
        echo "" >> "$shell_config"
        echo "# Homebrew 环境变量" >> "$shell_config"
        echo "$env_line" >> "$shell_config"
        print_success "环境变量配置完成"
    fi
    
    # 加载环境变量
    eval "$($brew_path/bin/brew shellenv)"
    
    return 0
}

# 更新 Homebrew
update_homebrew() {
    print_info "正在更新 Homebrew..."
    
    if brew update; then
        print_success "Homebrew 更新成功"
    else
        print_warning "Homebrew 更新失败，但不影响使用"
    fi
    
    return 0
}

# 安装推荐软件包
install_recommended_packages() {
    print_info "是否安装推荐的开发工具包？"
    echo
    print_info "推荐软件包："
    echo "  • git - 版本控制系统"
    echo "  • wget - 文件下载工具"
    echo "  • tree - 目录树显示"
    echo "  • htop - 系统监控工具"
    echo "  • jq - JSON 处理工具"
    echo "  • node - Node.js 运行时"
    echo
    
    if confirm "是否安装这些推荐软件包？" "y"; then
        local packages=("git" "wget" "tree" "htop" "jq" "node")
        
        print_info "正在安装推荐软件包..."
        for package in "${packages[@]}"; do
            print_info "安装 $package..."
            if brew install "$package"; then
                print_success "$package 安装成功"
            else
                print_warning "$package 安装失败"
            fi
        done
    fi
    
    return 0
}

# 配置 Homebrew 设置
configure_homebrew_settings() {
    print_info "配置 Homebrew 设置..."
    
    # 禁用匿名统计（可选）
    if confirm "是否禁用 Homebrew 匿名统计？" "y"; then
        export HOMEBREW_NO_ANALYTICS=1
        echo 'export HOMEBREW_NO_ANALYTICS=1' >> "$HOME/.zshrc"
        print_success "已禁用匿名统计"
    fi
    
    # 配置中国镜像（可选）
    if confirm "是否配置中国镜像以加速下载？" "n"; then
        print_info "配置中国镜像..."
        
        # 配置 Homebrew 镜像
        export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
        export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
        export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
        
        # 添加到配置文件
        cat >> "$HOME/.zshrc" <<EOF

# Homebrew 中国镜像配置
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
EOF
        
        print_success "中国镜像配置完成"
    fi
    
    return 0
}

# 验证安装
verify_installation() {
    print_info "正在验证安装..."
    
    # 检查 brew 命令
    if command_exists brew; then
        local version
        version=$(brew --version | head -1)
        print_success "Homebrew 安装成功：$version"
    else
        print_error "Homebrew 验证失败"
        return 1
    fi
    
    # 检查环境配置
    if brew --prefix &>/dev/null; then
        local prefix
        prefix=$(brew --prefix)
        print_success "Homebrew 路径：$prefix"
    else
        print_error "Homebrew 环境配置失败"
        return 1
    fi
    
    # 运行 brew doctor
    print_info "运行 Homebrew 诊断..."
    if brew doctor; then
        print_success "Homebrew 配置正常"
    else
        print_warning "Homebrew 诊断发现一些问题，但通常不影响使用"
    fi
    
    return 0
}

# 主安装函数
install_homebrew_environment() {
    print_header "🚀 安装 Homebrew - macOS 包管理器"
    echo "========================================"
    
    # 执行安装步骤
    if ! check_existing_installation; then
        return 1
    fi
    
    if ! check_system_requirements; then
        return 1
    fi
    
    # 确认安装
    echo
    print_info "即将安装 Homebrew 包管理器"
    print_info "Homebrew 是 macOS 上最流行的包管理器"
    print_info "它可以帮助您轻松安装和管理各种开发工具"
    echo
    
    if ! confirm "确认继续安装？" "y"; then
        print_info "安装已取消"
        return 1
    fi
    
    # 执行安装
    if ! install_homebrew; then
        return 1
    fi
    
    if ! configure_environment; then
        return 1
    fi
    
    if ! update_homebrew; then
        return 1
    fi
    
    install_recommended_packages
    configure_homebrew_settings
    
    if ! verify_installation; then
        return 1
    fi
    
    echo
    print_success "🎉 Homebrew 安装配置完成！"
    echo "========================================"
    print_info "Homebrew 前缀路径：$(brew --prefix)"
    print_info "配置文件已更新"
    echo
    print_info "常用 Homebrew 命令："
    echo "  brew install <package>  - 安装软件包"
    echo "  brew uninstall <package> - 卸载软件包"
    echo "  brew list              - 列出已安装软件包"
    echo "  brew search <keyword>  - 搜索软件包"
    echo "  brew update            - 更新 Homebrew"
    echo "  brew upgrade           - 升级所有软件包"
    echo "  brew doctor            - 诊断问题"
    echo "  brew info <package>    - 查看软件包信息"
    echo
    print_info "Homebrew Cask 命令（GUI 应用）："
    echo "  brew install --cask <app> - 安装 GUI 应用"
    echo "  brew list --cask         - 列出已安装应用"
    echo
    print_warning "重要提示："
    echo "1. 重新打开终端或运行 'source ~/.zshrc' 以使环境变量生效"
    echo "2. 首次使用可能需要一些时间来设置"
    echo "3. 定期运行 'brew update && brew upgrade' 保持软件最新"
    echo
    print_info "立即生效环境变量：source ~/.zshrc"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_homebrew_environment
fi
