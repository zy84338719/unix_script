#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/atuin/install.sh
#
# Atuin：SQLite 化 shell 历史（全量模糊搜索、跨机端到端加密同步）。
# 默认纯本地（UXS_CONFIG_SYNC=0）；UXS_CONFIG_SYNC=1 时提示用户自行注册（不代注册）。
#
# 子命令：install | sync | uninstall | status | help
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

MARK="# >>> unix_script atuin >>>"
ENDMARK="# <<< unix_script atuin <<<"

atuin_bin() {
    if command_exists atuin; then
        command -v atuin
    elif [[ -x "$HOME/.atuin/bin/atuin" ]]; then
        echo "$HOME/.atuin/bin/atuin"
    else
        return 1
    fi
}

install_atuin() {
    detect_os
    if ! atuin_bin >/dev/null; then
        if [[ "$OS_TYPE" == "darwin" ]]; then
            command_exists brew || { error "macOS $(_t 'Homebrew is required')"; return 1; }
            brew install atuin
        else
            if ! pkg_install atuin >/dev/null 2>&1; then
                # 信任模型：setup.atuin.sh 为官方安装器（HTTPS），装到 $HOME/.atuin/bin（实测）
                local ver
                ver=$(github_latest_tag "atuinsh/atuin" 2>/dev/null || echo "latest")
                info "$(_tf 'The repository has no atuin package, using the official script (target version: %s)...' "${ver}")"
                curl -fsSL https://setup.atuin.sh | sh || { error "atuin $(_t 'Installation failed')"; return 1; }
            fi
        fi
    fi
    atuin_bin >/dev/null || { error "atuin $(_t 'Still not available')"; return 1; }

    configure_rc
    import_history

    if [[ "${UXS_CONFIG_SYNC:-0}" == "1" ]]; then
        info "$(_t 'Configured with UXS_CONFIG_SYNC=1: run atuin register to register an account (interactive, you have to do it yourself)')"
        info "$(_t 'On other machines, run atuin login <username> && atuin sync to sync the history')"
    fi
    success "$(_tf '🎉 Atuin installation complete (sync=%s)' "${UXS_CONFIG_SYNC:-0}")"
    info "$(_t 'Open a new terminal or run exec zsh to take effect; Ctrl+R becomes the full fuzzy search of Atuin')"
}

configure_rc() {
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [[ -f "$rc" ]] || continue
        grep -q "$MARK" "$rc" 2>/dev/null && continue
        {
            echo ""
            echo "$MARK"
            [[ -x "$HOME/.atuin/bin/atuin" ]] && echo "export PATH=\"\$HOME/.atuin/bin:\$PATH\""
            echo "command -v atuin >/dev/null 2>&1 && eval \"\$(atuin init \$(basename \$SHELL))\""
            echo "$ENDMARK"
        } >> "$rc"
        info "$(_tf 'Added the atuin integration for %s' "$(basename "$rc")")"
    done
}

import_history() {
    # 首次安装时迁移旧历史；标记文件保证幂等
    local flag="$HOME/.config/atuin/.uxs_imported"
    [[ -f "$flag" ]] && return 0
    if "$(atuin_bin)" import auto >/dev/null 2>&1; then
        info "$(_t 'The old shell history has been imported into atuin')"
    else
        warn "$(_t 'Importing the old history failed (you can run it manually later: atuin import auto)')"
    fi
    mkdir -p "$(dirname "$flag")"
    touch "$flag"
}

cmd_sync() {
    if [[ "${UXS_CONFIG_SYNC:-0}" != "1" ]]; then
        warn "$(_t 'Currently in pure local mode (UXS_CONFIG_SYNC is not enabled), no sync needed')"
        return 0
    fi
    "$(atuin_bin)" sync
}

uninstall_atuin() {
    detect_os
    warn "atuin $(_t 'Uninstall instructions:')"
    echo "  $(_t 'Program: brew uninstall atuin or sudo <pkgmgr> remove atuin')"
    # shellcheck disable=SC2016  # 译文里的 $HOME 是要原样打印的字面量，不能展开
    echo "  $(_t 'Installed by script: rm -rf ~/.atuin (and remove $HOME/.atuin/bin from the PATH line in rc)')"
    echo "  shell:  $(_tf 'Delete the %s marker block in rc' "$MARK")"
    echo "  $(_t 'Data: rm -rf ~/.local/share/atuin ~/.config/atuin')"
    info "$(_t '(clean it up manually as needed)')"
}

status_atuin() {
    if atuin_bin >/dev/null; then
        local sync="off"
        grep -qs "$MARK" "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null && sync="on"
        emit_status "installed" "${GREEN}$(_tf '✅ atuin is installed (shell integration: %s)' "${sync}")${NC}"
        emit_extra "sync=$sync"
        local ver
        # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE(141)；grep 无匹配时退出 1。
        # 两者在 pipefail 下都会让整条管道非 0，set -e 会让 status 子命令整体中止
        # （违反「状态子命令恒 0」契约）。改用 sed 取首行（sed 读完整个输入才退出），
        # 取不到版本号就回落成空值。
        ver=$(atuin_bin --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | sed -n '1p') || ver=""
        # 收尾用 if 而不是 `[[ -n "$ver" ]] && ...`：后者在版本号为空时返回 1。
        if [[ -n "$ver" ]]; then
            emit_version "$ver"
        fi
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
    return 0
}

usage() {
    cat <<EOF
用法: $0 {install|sync|uninstall|status|help}

  install     $(_t 'Install atuin + rc integration + import the old history (UXS_CONFIG_SYNC=1 turns on the sync hint)')
  sync        $(_t 'Sync manually (sync must be enabled and the account registered)')
  uninstall   $(_t 'Show the uninstall instructions')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_atuin ;;
        sync)      cmd_sync ;;
        uninstall) uninstall_atuin ;;
        status)    status_atuin ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
