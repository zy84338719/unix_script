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

info() { echo -e "${BLUE}[$(_t 'Info]')${NC} $1"; }
success() { echo -e "${GREEN}[$(_t 'Success]')${NC} $1"; }
warn() { echo -e "${YELLOW}[$(_t 'Warning]')${NC} $1"; }

# 获取脚本所在目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

info "$(_t 'Creating the project shortcut scripts...')"

# 创建进程管理工具快捷脚本
cat > "$SCRIPT_DIR/pm_quick.sh" << 'EOF'
#!/bin/bash
# 快速访问进程管理工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/sys-tools/process_manager_tool" && bash pm_wrapper.sh "$@"
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

success "$(_t 'The shortcut scripts have been created:')"
echo "  pm_quick.sh      - $(_t 'Quick access to the process manager')"
echo "  install_quick.sh - $(_t 'Quick access to the main install menu')"
echo ""

info "$(_t 'How to use:')"
echo "  ./pm_quick.sh node       # $(_t 'Search the node processes directly')"
echo "  ./pm_quick.sh --help     # $(_t 'View the help')"
echo "  ./pm_quick.sh --config   # $(_t 'View the configuration')"
echo "  ./install_quick.sh       # $(_t 'Open the main install menu')"
