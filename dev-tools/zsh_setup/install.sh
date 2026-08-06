#!/bin/bash
#
# zsh_setup/install.sh
# Zsh 环境配置管理工具
#

_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共库
source "$_INSTALL_DIR/lib/common.sh"
source "$_INSTALL_DIR/lib/framework.sh"
source "$_INSTALL_DIR/lib/plugins.sh"
source "$_INSTALL_DIR/lib/themes.sh"
source "$_INSTALL_DIR/lib/config.sh"

# 版本
VERSION="2.0.0"

# 显示帮助
show_help() {
    cat << EOF
Zsh 环境配置管理工具 v${VERSION}

用法: $0 <command> [options]

命令:
  framework              框架管理
    [name]               安装指定框架 (oh-my-zsh, prezto, zinit, sheldon)
    select               交互式选择框架

  plugin                 插件管理
    list                 列出已安装插件
    add <name> [repo]    添加插件
    remove <name>        移除插件
    sync                 同步插件更新

  theme                  主题管理
    list                 列出可用主题
    set <name>           设置主题
    p10k                 安装 Powerlevel10k

  config                 配置管理
    backup               备份配置
    restore              恢复配置
    export               导出配置
    import <file>        导入配置

  status [--json]          查看状态 (--json 输出 JSON 格式)
  help                   显示帮助信息
  version                显示版本

示例:
  $0 framework oh-my-zsh   # 安装 Oh My Zsh
  $0 plugin add zsh-autosuggestions
  $0 theme p10k            # 安装 Powerlevel10k
  $0 config backup         # 备份配置
  $0 status                # 查看状态
  $0 status --json         # 查看状态 (JSON 格式)
EOF
}

# 显示版本
show_version() {
    echo "zsh_setup v${VERSION}"
}

# 显示状态
# 用法: show_status [--json|--text]
#   --json  输出 JSON 格式
#   --text  输出纯文本格式（默认）
#
# 机器模式（UXS_STATUS_MODE=machine）契约说明：
#   - --json 模式：保持原有 JSON 输出不变（不追加 STATE=，否则会破坏 JSON 合法性）。
#     即 --json 始终输出纯 JSON，无论 UXS_STATUS_MODE 如何。
#   - --text 模式 + UXS_STATUS_MODE=machine：首行输出 STATE=<installed|not_installed>，
#     随后 EXTRA=framework=...、EXTRA=theme=...、EXTRA=backups=N；人类详情块被抑制。
#   - --text 模式 + 人类模式：与原实现字节一致。
show_status() {
    local format="${1:---text}"

    # ---- 先计算事实（不输出），供两种格式复用 ----
    local zsh_installed_bool=false
    local zsh_version=""
    if command_exists zsh; then
        zsh_installed_bool=true
        zsh_version=$(zsh --version | head -1)
    fi

    local theme="none"
    local fw
    fw=$(detect_framework)
    if [ "$fw" != "none" ]; then
        case "$fw" in
            oh-my-zsh)
                if [ -f "$HOME/.zshrc" ]; then
                    theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2)
                fi
                ;;
            prezto)
                if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                    theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}')
                fi
                ;;
        esac
    fi

    local backup_count=0
    if [ -d "$BACKUP_DIR" ]; then
        backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -name 'zsh-backup-*.tar.gz' 2>/dev/null | wc -l)
    fi

    if [ "$format" == "--json" ]; then
        # JSON 格式输出（保持原有行为；机器模式不追加 STATE=，以保 JSON 合法）
        local framework_json
        framework_json=$(framework_status --json)

        local esc_version esc_theme
        esc_version=$(json_escape "$zsh_version")
        esc_theme=$(json_escape "${theme:-none}")
        cat <<EOF
{
  "zsh": {"installed": ${zsh_installed_bool}, "version": "${esc_version}"},
  "framework": ${framework_json},
  "theme": "${esc_theme}",
  "backups": ${backup_count}
}
EOF
        return 0
    fi

    # ---- 纯文本格式 ----
    # 主状态：zsh 已安装→installed；否则 not_installed
    local state
    if $zsh_installed_bool; then
        state="installed"
    else
        state="not_installed"
    fi

    # 机器模式：先 emit STATE=，再 emit_extra，抑制人类详情块
    if uxs_is_machine_mode; then
        emit_status "$state" ""
        emit_extra "framework=${fw}"
        emit_extra "theme=${theme:-none}"
        emit_extra "backups=${backup_count}"
        return 0
    fi

    # 人类模式：与原实现字节一致
    info "Zsh 环境状态:"
    echo ""

    # Zsh 状态
    if command_exists zsh; then
        success "Zsh: 已安装 ($(zsh --version | head -1))"
    else
        warn "Zsh: 未安装"
    fi

    echo ""

    # 框架状态
    framework_status "$format"

    echo ""

    # 主题状态
    if [ "$fw" != "none" ]; then
        case "$fw" in
            oh-my-zsh)
                if [ -f "$HOME/.zshrc" ]; then
                    info "当前主题: ${theme:-未设置}"
                fi
                ;;
            prezto)
                if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                    info "当前主题: ${theme:-未设置}"
                fi
                ;;
        esac
    fi

    echo ""

    # 配置备份状态
    if [ -d "$BACKUP_DIR" ]; then
        info "配置备份: ${backup_count} 个"
    else
        info "配置备份: 无"
    fi
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        framework)
            if [ -z "$1" ] || [ "$1" == "select" ]; then
                framework_select
            else
                framework_install "$1"
            fi
            ;;
        plugin)
            local subcommand="${1:-list}"
            shift || true
            case "$subcommand" in
                list) plugin_list ;;
                add) plugin_add "$1" "$2" ;;
                remove) plugin_remove "$1" ;;
                sync) plugin_sync ;;
                *) error "未知命令: plugin $subcommand"; show_help; exit 1 ;;
            esac
            ;;
        theme)
            local subcommand="${1:-list}"
            shift || true
            case "$subcommand" in
                list) theme_list ;;
                set) theme_set "$1" ;;
                p10k) theme_install_p10k ;;
                *) error "未知命令: theme $subcommand"; show_help; exit 1 ;;
            esac
            ;;
        config)
            local subcommand="${1:-help}"
            shift || true
            case "$subcommand" in
                backup) config_backup ;;
                restore) config_restore ;;
                export) config_export ;;
                import) config_import "$1" ;;
                *) error "未知命令: config $subcommand"; show_help; exit 1 ;;
            esac
            ;;
        status)
            show_status "$1"
            ;;
        help|--help|-h)
            show_help
            ;;
        version|--version|-v)
            show_version
            ;;
        *)
            error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 如果直接运行脚本（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
