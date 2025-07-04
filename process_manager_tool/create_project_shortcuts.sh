#!/bin/bash

#
# create_project_shortcuts.sh
#
# 在项目根目录创建快捷访问脚本，方便用户快速访问各个工具
#

# --- 颜色定义 ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }

# 获取脚本所在目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info "正在创建项目快捷访问脚本..."

# 创建进程管理工具快捷脚本
cat > "$SCRIPT_DIR/pm_quick.sh" << 'EOF'
#!/bin/bash
# 快速访问进程管理工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/process_manager_tool" && bash pm_wrapper.sh "$@"
EOF

# 创建主安装脚本快捷方式
cat > "$SCRIPT_DIR/install_quick.sh" << 'EOF'
#!/bin/bash
# 快速访问主安装菜单
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" && bash install.sh "$@"
EOF

# 设置执行权限
chmod +x "$SCRIPT_DIR/pm_quick.sh"
chmod +x "$SCRIPT_DIR/install_quick.sh"

success "快捷脚本创建完成："
echo "  pm_quick.sh      - 快速访问进程管理工具"
echo "  install_quick.sh - 快速访问主安装菜单"
echo ""

info "使用方法："
echo "  ./pm_quick.sh node       # 直接搜索node进程"
echo "  ./pm_quick.sh --help     # 查看帮助"
echo "  ./pm_quick.sh --config   # 查看配置"
echo "  ./install_quick.sh       # 打开主安装菜单"
