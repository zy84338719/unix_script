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
STEP_DESC=("zsh 本体" "Zsh + Oh My Zsh" "现代 CLI 工具集" "Nerd Font 字体" "Atuin 历史")

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

step_ready() {
    case "$1" in
        zsh)        command_exists zsh ;;
        zsh_setup)  [[ "$(machine_state zsh_setup)" == "installed" ]] ;;
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
            info "⏭ 跳过（UXS_CONFIG_EXCLUDE）: ${STEP_DESC[$i]}"
            continue
        fi
        if step_ready "$mod"; then
            success "✅ 已就绪: ${STEP_DESC[$i]}"
            continue
        fi
        info "🔧 安装: ${STEP_DESC[$i]} ..."
        if [[ "$mod" == "zsh" ]]; then
            command_exists zsh || pkg_install zsh || { error "zsh 本体安装失败"; return 1; }
        else
            bash "$(module_dir "$mod")/install.sh" install || warn "⚠️ ${STEP_DESC[$i]} 安装失败（继续后续环节）"
        fi
    done
    status_terminal_human
    success "🎉 终端全家桶完成！新开终端或 exec zsh 生效"
}

status_terminal_human() {
    local i mod mark
    echo
    info "环节状态："
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        if excluded "$mod"; then mark="⏭ 跳过"
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
        emit_status "installed" "${GREEN}✅ 终端全家桶全部就绪（${ready}/${total}）${NC}"
    else
        local csv
        csv=$(IFS=,; echo "${missing[*]}")
        if [[ $ready -gt 0 ]]; then
            emit_status "not_installed" "${YELLOW}⚠️ 部分就绪（${ready}/${total}）${NC}"
        else
            emit_status "not_installed" "${RED}❌ 未配置${NC}"
        fi
        emit_extra "missing=${csv}"
    fi
    return 0
}

uninstall_terminal() {
    warn "terminal 为编排模块，无独立卸载；请逐个子模块 uninstall："
    echo "  ./install.sh atuin uninstall && ./install.sh zsh_setup uninstall"
    echo "  rc 清理: 删除各 '# >>> unix_script <模块> >>>' 标记块"
}

usage() {
    cat <<EOF
用法: $0 {install|status|help}

  install     一键终端全家桶（zsh → zsh_setup → modern-cli → nerd-font → atuin）
              UXS_CONFIG_FRAMEWORK=oh-my-zsh      框架选择（透传 zsh_setup）
              UXS_CONFIG_THEME=p10k               主题（透传 zsh_setup）
              UXS_CONFIG_FONTS=JetBrainsMono      字体清单（透传 nerd-font）
              UXS_CONFIG_SYNC=0                   atuin 同步开关（透传 atuin）
              UXS_CONFIG_EXCLUDE=atuin,nerd-font  裁剪环节
  status      查看各环节就绪状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
