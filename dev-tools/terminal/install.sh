#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/terminal/install.sh
#
# 终端全家桶编排：按序调用同级子模块，逐步幂等跳过已就绪环节。
# 不走阶段 E REQUIRES——REQUIRES 自动装依赖无法传递框架/字体偏好，必须自编排带参调用。
# UXS_CONFIG_EXCLUDE=zsh_setup,atuin 可裁剪环节；UXS_CONFIG_* 经进程继承透传给子模块。
#
# 子命令：install | status | help
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 编排顺序即依赖顺序
STEPS=(zsh zsh_setup modern-cli nerd-font atuin)
STEP_DESC=("zsh $(_t 'the core')" "Zsh + Oh My Zsh" "$(_t 'modern CLI toolset')" "Nerd Font $(_t 'the font')" "Atuin $(_t 'the history')")

module_dir() { echo "$SCRIPT_DIR/../$1"; }

excluded() {
    local e IFS=,
    for e in ${UXS_CONFIG_EXCLUDE:-}; do
        [[ "$e" == "$1" ]] && return 0
    done
    return 1
}

# 调子模块机器模式 status，取首个 STATE=
machine_state() {
    ( cd "$(module_dir "$1")" && UXS_STATUS_MODE=machine bash ./install.sh status </dev/null 2>/dev/null ) \
        | sed -n 's/^STATE=//p' | head -1
}

# 取子模块机器模式 status 的某个 EXTRA=<key>= 值
machine_extra() {
    ( cd "$(module_dir "$1")" && UXS_STATUS_MODE=machine bash ./install.sh status </dev/null 2>/dev/null ) \
        | sed -n "s/^EXTRA=$2=//p" | head -1
}

step_ready() {
    case "$1" in
        zsh) os_has_cmd zsh ;;
        zsh_setup)
            # STATE 只反映 zsh 本体；框架未选（none）视为未就绪，否则会跳过框架安装
            [[ "$(machine_state zsh_setup)" == "installed" ]] \
                && [[ "$(machine_extra zsh_setup framework)" != "none" ]] ;;
        modern-cli) [[ "$(machine_state modern-cli)" == "installed" ]] ;;
        nerd-font)  [[ "$(machine_state nerd-font)" == "installed" ]] ;;
        atuin)      [[ "$(machine_state atuin)" == "installed" ]] ;;
        *) return 1 ;;
    esac
}

install_terminal() {
    detect_os
    local i mod
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        if excluded "$mod"; then
            info "$(_tf '⏭ skipped (UXS_CONFIG_EXCLUDE): %s' "${STEP_DESC[$i]}")"
            continue
        fi
        if step_ready "$mod"; then
            success "$(_tf '✅ ready: %s' "${STEP_DESC[$i]}")"
            continue
        fi
        info "$(_tf '🔧 installing: %s ...' "${STEP_DESC[$i]}")"
        if [[ "$mod" == "zsh" ]]; then
            os_has_cmd zsh || pkg_install zsh || { error "zsh $(_t 'the core installation failed')"; return 1; }
        else
            bash "$(module_dir "$mod")/install.sh" install || warn "$(_tf '⚠️ %s installation failed (continue with the remaining steps)' "${STEP_DESC[$i]}")"
        fi
    done
    status_terminal_human
    success "$(_t '🎉 the terminal suite is complete! Open a new terminal or run exec zsh to take effect')"
}

status_terminal_human() {
    local i mod mark
    echo
    info "$(_t 'step status:')"
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        if excluded "$mod"; then mark="$(_t '⏭ skipped')"
        elif step_ready "$mod"; then mark="✅"
        else mark="❌"; fi
        echo "  $mark ${STEP_DESC[$i]}"
    done
}

status_terminal() {
    detect_os
    local i mod missing=() ready=0 total=0
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        excluded "$mod" && continue
        total=$((total + 1))
        if step_ready "$mod"; then
            ready=$((ready + 1))
        else
            missing+=("$mod")
        fi
    done
    if [[ $ready -eq $total ]]; then
        uxs_emit_status "installed" "${GREEN}$(_tf '✅ the whole terminal suite is ready (%s/%s)' "${ready}" "${total}")${NC}"
    else
        local csv
        csv=$(IFS=,; echo "${missing[*]}")
        if [[ $ready -gt 0 ]]; then
            uxs_emit_status "not_installed" "${YELLOW}$(_tf '⚠️ partially ready (%s/%s)' "${ready}" "${total}")${NC}"
        else
            uxs_emit_status "not_installed" "${RED}$(_t '❌ not configured')${NC}"
        fi
        uxs_emit_extra "missing=${csv}"
    fi
    return 0
}

uninstall_terminal() {
    warn "terminal $(_t 'This is an orchestration module and has no standalone uninstall; please uninstall the sub-modules one by one:')"
    echo "  ./install.sh atuin uninstall && ./install.sh zsh_setup uninstall"
    echo "  rc $(_t 'cleanup: delete the marker blocks marked with # >>> unix_script <module> >>>')"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'one-click terminal suite (zsh → zsh_setup → modern-cli → nerd-font → atuin)')
              UXS_CONFIG_FRAMEWORK=oh-my-zsh      $(_t 'framework choice (passed through to zsh_setup)')
              UXS_CONFIG_THEME=p10k               $(_t 'theme (passed through to zsh_setup)')
              UXS_CONFIG_FONTS=JetBrainsMono      $(_t 'font list (passed through to nerd-font)')
              UXS_CONFIG_SYNC=0                   atuin $(_t 'sync switch (passed through to atuin)')
              UXS_CONFIG_EXCLUDE=atuin,nerd-font  $(_t 'exclude steps')
  status      $(_t 'view the ready status of each step')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_terminal ;;
        status)    status_terminal ;;
        uninstall) uninstall_terminal ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
