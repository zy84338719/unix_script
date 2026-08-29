#!/usr/bin/env bash
#
# lib/scaffold.sh
#
# 模块脚手架：自动生成新模块的目录结构和模板文件。
# 用法: source 后调用 scaffold_module <module_name> [--category <cat>] [--label <label>]
#

# 幂等保护
if [[ -n "${_SCAFFOLD_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_SCAFFOLD_SH_LOADED=1

# 生成新模块
scaffold_module() {
    local name="$1"
    local category="${2:-系统工具}"
    local label="$3"

    # Validate name (lowercase, hyphens ok)
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        error "模块名只能包含小写字母、数字和连字符，且以字母开头"
        return 1
    fi

    # 根据 category 确定分类目录
    local cat_dir
    case "$category" in
        服务)     cat_dir="services" ;;
        装机必备) cat_dir="essentials" ;;
        开发环境) cat_dir="dev-tools" ;;
        AI工具)   cat_dir="ai-tools" ;;
        系统工具) cat_dir="sys-tools" ;;
        *)        cat_dir="sys-tools" ;;
    esac

    local dir="${SCRIPT_DIR:-.}/$cat_dir/$name"
    if [[ -d "$dir" ]]; then
        error "目录 $name 已存在"
        return 1
    fi

    [[ -z "$label" ]] && label="$name"

    mkdir -p "$dir"

    # .manifest
    cat > "$dir/.manifest" <<EOF
LABEL=$label
CATEGORY=$category
DESC=一句话中文描述（请替换）
DEFAULT_ACTION=install
# NEXT_STEPS=安装成功后的下一步提示;多条用分号分隔（可选，条目内冒号分隔「说明:命令」）
EOF

    # install.sh template
    cat > "$dir/install.sh" <<'TEMPLATE'
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    check_commands curl
}

install_MODULENAME() {
    preflight
    info "🚀 安装 LABEL"
    # TODO: 实现安装逻辑

    success "🎉 LABEL 安装完成！"
}

uninstall_MODULENAME() {
    detect_os
    require_sudo
    info "卸载 LABEL ..."
    # TODO: 实现卸载逻辑
    success "LABEL 已卸载"
}

status_MODULENAME() {
    detect_os
    # TODO: 实现状态检查
    echo -e "${RED}❌ 未安装${NC}"
}

usage() {
    cat <<EOF
用法: \$0 {install|uninstall|status|help}

  install     安装 LABEL（默认动作）
  uninstall   卸载 LABEL
  status      查看安装状态
  help        显示此帮助
EOF
}

main() {
    local action="\${1:-install}"
    detect_os
    case "\$action" in
        install)   install_MODULENAME ;;
        uninstall) uninstall_MODULENAME ;;
        status)    status_MODULENAME ;;
        help|--help|-h) usage ;;
        *) error "未知操作: \$action"; usage; exit 1 ;;
    esac
}

if [[ "\${BASH_SOURCE[0]}" == "\${0}" ]]; then
    main "\$@"
fi
TEMPLATE

    # Replace placeholders in template
    local safe_name="${name//-/_}"
    sed -i.bak "s/MODULENAME/$safe_name/g" "$dir/install.sh"
    sed -i.bak "s/LABEL/$label/g" "$dir/install.sh"
    rm -f "$dir/install.sh.bak"
    chmod +x "$dir/install.sh"

    # README.md
    cat > "$dir/README.md" <<EOF
# $label

TODO: 模块说明

## 支持平台

- ✅ Linux
- ✅ macOS

## 子命令

| 子命令 | 说明 |
|--------|------|
| \`install\` | 安装（默认动作） |
| \`uninstall\` | 卸载 |
| \`status\` | 查看状态 |
| \`help\` | 帮助信息 |

## 快速开始

\`\`\`bash
./install.sh $name
./install.sh $name status
\`\`\`
EOF

    success "模块 $name 已创建：$cat_dir/$name/"
    info "文件："
    echo "  $cat_dir/$name/.manifest"
    echo "  $cat_dir/$name/install.sh"
    echo "  $cat_dir/$name/README.md"
    echo
    info "下一步："
    echo "  0. 编辑 $cat_dir/$name/.manifest 的 DESC 为一句话中文描述"
    echo "  1. 编辑 $cat_dir/$name/install.sh 实现安装逻辑"
    echo "  2. 更新 README.md"
    echo "  3. 运行 ./tests/ci_run.sh --phase static 检查语法"
}
