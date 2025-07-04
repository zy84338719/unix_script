#!/bin/bash

#
# install_process_manager.sh
#
# 安装进程管理工具到用户的 ~/.tools 目录，并配置环境变量
#

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # 无颜色

# --- 日志函数 ---
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
header() { echo -e "${CYAN}${BOLD}$1${NC}"; }

# --- 全局变量 ---
TOOLS_DIR="$HOME/.tools"
BIN_DIR="$TOOLS_DIR/bin"
SCRIPT_NAME="process_manager"
CONFIG_NAME="process_manager_config"

# --- 检测操作系统和Shell ---
detect_system() {
    # 检测操作系统
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            ;;
        Linux)
            OS="Linux"
            ;;
        *)
            error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac
    
    # 检测用户使用的Shell
    USER_SHELL=$(basename "$SHELL")
    case "$USER_SHELL" in
        bash)
            if [[ "$OS" == "macOS" ]]; then
                SHELL_RC="$HOME/.bash_profile"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            ;;
        fish)
            SHELL_RC="$HOME/.config/fish/config.fish"
            ;;
        *)
            warn "未识别的Shell: $USER_SHELL，使用默认配置"
            if [[ "$OS" == "macOS" ]]; then
                SHELL_RC="$HOME/.bash_profile"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
            ;;
    esac
    
    info "检测到系统: $OS"
    info "检测到Shell: $USER_SHELL"
    info "配置文件: $SHELL_RC"
}

# --- 创建工具目录 ---
create_tools_directory() {
    info "检查 ~/.tools 目录..."
    
    if [[ ! -d "$TOOLS_DIR" ]]; then
        info "创建 ~/.tools 目录..."
        mkdir -p "$TOOLS_DIR"
        success "已创建 $TOOLS_DIR"
    else
        info "~/.tools 目录已存在"
    fi
    
    if [[ ! -d "$BIN_DIR" ]]; then
        info "创建 ~/.tools/bin 目录..."
        mkdir -p "$BIN_DIR"
        success "已创建 $BIN_DIR"
    else
        info "~/.tools/bin 目录已存在"
    fi
}

# --- 复制脚本文件 ---
install_scripts() {
    info "安装进程管理工具脚本..."
    
    # 检查源文件是否存在
    if [[ ! -f "process_manager.sh" ]]; then
        error "未找到 process_manager.sh 文件，请在项目根目录运行此脚本"
        exit 1
    fi
    
    # 复制主脚本
    cp "process_manager.sh" "$BIN_DIR/$SCRIPT_NAME"
    chmod +x "$BIN_DIR/$SCRIPT_NAME"
    success "已安装 $SCRIPT_NAME 到 $BIN_DIR"
    
    # 复制包装脚本（如果存在）
    if [[ -f "pm_wrapper.sh" ]]; then
        cp "pm_wrapper.sh" "$BIN_DIR/pm"
        chmod +x "$BIN_DIR/pm"
        success "已安装 pm 包装脚本到 $BIN_DIR"
    fi
    
    # 复制配置文件（如果存在）
    if [[ -f "process_manager_config.sh" ]]; then
        cp "process_manager_config.sh" "$BIN_DIR/$CONFIG_NAME.sh"
        success "已安装配置文件到 $BIN_DIR"
    fi
    
    # 复制文档（如果存在）
    if [[ -d "process_manager" && -f "process_manager/README.md" ]]; then
        mkdir -p "$TOOLS_DIR/docs"
        cp "process_manager/README.md" "$TOOLS_DIR/docs/process_manager_README.md"
        success "已安装文档到 $TOOLS_DIR/docs"
    fi
    
    # 复制快速上手指南（如果存在）
    if [[ -f "PROCESS_MANAGER_QUICKSTART.md" ]]; then
        mkdir -p "$TOOLS_DIR/docs"
        cp "PROCESS_MANAGER_QUICKSTART.md" "$TOOLS_DIR/docs/process_manager_quickstart.md"
        success "已安装快速上手指南到 $TOOLS_DIR/docs"
    fi
}

# --- 配置环境变量 ---
setup_environment() {
    info "配置环境变量..."
    
    # 检查PATH中是否已包含~/.tools/bin
    if echo "$PATH" | grep -q "$BIN_DIR"; then
        info "PATH 中已包含 ~/.tools/bin"
        return 0
    fi
    
    # 根据不同Shell添加相应的配置
    local path_export="export PATH=\"\$HOME/.tools/bin:\$PATH\""
    local alias_pm="alias pm='$BIN_DIR/pm'"
    local alias_pmc="alias pmc='source \$HOME/.tools/bin/$CONFIG_NAME.sh && quick_search'"
    
    case "$USER_SHELL" in
        fish)
            # Fish shell 使用不同的语法
            local fish_config_dir="$HOME/.config/fish"
            mkdir -p "$fish_config_dir"
            
            if ! grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
                echo "" >> "$SHELL_RC"
                echo "# 添加 ~/.tools/bin 到 PATH" >> "$SHELL_RC"
                echo "set -gx PATH \$HOME/.tools/bin \$PATH" >> "$SHELL_RC"
                echo "" >> "$SHELL_RC"
                echo "# 进程管理工具别名" >> "$SHELL_RC"
                echo "alias pm='$BIN_DIR/pm'" >> "$SHELL_RC"
                success "已更新 Fish 配置文件"
            fi
            ;;
        *)
            # Bash/Zsh
            if ! grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
                echo "" >> "$SHELL_RC"
                echo "# 添加 ~/.tools/bin 到 PATH" >> "$SHELL_RC"
                echo "$path_export" >> "$SHELL_RC"
                echo "" >> "$SHELL_RC"
                echo "# 进程管理工具别名" >> "$SHELL_RC"
                echo "alias pm='$BIN_DIR/pm'" >> "$SHELL_RC"
                if [[ -f "$BIN_DIR/$CONFIG_NAME.sh" ]]; then
                    echo "$alias_pmc" >> "$SHELL_RC"
                fi
                success "已更新 $USER_SHELL 配置文件"
            fi
            ;;
    esac
}

# --- 创建快捷启动脚本 ---
create_launcher() {
    info "创建快捷启动脚本..."
    
    # 为当前用户创建符号链接（如果~/.local/bin存在且在PATH中）
    local local_bin="$HOME/.local/bin"
    if [[ -d "$local_bin" ]] && echo "$PATH" | grep -q "$local_bin"; then
        if ln -sf "$BIN_DIR/$SCRIPT_NAME" "$local_bin/pm" 2>/dev/null; then
            success "已创建用户级命令 'pm' (在 ~/.local/bin)"
        fi
    fi
    
    # 创建一个全局启动脚本（如果用户有sudo权限）
    local global_bin="/usr/local/bin"
    if [[ -w "$global_bin" ]] || sudo -n true 2>/dev/null; then
        read -r -p "是否创建全局命令链接 ($global_bin/pm)? [y/N]: "
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            if sudo ln -sf "$BIN_DIR/$SCRIPT_NAME" "$global_bin/pm" 2>/dev/null; then
                success "已创建全局命令 'pm'"
            else
                warn "无法创建全局命令链接"
            fi
        fi
    fi
}

# --- 验证安装 ---
verify_installation() {
    info "验证安装..."
    
    # 验证文件是否存在
    if [[ -f "$BIN_DIR/$SCRIPT_NAME" && -x "$BIN_DIR/$SCRIPT_NAME" ]]; then
        success "✅ 主脚本文件安装成功"
    else
        error "❌ 主脚本文件安装失败"
        return 1
    fi
    
    # 验证包装脚本
    if [[ -f "$BIN_DIR/pm" && -x "$BIN_DIR/pm" ]]; then
        success "✅ 包装脚本安装成功"
    else
        info "ℹ️  包装脚本未安装（可选）"
    fi
    
    # 验证配置文件
    if [[ -f "$BIN_DIR/$CONFIG_NAME.sh" ]]; then
        success "✅ 配置文件安装成功"
    else
        info "ℹ️  配置文件未安装（可选）"
    fi
    
    # 验证环境变量
    if grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
        success "✅ 环境变量配置成功"
    else
        warn "⚠️  环境变量配置可能失败"
    fi
    
    return 0
}

# --- 显示安装后信息 ---
show_post_install_info() {
    echo ""
    header "🎉 安装完成！"
    echo "================================================"
    echo ""
    
    success "进程管理工具已安装到: $BIN_DIR/$SCRIPT_NAME"
    echo ""
    
    header "使用方法："
    echo "1. 重新加载Shell配置:"
    echo "   source $SHELL_RC"
    echo ""
    echo "2. 或者重启终端"
    echo ""
    echo "3. 使用命令:"
    echo "   process_manager <搜索词>    # 直接搜索"
    echo "   process_manager             # 交互式模式"
    echo "   pm <搜索词>                 # 使用包装脚本(推荐)"
    echo "   pm                          # 交互式模式"
    echo ""
    
    if [[ -f "$BIN_DIR/$CONFIG_NAME.sh" ]]; then
        echo "4. 使用预定义快捷搜索:"
        echo "   pmc chrome                  # 搜索Chrome"
        echo "   pmc http                    # 搜索HTTP端口"
        echo ""
    fi
    
    header "示例:"
    echo "   pm node                     # 搜索Node.js进程"
    echo "   pm 3000                     # 搜索端口3000"
    echo "   pm chrome                   # 搜索Chrome浏览器"
    echo ""
    
    if [[ -f "$TOOLS_DIR/docs/process_manager_README.md" ]]; then
        echo "📖 详细文档: $TOOLS_DIR/docs/process_manager_README.md"
        echo ""
    fi
    
    warn "注意: 请重新加载Shell配置或重启终端以使环境变量生效"
    echo "================================================"
}

# --- 卸载功能 ---
uninstall() {
    header "🗑️  卸载进程管理工具"
    echo ""
    
    warn "这将删除以下内容:"
    echo "  • $BIN_DIR/$SCRIPT_NAME"
    echo "  • $BIN_DIR/pm"
    if [[ -f "$BIN_DIR/$CONFIG_NAME.sh" ]]; then
        echo "  • $BIN_DIR/$CONFIG_NAME.sh"
    fi
    if [[ -f "$TOOLS_DIR/docs/process_manager_README.md" ]]; then
        echo "  • $TOOLS_DIR/docs/process_manager_README.md"
    fi
    if [[ -f "$TOOLS_DIR/docs/process_manager_quickstart.md" ]]; then
        echo "  • $TOOLS_DIR/docs/process_manager_quickstart.md"
    fi
    echo "  • Shell配置文件中的相关配置"
    echo ""
    
    read -r -p "确认卸载? [y/N]: "
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        info "已取消卸载"
        exit 0
    fi
    
    # 删除文件
    rm -f "$BIN_DIR/$SCRIPT_NAME"
    rm -f "$BIN_DIR/pm"
    rm -f "$BIN_DIR/$CONFIG_NAME.sh"
    rm -f "$TOOLS_DIR/docs/process_manager_README.md"
    rm -f "$TOOLS_DIR/docs/process_manager_quickstart.md"
    
    # 删除全局链接
    if [[ -L "/usr/local/bin/pm" ]]; then
        sudo rm -f "/usr/local/bin/pm" 2>/dev/null || true
    fi
    
    # 删除用户级链接
    if [[ -L "$HOME/.local/bin/pm" ]]; then
        rm -f "$HOME/.local/bin/pm" 2>/dev/null || true
    fi
    
    # 清理Shell配置
    if [[ -f "$SHELL_RC" ]]; then
        # 创建备份
        cp "$SHELL_RC" "$SHELL_RC.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 删除相关配置行
        case "$USER_SHELL" in
            fish)
                sed -i.tmp '/# 添加.*\.tools\/bin/,/^$/d' "$SHELL_RC" 2>/dev/null || true
                sed -i.tmp '/process_manager/d' "$SHELL_RC" 2>/dev/null || true
                ;;
            *)
                sed -i.tmp '/# 添加.*\.tools\/bin/,/^$/d' "$SHELL_RC" 2>/dev/null || true
                sed -i.tmp '/process_manager/d' "$SHELL_RC" 2>/dev/null || true
                ;;
        esac
        rm -f "$SHELL_RC.tmp" 2>/dev/null || true
    fi
    
    success "卸载完成"
    info "Shell配置文件已备份为: $SHELL_RC.backup.*"
    warn "请重启终端或重新加载Shell配置以使更改生效"
}

# --- 主函数 ---
main() {
    # 检查参数
    if [[ "$1" == "uninstall" || "$1" == "--uninstall" || "$1" == "-u" ]]; then
        detect_system
        uninstall
        exit 0
    fi
    
    if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  install       安装进程管理工具 (默认)"
        echo "  uninstall     卸载进程管理工具"
        echo "  check         检查系统依赖"
        echo "  help          显示此帮助信息"
        echo ""
        exit 0
    fi
    
    if [[ "$1" == "check" || "$1" == "--check" || "$1" == "-c" ]]; then
        if [[ -f "check_dependencies.sh" ]]; then
            info "运行依赖检查..."
            bash check_dependencies.sh
            exit $?
        else
            error "未找到 check_dependencies.sh 文件"
            exit 1
        fi
    fi
    
    header "🔧 进程管理工具安装程序"
    echo "=================================="
    
    detect_system
    echo ""
    
    # 可选的依赖检查
    if [[ -f "check_dependencies.sh" ]]; then
        read -r -p "是否运行系统依赖检查? [y/N]: "
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo ""
            if ! bash check_dependencies.sh; then
                warn "依赖检查发现问题，是否继续安装? [y/N]:"
                read -r
                if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
                    info "安装已取消"
                    exit 1
                fi
            fi
            echo ""
        fi
    fi
    
    create_tools_directory
    echo ""
    
    install_scripts
    echo ""
    
    setup_environment
    echo ""
    
    create_launcher
    echo ""
    
    if verify_installation; then
        show_post_install_info
    else
        error "安装验证失败"
        exit 1
    fi
}

# --- 脚本入口 ---
main "$@"
