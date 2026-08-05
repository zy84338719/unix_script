#!/bin/bash
#
# zsh_setup/lib/framework.sh
# 框架抽象层
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 加载框架适配器
load_framework() {
    local framework="$1"
    local adapter="$SCRIPT_DIR/../frameworks/${framework}.sh"

    if [ ! -f "$adapter" ]; then
        error "未找到框架适配器: $framework"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$adapter"
}

# 安装框架
framework_install() {
    local framework="$1"

    if [ -z "$framework" ]; then
        error "请指定框架名称"
        return 1
    fi

    load_framework "$framework" || return 1

    info "正在安装 $framework..."
    if "install_${framework//-/_}"; then
        success "$framework 安装成功"
    else
        error "$framework 安装失败"
        return 1
    fi
}

# 卸载框架
framework_uninstall() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        warn "未检测到已安装的框架"
        return 0
    fi

    load_framework "$framework" || return 1

    info "正在卸载 $framework..."
    if "uninstall_${framework//-/_}"; then
        success "$framework 卸载成功"
    else
        error "$framework 卸载失败"
        return 1
    fi
}

# 框架状态
# 用法: framework_status [--json|--text]
#   --json  输出 JSON 格式
#   --text  输出纯文本格式（默认）
framework_status() {
    local format="${1:---text}"
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        if [ "$format" == "--json" ]; then
            echo '{"framework": "none", "status": "not_installed"}'
        else
            echo "未安装框架"
        fi
        return 0
    fi

    load_framework "$framework" || return 1

    if [ "$format" == "--json" ]; then
        local status_text
        status_text=$("status_${framework//-/_}")
        local escaped_status
        escaped_status=$(json_escape "$status_text")
        echo "{\"framework\": \"${framework}\", \"status\": \"${escaped_status}\"}"
    else
        "status_${framework//-/_}"
    fi
}

# 帮助信息
framework_help() {
    cat <<'EOF'
用法: framework <command> [options]

可用命令:
  install <framework>    安装指定框架 (oh-my-zsh, prezto, zinit, sheldon)
  uninstall              卸载当前框架
  status [--json|--text] 显示当前框架状态
  list-plugins           列出当前框架的插件
  select                 交互式选择并安装框架
  help                   显示此帮助信息

示例:
  framework install oh-my-zsh
  framework status --json
  framework help
EOF
}

# 列出框架插件
framework_list_plugins() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi

    load_framework "$framework" || return 1

    "list_plugins_${framework//-/_}"
}

# 交互式选择框架
framework_select() {
    echo "可用的 Zsh 框架:"
    echo "  1) Oh My Zsh - 最流行，插件丰富"
    echo "  2) Prezto - 轻量级，模块化"
    echo "  3) Zinit - 性能极佳，异步加载"
    echo "  4) sheldon - 现代化，Rust 编写"
    echo ""

    read -r -p "请选择框架 (1-4): " choice

    case "$choice" in
        1) framework_install "oh-my-zsh" ;;
        2) framework_install "prezto" ;;
        3) framework_install "zinit" ;;
        4) framework_install "sheldon" ;;
        *) error "无效选择"; return 1 ;;
    esac
}
