#!/usr/bin/env bash
#
# lib/menu.sh
#
# 主菜单、交互主循环、机器可读输出、用法文本、卸载菜单。
# 注册表驱动，不再硬编码模块列表。
#

# 幂等保护
if [[ -n "${_MENU_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_MENU_SH_LOADED=1

# ============================================================
# 系统信息
# ============================================================
show_system_info() {
    header "🖥️  系统信息"
    echo "───────────────────────────────"
    echo "操作系统: $OS_TYPE"
    echo "CPU架构:  $ARCH_TYPE"
    echo "───────────────────────────────"
    echo
}

# ============================================================
# 主菜单（注册表驱动，按分类动态生成）
# ============================================================
show_main_menu() {
    clear
    header "🚀 一键安装脚本 - 服务与环境管理工具"
    echo "========================================"
    show_system_info

    # 版本信息 + 更新检查
    local current_ver; current_ver=$(get_local_version 2>/dev/null || echo unknown)
    echo "脚本版本:      v${current_ver}"
    check_for_update 2>/dev/null || true
    if [[ "${UPDATE_AVAILABLE:-}" == "true" ]]; then
        echo -e "最新版本:      ${YELLOW}v${REMOTE_LATEST}${NC} ${YELLOW}(有更新！输入 c 检查/更新)${NC}"
    else
        echo "最新版本:      v${current_ver}（已是最新）"
    fi
    echo "───────────────────────────────"

    menu "请选择要安装的服务或配置环境："
    echo

    # 按分类动态生成菜单项
    local num=1 cat mod label has_submenu
    for cat in $CATEGORY_ORDER; do
        # 检查该分类是否有模块
        local has_any=false
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] && { has_any=true; break; }
        done
        $has_any || continue

        echo "  --- $cat ---"
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] || continue
            label=$(_reg_get "$mod" LABEL)
            has_submenu=$(_reg_get "$mod" HAS_SUBMENU)
            if [[ -n "$has_submenu" ]]; then
                printf "  %2d) %-16s - %s（子菜单）\n" "$num" "$label" "$mod"
            else
                printf "  %2d) %-16s - %s\n" "$num" "$label" "$mod"
            fi
            num=$((num + 1))
        done
        echo
    done

    echo "  --- 管理 ---"
    echo "  s) 查看已安装状态    - 检查服务和环境的安装情况"
    echo "  u) 卸载服务/环境     - 移除已安装的服务或环境"
    echo "  c) 检查更新          - 检查并更新到最新版本"
    echo "  q) 退出"
    echo
    echo "========================================"
}

# ============================================================
# 交互式主循环（注册表驱动）
# ============================================================
interactive_main() {
    while true; do
        show_main_menu
        read -r -p "请输入选项: " choice

        # 处理特殊选项
        case "$choice" in
            s|S) show_installed_services; continue ;;
            u|U)
                while true; do
                    show_uninstall_menu
                    read -r -p "请输入选项: " uninstall_choice
                    if ! do_uninstall "$uninstall_choice"; then
                        break
                    fi
                done
                continue
                ;;
            c|C)
                clear
                header "🔄 检查更新"
                echo "========================================"
                info "当前版本：v$(get_local_version)"
                if check_for_update 2>/dev/null; then
                    warn "检测到新版本：v$(get_local_version) → v${REMOTE_LATEST}"
                    if yes_no "是否立即更新？"; then
                        do_self_update
                    fi
                else
                    if [[ -n "${REMOTE_LATEST:-}" ]]; then
                        success "已是最新版本：v$(get_local_version)"
                    else
                        warn "无法获取远端版本（网络问题或未发布 release）"
                    fi
                fi
                echo
                read -r -p "按回车键返回主菜单..."
                continue
                ;;
            q|Q|0) info "感谢使用！再见！"; exit 0 ;;
        esac

        # 数字选项：通过注册表找到对应模块
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local num=1 mod
            for cat in $CATEGORY_ORDER; do
                for mod in $_REGISTRY_MODULES; do
                    [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] || continue
                    if [[ $num -eq $choice ]]; then
                        # 找到模块
                        local submenu=$(_reg_get "$mod" HAS_SUBMENU)
                        local default_action
                        default_action=$(_reg_get "$mod" DEFAULT_ACTION)
                        default_action="${default_action:-install}"
                        if [[ -n "$submenu" ]]; then
                            # 有子菜单：调用 manage_* 函数
                            "manage_${submenu}"
                        elif [[ -n "$default_action" ]]; then
                            # 直接执行默认动作
                            local action_args=($default_action)
                            run_in_dir "$mod" install.sh "${action_args[@]}"
                            echo; read -r -p "按回车键返回主菜单..."
                        fi
                        continue 3
                    fi
                    num=$((num + 1))
                done
            done
            error "无效选项，请重新输入！"; sleep 1
        else
            error "无效选项，请重新输入！"; sleep 1
        fi
    done
}

# ============================================================
# 机器可读输出（供 AI agent / 脚本解析）
# ============================================================

# --list-modules: TSV 输出模块名 + 支持的子命令
show_list_modules() {
    local mod
    for mod in $_REGISTRY_MODULES; do
        local entry_script
        entry_script=$(registry_entry_script "$mod")
        local script="$SCRIPT_DIR/$mod/$entry_script"
        [[ -f "$script" ]] || continue
        local subs=""
        local usage_line
        usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null || true)
        if [[ "$usage_line" == *"{"*"}"* ]]; then
            subs=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
        fi
        if [[ -z "$subs" ]]; then
            subs=$(grep -oE '^\s+(install|uninstall|status|help|mirror|unmirror|start|stop|restart|enable|disable|pull|all|config|example|tun-on|tun-off|clear|list|setup|route-user|route-port|save)\)' "$script" 2>/dev/null | tr -d ' )' | sort -u | tr '\n' ' ' || true)
        fi
        [[ -z "$subs" ]] && subs="install"
        printf '%s\t%s\n' "$mod" "$subs"
    done
}

# --status-json: key:value 格式输出各模块状态（无颜色、无 emoji）
show_status_json() {
    detect_os
    detect_arch
    echo "os:$OS_TYPE"
    echo "arch:$ARCH_TYPE"
    echo "version:$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"

    local mod
    for mod in $_REGISTRY_MODULES; do
        local entry_script
        entry_script=$(registry_entry_script "$mod")
        local script="$SCRIPT_DIR/$mod/$entry_script"
        [[ -f "$script" ]] || continue
        local raw
        raw=$(bash "$script" status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -1 || echo "unknown")
        local val="unknown"
        if echo "$raw" | grep -qiE '✅|已安装并运行'; then
            val="installed:running"
        elif echo "$raw" | grep -qiE '已安装但未运行|已安装，但|已安装但服务'; then
            val="installed:stopped"
        elif echo "$raw" | grep -qiE '已安装'; then
            val="installed"
        elif echo "$raw" | grep -qiE '未安装'; then
            val="not_installed"
        elif echo "$raw" | grep -qiE '不适用|仅 Linux'; then
            val="n/a"
        elif echo "$raw" | grep -qiE '已配置'; then
            val="configured"
        elif echo "$raw" | grep -qiE '未配置'; then
            val="not_configured"
        fi
        printf '%s:%s\n' "$mod" "$val"
    done
}

# ============================================================
# 卸载菜单（注册表驱动）
# ============================================================
show_uninstall_menu() {
    clear
    header "🗑️  卸载服务与环境"
    echo "========================================"
    warn "注意：卸载操作将完全移除服务及其配置文件！"
    echo

    local num=1 mod label
    for mod in $_REGISTRY_MODULES; do
        label=$(_reg_get "$mod" LABEL)
        printf "  %2d) 卸载 %s\n" "$num" "$label"
        num=$((num + 1))
    done
    echo "  0) 返回主菜单"
    echo
    echo "========================================"
}

# 处理卸载选择（注册表驱动）
do_uninstall() {
    local choice="$1"

    if [[ "$choice" == "0" ]]; then
        return 1
    fi

    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        error "无效选项，请重新输入！"; sleep 1
        return 0
    fi

    # 按注册表顺序找到对应模块
    local num=1 mod
    for mod in $_REGISTRY_MODULES; do
        if [[ $num -eq $choice ]]; then
            local label=$(_reg_get "$mod" LABEL)
            # 特殊模块处理
            case "$mod" in
                shutdown_timer)
                    uninstall_shutdown_timer
                    ;;
                process_manager_tool)
                    if yes_no "确认卸载 $label？"; then
                        info "开始卸载..."
                        run_in_dir process_manager_tool install_process_manager.sh uninstall
                    fi
                    ;;
                *)
                    if yes_no "确认卸载 $label？"; then
                        run_in_dir "$mod" install.sh uninstall
                    fi
                    ;;
            esac
            echo
            read -r -p "按回车键继续..."
            return 0
        fi
        num=$((num + 1))
    done

    error "无效选项，请重新输入！"; sleep 1
    return 0
}

# ============================================================
# 用法文本
# ============================================================
show_usage() {
    local mod_list=""
    for mod in $_REGISTRY_MODULES; do
        mod_list="$mod_list | $mod"
    done
    mod_list="${mod_list# | }"

    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help        显示本帮助
  -v, --version     显示版本
  -s, --status      查看所有模块的安装状态后退出（非交互）
  --list            列出可用模块名后退出
  --list-modules    机器可读：模块名 + 支持子命令（TSV，供 AI/脚本）
  --status-json     机器可读：模块状态 key:value（无颜色，供 AI/脚本）
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库
  cli               安装全局命令 uxs 到 ~/.tools/bin（之后可在任意目录 uxs <子命令>）
  uninstall-cli     卸载全局命令 uxs

模块名（用于非交互安装）:
  $mod_list

示例:
  $0                       # 进入交互式主菜单
  $0 --status              # 直接打印安装状态
  $0 docker                # 直接安装 docker
  $0 tailscale             # 直接安装 tailscale
  $0 check-update          # 检查是否有新版本
  $0 update                # 更新到最新版本（需确认）
  $0 cli                   # 安装全局命令 uxs（之后可 uxs docker-image 等）
EOF
}

show_noninteractive_usage() {
    show_usage
}
