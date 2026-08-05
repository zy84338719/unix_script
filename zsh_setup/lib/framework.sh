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
framework_status() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        echo "未安装框架"
        return 0
    fi

    load_framework "$framework" || return 1

    "status_${framework//-/_}"
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
