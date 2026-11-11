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
        error "$(_tf 'Framework adapter not found: %s' "$framework")"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$adapter"
}

# 安装框架
framework_install() {
    local framework="$1"

    if [ -z "$framework" ]; then
        error "$(_t 'Please specify a framework name')"
        return 1
    fi

    load_framework "$framework" || return 1

    info "$(_tf 'Installing %s...' "$framework")"
    if "install_${framework//-/_}"; then
        success "$(_tf '%s installed successfully' "$framework")"
    else
        error "$(_tf '%s failed to install' "$framework")"
        return 1
    fi
}

# 卸载框架
framework_uninstall() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        warn "$(_t 'No installed framework detected')"
        return 0
    fi

    load_framework "$framework" || return 1

    info "$(_tf 'Uninstalling %s...' "$framework")"
    if "uninstall_${framework//-/_}"; then
        success "$(_tf '%s uninstalled successfully' "$framework")"
    else
        error "$(_tf '%s failed to uninstall' "$framework")"
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
            printf '%s\n' "$(_t 'No framework installed')"
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
    cat <<EOF
用法: framework <command> [options]

$(_t 'Available commands (framework):')
  install <framework>    $(_t 'install a given framework (oh-my-zsh, prezto, zinit, sheldon)')
  uninstall              $(_t 'uninstall the current framework')
  status [--json|--text] $(_t 'show the current framework status')
  list-plugins           $(_t 'list the plugins of the current framework')
  select                 $(_t 'interactively select and install a framework')
  help                   $(_t 'show this help information')

$(_t 'Examples:')
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
        warn "$(_t 'No framework installed')"
        return 0
    fi

    load_framework "$framework" || return 1

    "list_plugins_${framework//-/_}"
}

# 交互式选择框架
framework_select() {
    printf '%s\n' "$(_t 'Available Zsh frameworks:')"
    echo "  1) Oh My Zsh - $(_t 'most popular, rich plugin ecosystem')"
    echo "  2) Prezto - $(_t 'lightweight and modular')"
    echo "  3) Zinit - $(_t 'top performance, async loading')"
    echo "  4) sheldon - $(_t 'modern, written in Rust')"
    echo ""

    read -r -p "$(_t 'Select a framework (1-4): ')" choice

    case "$choice" in
        1) framework_install "oh-my-zsh" ;;
        2) framework_install "prezto" ;;
        3) framework_install "zinit" ;;
        4) framework_install "sheldon" ;;
        *) error "$(_t 'Invalid selection')"; return 1 ;;
    esac
}
