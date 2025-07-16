#!/usr/bin/env bash
#
# Zsh 环境配置脚本 - macOS 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 检查现有安装
check_existing_installation() {
    local zsh_installed=false
    local ohmyzsh_installed=false
    local is_default_shell=false
    local homebrew_zsh=false
    
    if command_exists zsh; then
        zsh_installed=true
        local zsh_path=$(which zsh)
        local zsh_version=$(zsh --version)
        print_info "检测到已安装 Zsh: $zsh_version"
        print_info "Zsh 路径: $zsh_path"
        
        # 检查是否为 Homebrew 安装的 Zsh
        if [[ "$zsh_path" == "/opt/homebrew/bin/zsh" ]] || [[ "$zsh_path" == "/usr/local/bin/zsh" ]]; then
            homebrew_zsh=true
            print_info "检测到 Homebrew 版本的 Zsh"
        fi
    fi
    
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ohmyzsh_installed=true
        print_info "检测到已安装 Oh My Zsh"
    fi
    
    if [[ "$SHELL" == *"zsh"* ]]; then
        is_default_shell=true
        print_info "Zsh 已是默认 Shell"
    fi
    
    if $zsh_installed && $ohmyzsh_installed && $is_default_shell; then
        print_warning "Zsh 环境已完全配置"
        if confirm "是否重新配置？" "n"; then
            return 0
        else
            print_info "配置已取消"
            return 1
        fi
    fi
    
    return 0
}

# 检查并安装 Homebrew
check_homebrew() {
    if ! command_exists brew; then
        print_warning "未检测到 Homebrew"
        if confirm "是否安装 Homebrew？（推荐）" "y"; then
            print_info "正在安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # 添加 Homebrew 到 PATH（Apple Silicon Mac）
            if [[ $(uname -m) == "arm64" ]]; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                eval "$(/opt/homebrew/bin/brew shellenv)"
            else
                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            
            if command_exists brew; then
                print_success "Homebrew 安装成功"
            else
                print_error "Homebrew 安装失败"
                return 1
            fi
        else
            print_info "将使用系统自带的 Zsh"
        fi
    fi
    
    return 0
}

# 安装/更新 Zsh
install_zsh() {
    # macOS 已预装 Zsh，但可能不是最新版本
    if command_exists brew; then
        print_info "正在通过 Homebrew 安装最新版 Zsh..."
        
        if brew install zsh; then
            print_success "Zsh 安装/更新成功"
            
            # 将 Homebrew 的 zsh 添加到 /etc/shells
            local homebrew_zsh
            if [[ $(uname -m) == "arm64" ]]; then
                homebrew_zsh="/opt/homebrew/bin/zsh"
            else
                homebrew_zsh="/usr/local/bin/zsh"
            fi
            
            if ! grep -q "$homebrew_zsh" /etc/shells; then
                print_info "将 Homebrew Zsh 添加到 /etc/shells..."
                echo "$homebrew_zsh" | sudo tee -a /etc/shells > /dev/null
            fi
        else
            print_warning "Homebrew Zsh 安装失败，将使用系统自带版本"
        fi
    else
        print_info "使用 macOS 系统自带的 Zsh"
    fi
    
    # 确保基本工具可用
    if ! command_exists curl; then
        print_error "curl 命令不可用，请先安装 Xcode Command Line Tools"
        print_info "运行: xcode-select --install"
        return 1
    fi
    
    return 0
}

# 安装 Oh My Zsh
install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        print_info "Oh My Zsh 已安装"
        return 0
    fi
    
    print_info "正在安装 Oh My Zsh..."
    
    # 备份现有 .zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        local backup_file
        backup_file=$(backup_file "$HOME/.zshrc")
        print_info "已备份现有 .zshrc 到 $backup_file"
    fi
    
    # 下载并安装 Oh My Zsh
    local install_script="/tmp/install_ohmyzsh.sh"
    setup_cleanup "$install_script"
    
    if safe_download "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "$install_script"; then
        if sh "$install_script" --unattended; then
            print_success "Oh My Zsh 安装成功"
        else
            print_error "Oh My Zsh 安装失败"
            return 1
        fi
    else
        print_error "下载 Oh My Zsh 安装脚本失败"
        return 1
    fi
    
    return 0
}

# 安装插件
install_plugins() {
    local plugins_dir="$HOME/.oh-my-zsh/custom/plugins"
    
    print_info "正在安装 Zsh 插件..."
    
    # 安装 zsh-autosuggestions
    local autosuggestions_dir="$plugins_dir/zsh-autosuggestions"
    if [[ ! -d "$autosuggestions_dir" ]]; then
        print_info "安装 zsh-autosuggestions..."
        if git clone https://github.com/zsh-users/zsh-autosuggestions "$autosuggestions_dir"; then
            print_success "zsh-autosuggestions 安装成功"
        else
            print_error "zsh-autosuggestions 安装失败"
        fi
    else
        print_info "zsh-autosuggestions 已安装"
    fi
    
    # 安装 zsh-syntax-highlighting
    local syntax_highlighting_dir="$plugins_dir/zsh-syntax-highlighting"
    if [[ ! -d "$syntax_highlighting_dir" ]]; then
        print_info "安装 zsh-syntax-highlighting..."
        if git clone https://github.com/zsh-users/zsh-syntax-highlighting "$syntax_highlighting_dir"; then
            print_success "zsh-syntax-highlighting 安装成功"
        else
            print_error "zsh-syntax-highlighting 安装失败"
        fi
    else
        print_info "zsh-syntax-highlighting 已安装"
    fi
    
    return 0
}

# 配置 .zshrc
configure_zshrc() {
    local zshrc_file="$HOME/.zshrc"
    
    print_info "正在配置 .zshrc..."
    
    # 创建新的 .zshrc 配置
    cat > "$zshrc_file" <<'EOF'
# Oh My Zsh 配置路径
export ZSH="$HOME/.oh-my-zsh"

# 主题设置
ZSH_THEME="robbyrussell"

# 插件列表
plugins=(
    git
    brew
    macos
    zsh-autosuggestions
    zsh-syntax-highlighting
    extract
    z
    history-substring-search
)

# 加载 Oh My Zsh
source $ZSH/oh-my-zsh.sh

# macOS 特定配置
# Homebrew 环境变量 (Apple Silicon)
if [[ $(uname -m) == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

# 用户自定义配置
# 别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'

# macOS 专用别名
alias finder='open -a Finder'
alias plist='plutil -p'
alias cleanDS='find . -name "*.DS_Store" -type f -delete'

# 历史设置
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# 自动建议颜色
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#666666"

# 命令提示符优化
setopt AUTO_CD
setopt CORRECT
setopt CORRECT_ALL

# 导出环境变量
export EDITOR='nano'
export LANG=en_US.UTF-8

# macOS 路径优化
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"

# 如果存在用户自定义配置文件，则加载它
if [[ -f "$HOME/.zshrc.local" ]]; then
    source "$HOME/.zshrc.local"
fi
EOF

    if [[ $? -eq 0 ]]; then
        print_success ".zshrc 配置完成"
    else
        print_error ".zshrc 配置失败"
        return 1
    fi
    
    return 0
}

# 设置默认 Shell
set_default_shell() {
    local zsh_path
    
    # 优先使用 Homebrew 版本的 zsh
    if command_exists brew; then
        if [[ $(uname -m) == "arm64" ]]; then
            zsh_path="/opt/homebrew/bin/zsh"
        else
            zsh_path="/usr/local/bin/zsh"
        fi
        
        if [[ ! -x "$zsh_path" ]]; then
            zsh_path=$(which zsh)
        fi
    else
        zsh_path=$(which zsh)
    fi
    
    if [[ "$SHELL" == "$zsh_path" ]]; then
        print_info "Zsh 已是默认 Shell"
        return 0
    fi
    
    print_info "正在将 Zsh 设置为默认 Shell..."
    print_info "使用 Zsh 路径: $zsh_path"
    
    # 检查 zsh 是否在 /etc/shells 中
    if ! grep -q "$zsh_path" /etc/shells; then
        print_info "将 Zsh 添加到 /etc/shells..."
        echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi
    
    # 更改默认 shell
    if chsh -s "$zsh_path"; then
        print_success "默认 Shell 已设置为 Zsh"
        print_info "重新打开终端或注销后重新登录生效"
    else
        print_error "设置默认 Shell 失败"
        print_info "请手动运行: chsh -s $zsh_path"
        return 1
    fi
    
    return 0
}

# 验证安装
verify_installation() {
    print_info "正在验证安装..."
    
    # 检查 Zsh
    if command_exists zsh; then
        local version
        version=$(zsh --version)
        print_success "Zsh 安装成功：$version"
    else
        print_error "Zsh 验证失败"
        return 1
    fi
    
    # 检查 Oh My Zsh
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        print_success "Oh My Zsh 安装成功"
    else
        print_error "Oh My Zsh 验证失败"
        return 1
    fi
    
    # 检查插件
    local plugins_dir="$HOME/.oh-my-zsh/custom/plugins"
    if [[ -d "$plugins_dir/zsh-autosuggestions" ]] && [[ -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
        print_success "Zsh 插件安装成功"
    else
        print_warning "部分插件可能安装失败"
    fi
    
    # 检查配置文件
    if [[ -f "$HOME/.zshrc" ]]; then
        print_success "配置文件创建成功"
    else
        print_error "配置文件验证失败"
        return 1
    fi
    
    return 0
}

# 主安装函数
install_zsh_environment() {
    print_header "🚀 配置 Zsh 环境 - macOS 平台"
    echo "========================================"
    
    # 执行安装步骤
    if ! check_existing_installation; then
        return 1
    fi
    
    # 确认安装
    echo
    print_info "即将配置 Zsh 开发环境"
    print_info "这将安装/配置："
    echo "  • Homebrew（如果未安装）"
    echo "  • 最新版 Zsh"
    echo "  • Oh My Zsh 框架"
    echo "  • zsh-autosuggestions 插件"
    echo "  • zsh-syntax-highlighting 插件"
    echo "  • macOS 优化的配置文件"
    echo
    
    if ! confirm "确认继续安装？" "n"; then
        print_info "安装已取消"
        return 1
    fi
    
    # 执行安装
    if ! check_homebrew; then
        return 1
    fi
    
    if ! install_zsh; then
        return 1
    fi
    
    if ! install_oh_my_zsh; then
        return 1
    fi
    
    if ! install_plugins; then
        return 1
    fi
    
    if ! configure_zshrc; then
        return 1
    fi
    
    if ! set_default_shell; then
        return 1
    fi
    
    if ! verify_installation; then
        return 1
    fi
    
    echo
    print_success "🎉 Zsh 环境配置完成！"
    echo "========================================"
    print_info "配置文件位置：$HOME/.zshrc"
    print_info "自定义配置：$HOME/.zshrc.local (可选)"
    echo
    print_info "已安装的插件："
    echo "  • git - Git 命令别名和状态显示"
    echo "  • brew - Homebrew 命令别名"
    echo "  • macos - macOS 特定功能"
    echo "  • zsh-autosuggestions - 命令自动建议"
    echo "  • zsh-syntax-highlighting - 语法高亮"
    echo "  • extract - 智能解压工具"
    echo "  • z - 快速目录跳转"
    echo "  • history-substring-search - 历史搜索"
    echo
    print_info "macOS 专用别名："
    echo "  finder   - 在 Finder 中打开当前目录"
    echo "  plist    - 格式化显示 plist 文件"
    echo "  cleanDS  - 删除 .DS_Store 文件"
    echo
    print_warning "重要提示："
    echo "1. 重新打开终端或注销后重新登录以使默认 Shell 生效"
    echo "2. 可以在 ~/.zshrc.local 中添加个人配置"
    echo "3. 使用 'source ~/.zshrc' 重新加载配置"
    echo "4. 如果使用 Apple Silicon Mac，Homebrew 路径已自动配置"
    echo
    print_info "立即切换到 Zsh：exec zsh"
    echo
    
    return 0
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_zsh_environment
fi
