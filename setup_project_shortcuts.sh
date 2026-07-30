#!/bin/bash

#
# setup_project_shortcuts.sh
#
# 项目级别的快捷脚本管理器，创建便于访问各个工具的快捷方式
#

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
header() { echo -e "${CYAN}$1${NC}"; }

# 获取脚本所在目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

header "🚀 设置项目快捷访问脚本"
echo "========================================"

# 检查是否已存在快捷脚本
check_existing() {
    local existing_scripts=()
    
    if [ -f "$SCRIPT_DIR/pm_quick.sh" ]; then
        existing_scripts+=("pm_quick.sh")
    fi
    
    if [ -f "$SCRIPT_DIR/install_quick.sh" ]; then
        existing_scripts+=("install_quick.sh")
    fi
    
    if [ ${#existing_scripts[@]} -gt 0 ]; then
        warn "发现已存在的快捷脚本："
        for script in "${existing_scripts[@]}"; do
            echo "  - $script"
        done
        echo ""
        read -r -p "是否覆盖现有脚本? [y/N]: "
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            info "已取消创建"
            exit 0
        fi
    fi
}

# 创建进程管理工具快捷脚本
create_pm_quick() {
    info "创建进程管理工具快捷访问脚本..."
    
    cat > "$SCRIPT_DIR/pm_quick.sh" << 'EOF'
#!/bin/bash
#
# 进程管理工具快捷访问脚本
# 用法: ./pm_quick.sh [参数]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PM_TOOL_DIR="$SCRIPT_DIR/process_manager_tool"

# 检查进程管理工具目录是否存在
if [ ! -d "$PM_TOOL_DIR" ]; then
    echo "错误: 进程管理工具目录不存在: $PM_TOOL_DIR"
    exit 1
fi

# 智能选择运行方式
if [ -f "$HOME/.tools/bin/pm" ] && command -v pm >/dev/null 2>&1; then
    # 如果已安装，使用系统安装版本
    pm "$@"
else
    # 否则使用开发版本
    cd "$PM_TOOL_DIR" && bash pm_wrapper.sh "$@"
fi
EOF

    chmod +x "$SCRIPT_DIR/pm_quick.sh"
    success "✅ pm_quick.sh 创建完成"
}

# 创建主安装脚本快捷方式
create_install_quick() {
    info "创建主安装菜单快捷访问脚本..."
    
    cat > "$SCRIPT_DIR/install_quick.sh" << 'EOF'
#!/bin/bash
#
# 主安装菜单快捷访问脚本
# 用法: ./install_quick.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查主安装脚本是否存在
if [ ! -f "$SCRIPT_DIR/install.sh" ]; then
    echo "错误: 主安装脚本不存在: $SCRIPT_DIR/install.sh"
    exit 1
fi

# 运行主安装脚本
cd "$SCRIPT_DIR" && bash install.sh "$@"
EOF

    chmod +x "$SCRIPT_DIR/install_quick.sh"
    success "✅ install_quick.sh 创建完成"
}

# 显示使用说明
show_usage() {
    echo ""
    header "📖 使用说明"
    echo "========================================"
    echo ""
    
    info "进程管理工具快捷访问："
    echo "  ./pm_quick.sh                # 交互式模式"
    echo "  ./pm_quick.sh node           # 搜索node进程"
    echo "  ./pm_quick.sh 3000           # 搜索端口3000"
    echo "  ./pm_quick.sh --help         # 查看帮助"
    echo "  ./pm_quick.sh --config       # 查看配置"
    echo ""
    
    info "主安装菜单快捷访问："
    echo "  ./install_quick.sh           # 打开主安装菜单"
    echo ""
    
    info "进程管理工具完整功能："
    echo "  cd process_manager_tool/     # 进入工具目录"
    echo "  ./install_process_manager.sh # 安装到系统"
    echo "  ./check_dependencies.sh     # 检查系统依赖"
    echo ""
    
    warn "提示："
    echo "  - pm_quick.sh 会自动检测并使用已安装的系统版本"
    echo "  - 如果未安装，则使用开发版本"
    echo "  - 推荐先通过主菜单安装到系统，然后使用 pm 命令"
}

# 主函数
main() {
    check_existing
    echo ""
    
    create_pm_quick
    create_install_quick
    
    show_usage
    
    echo ""
    success "🎉 所有快捷脚本创建完成！"
}

main "$@"
