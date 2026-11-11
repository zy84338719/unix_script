#!/bin/bash
set -euo pipefail
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
$(_t 'Zsh environment configuration tool') v${VERSION}

用法: $0 <command> [options]

$(_t 'Commands (zsh setup):')
  framework              $(_t 'framework management')
    [name]               $(_t 'install a given framework (oh-my-zsh, prezto, zinit, sheldon)')
    select               $(_t 'interactively select a framework')

  plugin                 $(_t 'plugin management')
    list                 $(_t 'list installed plugins')
    add <name> [repo]    $(_t 'add a plugin')
    remove <name>        $(_t 'remove a plugin')
    sync                 $(_t 'sync plugin updates')

  theme                  $(_t 'theme management')
    list                 $(_t 'list available themes')
    set <name>           $(_t 'set the theme')
    p10k                 $(_t 'install Powerlevel10k')

  config                 $(_t 'config management')
    backup               $(_t 'back up the config')
    restore              $(_t 'restore the config')
    export               $(_t 'export the config')
    import <file>        $(_t 'import the config')

  status [--json]          $(_t 'view status (--json prints JSON)')
  help                   $(_t 'show help information')
  version                $(_t 'show the version')

$(_t 'Examples:')
  $0 framework oh-my-zsh   $(_t '# install Oh My Zsh')
  $0 plugin add zsh-autosuggestions
  $0 theme p10k            $(_t '# install Powerlevel10k')
  $0 config backup         $(_t '# back up the config')
  $0 status                $(_t '# view status')
  $0 status --json         $(_t '# view status (JSON format)')
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
        # 不用 `| head -1`：head 命中即退会提前关管道，上游 zsh 被打成 SIGPIPE(141)；
        # `zsh --version` 失败时 pipefail 会把非 0 带出，set -e 让 status 子命令中止
        # （违反「状态子命令恒 0」契约）。改用 sed 取首行（读完整个输入才退出），
        # 取不到就回落成空串。
        zsh_version=$(zsh --version | sed -n '1p') || zsh_version=""
    fi

    local theme="none"
    local fw
    fw=$(detect_framework)
    if [ "$fw" != "none" ]; then
        case "$fw" in
            oh-my-zsh)
                if [ -f "$HOME/.zshrc" ]; then
                    # grep 未匹配返回 1，pipefail 下会触发 set -e；用 || true 兜底（theme 留空）
                    theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2 || true)
                fi
                ;;
            prezto)
                if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                    theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}' || true)
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
        emit_version "$VERSION"
        emit_extra "framework=${fw}"
        emit_extra "theme=${theme:-none}"
        emit_extra "backups=${backup_count}"
        return 0
    fi

    # 人类模式：与原实现字节一致
    info "$(_t 'Zsh environment status:')"
    echo ""

    # Zsh 状态
    if command_exists zsh; then
        success "$(_t 'Zsh: installed') ($(zsh --version | head -1))"
    else
        warn "$(_t 'Zsh: not installed')"
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
                    info "$(_t 'Current theme:') ${theme:-$(_t 'not set')}"
                fi
                ;;
            prezto)
                if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                    info "$(_t 'Current theme:') ${theme:-$(_t 'not set')}"
                fi
                ;;
        esac
    fi

    echo ""

    # 配置备份状态
    if [ -d "$BACKUP_DIR" ]; then
        info "$(_tf 'Config backups: %s' "${backup_count}")"
    else
        info "$(_t 'Config backups: none')"
    fi
}

# 卸载：移除已安装的框架 + 本工具配置目录。
# 各框架卸载器（uninstall_oh_my_zsh / uninstall_prezto / ...）自行清理其 .zshrc 片段；
# zsh_setup 未用统一标记写入 .zshrc，故残留行需用户手动复查。
uninstall_zsh_setup() {
    info "$(_t 'Uninstalling zsh_setup...')"
    # set -e 下 framework_uninstall 失败需捕获，不能直接中止整个卸载流程
    if framework_uninstall; then
        :
    else
        warn "$(_t 'Framework uninstall did not fully succeed (see the output above)')"
    fi
    local cfg_dir="$HOME/.config/zsh_setup"
    if [ -d "$cfg_dir" ]; then
        rm -rf "$cfg_dir"
        success "$(_tf 'Removed config directory: %s' "$cfg_dir")"
    else
        info "$(_tf 'Config directory not found: %s (nothing to clean up)' "${cfg_dir}")"
    fi
    warn "$(_t 'To fully restore zsh, check ~/.zshrc for leftover config lines')"
}

# 非交互默认安装（DEFAULT_ACTION=install 的实现）：
# zsh 本体 → 框架(UXS_CONFIG_FRAMEWORK, 默认 oh-my-zsh) → 基础插件 4 件套(仅 oh-my-zsh)
# → 主题(UXS_CONFIG_THEME, 默认随框架; p10k 走 theme_install_p10k)
install_zsh_setup_default() {
    local framework="${UXS_CONFIG_FRAMEWORK:-oh-my-zsh}"
    local theme="${UXS_CONFIG_THEME:-}"

    if ! command_exists zsh; then
        info "$(_t 'Installing zsh...')"
        if ! pkg_install zsh; then
            error "$(_t 'Failed to install zsh (install zsh manually and retry)')"
            return 1
        fi
    fi

    framework_install "$framework"

    # 基础插件：默认框架 oh-my-zsh 提供幂等的目录判断；
    # 其他框架（prezto/zinit/sheldon）插件目录约定各异，提示用户用 plugin add 自行管理
    if [ "$framework" = "oh-my-zsh" ]; then
        local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        local p
        for p in zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search; do
            if [ -d "$custom_dir/plugins/$p" ]; then
                info "$(_tf 'Plugin already exists: %s' "$p")"
            else
                plugin_add "$p" || warn "$(_tf 'Plugin install failed: %s (retry later with plugin add %s)' "${p}" "${p}")"
            fi
        done
    else
        info "$(_tf 'For framework %s, add basic plugins with: %s plugin add <name>' "$framework" "$0")"
    fi

    case "$theme" in
        # 框架默认主题，不动作
        ""|robbyrussell) : ;;
        p10k|powerlevel10k) theme_install_p10k ;;
        *) theme_set "$theme" ;;
    esac

    success "$(_tf '🎉 zsh_setup default install complete (framework: %s)' "${framework}")"
    info "$(_t 'New terminal or exec zsh to apply')"
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        install)
            install_zsh_setup_default
            ;;
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
                *) error "$(_tf 'Unknown command: plugin %s' "$subcommand")"; show_help; exit 1 ;;
            esac
            ;;
        theme)
            local subcommand="${1:-list}"
            shift || true
            case "$subcommand" in
                list) theme_list ;;
                set) theme_set "$1" ;;
                p10k) theme_install_p10k ;;
                *) error "$(_tf 'Unknown command: theme %s' "$subcommand")"; show_help; exit 1 ;;
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
                *) error "$(_tf 'Unknown command: config %s' "$subcommand")"; show_help; exit 1 ;;
            esac
            ;;
        status)
            show_status "${1:-}"
            ;;
        uninstall)
            uninstall_zsh_setup
            ;;
        help|--help|-h)
            show_help
            ;;
        version|--version|-v)
            show_version
            ;;
        *)
            error "$(_tf 'Unknown command: %s' "$command")"
            show_help
            exit 1
            ;;
    esac
}

# 如果直接运行脚本（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
