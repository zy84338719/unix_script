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
# 交互菜单（UX 改造）：两级分类导航 + 多选 + 过滤 + 状态图标
# fzf 可用时由 menu_fzf.sh 的 menu_fzf_main 接管（见 interactive_main 分派）。
# ============================================================

# 菜单模式解析：UXS_MENU=fzf|bash 强制；auto=有 fzf 用 fzf；强制 fzf 缺失时回退 bash
resolve_menu_mode() {
    local mode="${UXS_MENU:-auto}"
    case "$mode" in
        fzf)
            if command -v fzf >/dev/null 2>&1; then
                echo "fzf"
            else
                warn "UXS_MENU=fzf 但未检测到 fzf，回退 bash 菜单（安装：brew install fzf / apt install fzf）"
                echo "bash"
            fi
            ;;
        bash) echo "bash" ;;
        *)
            if command -v fzf >/dev/null 2>&1; then echo "fzf"; else echo "bash"; fi
            ;;
    esac
}

# 错误提示：不清屏、不 sleep（保留现场，用户看得到错在哪）
menu_error() {
    error "$1"
}

# ---------------- 首页与分类页渲染（纯函数，可测） ----------------

render_main_page() {
    clear 2>/dev/null || true
    header "🚀 一键安装脚本 - 服务与环境管理工具"
    echo "========================================"
    show_system_info
    local current_ver
    current_ver=$(get_local_version 2>/dev/null || echo unknown)
    echo "脚本版本:      v${current_ver}"
    if [[ "${UPDATE_AVAILABLE:-}" == "true" ]]; then
        echo -e "最新版本:      ${YELLOW}v${REMOTE_LATEST:-?}${NC} ${YELLOW}(有更新！输入 c 检查/更新)${NC}"
    else
        echo "最新版本:      v${current_ver}（已是最新）"
    fi
    echo "───────────────────────────────"
    menu "请选择分类："
    echo
    local n=1 cat mods installed=0 total=0 mod state
    for cat in $CATEGORY_ORDER; do
        mods=$(registry_modules_in_category "$cat")
        if [[ -z "$mods" ]]; then continue; fi
        total=0; installed=0
        for mod in $mods; do
            total=$((total + 1))
            state=$(status_state_get "$mod")
            case "$state" in
                installed*|configured) installed=$((installed + 1)) ;;
            esac
        done
        printf "  %d) %s（%d/%d 已装）\n" "$n" "$cat" "$installed" "$total"
        n=$((n + 1))
    done
    echo
    echo "  --- 管理 ---"
    echo "  s) 查看已安装状态"
    echo "  u) 卸载服务/环境"
    echo "  c) 检查更新"
    echo "  f) 刷新状态缓存"
    echo "  q) 退出"
    echo
    echo "========================================"
}

# ============================================================
# 分类页渲染与条目（纯函数，可测；序号即 category_items 顺序，二者必须同序）
# ============================================================

# 分类页条目（空格分隔模块名）；filter 非空时按 模块名/LABEL/DESC 子串过滤（大小写不敏感）
category_items() {
    local cat="$1" filter="$2" mod label desc hay out=""
    local lf
    lf=$(printf '%s' "$filter" | tr '[:upper:]' '[:lower:]')
    for mod in $(registry_modules_in_category "$cat"); do
        if [[ -n "$lf" ]]; then
            label=$(_reg_get "$mod" LABEL)
            desc=$(registry_desc "$mod")
            hay=$(printf '%s %s %s' "$mod" "$label" "$desc" | tr '[:upper:]' '[:lower:]')
            if [[ "$hay" != *"$lf"* ]]; then continue; fi
        fi
        out="$out $mod"
    done
    echo "${out# }"
}

render_category_page() {
    local cat="$1" filter="$2"
    clear 2>/dev/null || true
    header "📁 ${cat}"
    echo "========================================"
    if [[ -n "$filter" ]]; then
        echo "过滤: /${filter}（输入 / 清空过滤）"
        echo "───────────────────────────────"
    fi
    local mods n=1 mod label desc state icon marker
    mods=$(category_items "$cat" "$filter")
    if [[ -z "$mods" ]]; then
        warn "无匹配模块"
    fi
    for mod in $mods; do
        label=$(_reg_get "$mod" LABEL)
        desc=$(registry_desc "$mod")
        state=$(status_state_get "$mod")
        icon=$(status_icon "$state")
        marker=""
        if [[ -n "$(_reg_get "$mod" HAS_SUBMENU)" ]]; then
            marker="（子菜单）"
        fi
        printf "  %2d) %s %-18s %-22s %s%s\n" "$n" "$icon" "$mod" "$label" "$desc" "$marker"
        n=$((n + 1))
    done
    echo
    echo "───────────────────────────────"
    echo "  b) 返回上级    （多选示例: 1,3,5-8；过滤示例: /vpn）"
    echo "========================================"
}

# ============================================================
# 动作执行（bash 菜单与 fzf 菜单共用）
# ============================================================
menu_exec_actions() {
    local mods=("$@") mod submenu path entry default_action
    if [[ ${#mods[@]} -eq 0 ]]; then return 0; fi
    for mod in "${mods[@]}"; do
        submenu=$(_reg_get "$mod" HAS_SUBMENU)
        if [[ -n "$submenu" ]]; then
            if [[ ${#mods[@]} -gt 1 ]]; then
                warn "${mod} 需进入子菜单操作，已跳过（请单独选择）"
                continue
            fi
            # 入口函数名必须为 manage_<HAS_SUBMENU>（见 lib/submenus.sh 头注）；
            # declare -F 兜底：缺失时报错跳过，而非 set -e 下 127 使整个菜单退出
            if declare -F "manage_${submenu}" >/dev/null 2>&1; then
                "manage_${submenu}"
            else
                menu_error "子菜单入口缺失：manage_${submenu}（应在 lib/submenus.sh 定义）"
            fi
            break
        fi
        default_action=$(registry_default_action "$mod")
        local -a action_args
        read -ra action_args <<< "$default_action"
        if [[ "${action_args[0]:-}" == "install" ]]; then
            ensure_module_deps "$mod"
        fi
        path=$(registry_path "$mod")
        entry=$(registry_entry_script "$mod")
        run_in_dir "$path" "$entry" "${action_args[@]}"
        status_state_refresh "$mod"
    done
    echo
    read -r -p "按回车键返回..."
}

# ============================================================
# 主循环与页面循环
# ============================================================

menu_check_update() {
    clear 2>/dev/null || true
    header "🔄 检查更新"
    echo "========================================"
    info "当前版本：v$(get_local_version)"
    if check_for_update 2>/dev/null; then
        warn "检测到新版本：v$(get_local_version) → v${REMOTE_LATEST:-?}"
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
}

interactive_main() {
    local mode
    mode=$(resolve_menu_mode)
    if [[ "$mode" == "fzf" ]] && type menu_fzf_main >/dev/null 2>&1; then
        menu_fzf_main
        return $?
    fi
    interactive_main_bash
}

interactive_main_bash() {
    menu_status_ensure
    local page="main" cur_cat="" choice cats c n found
    while true; do
        if [[ "$page" == "main" ]]; then
            render_main_page
            # 内层读循环：错误输入不重绘，保留现场
            while true; do
                read -r -p "请输入选项: " choice
                case "$choice" in
                    s|S) show_installed_services; break ;;
                    u|U) uninstall_menu_loop; break ;;
                    c|C) menu_check_update; break ;;
                    f|F)
                        info "刷新安装状态..."
                        # shellcheck disable=SC2086  # $_REGISTRY_MODULES 为受控模块名列表
                        status_batch_query $_REGISTRY_MODULES
                        status_cache_save
                        success "状态缓存已刷新"
                        break
                        ;;
                    q|Q|0) info "感谢使用！再见！"; exit 0 ;;
                    ''|*[!0-9]*) menu_error "无效选项: ${choice:-（空）}"; continue ;;
                    *)
                        cats=$(registry_categories)
                        n=1; found=""
                        for c in $cats; do
                            if [[ $n -eq "$choice" ]]; then found="$c"; break; fi
                            n=$((n + 1))
                        done
                        if [[ -n "$found" ]]; then
                            cur_cat="$found"; page="cat"
                            break
                        fi
                        menu_error "无效选项: $choice（共 ${n} 个分类）"
                        continue
                        ;;
                esac
            done
        else
            category_page_loop "$cur_cat"
            page="main"
        fi
    done
}

category_page_loop() {
    local cat="$1" filter="" input items max nums
    while true; do
        render_category_page "$cat" "$filter"
        while true; do
            read -r -p "请输入编号（支持 1,3,5-8，/关键字 过滤，b 返回）: " input
            case "$input" in
                b|B|0) return 0 ;;
                /*)
                    filter="${input#/}"
                    break   # 变更过滤 → 重绘
                    ;;
                "")
                    continue   # 空输入忽略，不重绘
                    ;;
                *[!0-9,-]*)
                    menu_error "无效输入: $input"
                    continue
                    ;;
                *)
                    items=$(category_items "$cat" "$filter")
                    max=$(printf '%s' "$items" | wc -w)
                    if [[ "$max" -eq 0 ]]; then
                        menu_error "当前列表为空"
                        continue
                    fi
                    if ! nums=$(parse_multiselect "$input" "$max"); then
                        menu_error "无效编号: $input（范围 1-${max}）"
                        continue
                    fi
                    local -a sel mods
                    read -ra sel <<< "$nums"
                    mods=()
                    local idx m i=1
                    for m in $items; do
                        for idx in "${sel[@]}"; do
                            if [[ "$idx" -eq "$i" ]]; then
                                mods+=("$m")
                            fi
                        done
                        i=$((i + 1))
                    done
                    menu_exec_actions "${mods[@]}"
                    break   # 执行完毕 → 重绘
                    ;;
            esac
        done
    done
}

# ============================================================
# 机器可读输出（供 AI agent / 脚本解析）
# ============================================================

# 模块支持的子命令（空格分隔）：先解析入口脚本 usage 行的 {a|b|c} 枚举，
# 回退扫描 case 分支的已知子命令词表；最终兜底 "install"。
module_subcommands() {
    local mod="$1"
    local entry_script mod_path script subs usage_line
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo ""; return 0; }
    subs=""
    usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null || true)
    if [[ "$usage_line" == *"{"*"}"* ]]; then
        subs=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
    fi
    if [[ -z "$subs" ]]; then
        subs=$(grep -oE '^\s+(install|uninstall|status|help|mirror|unmirror|start|stop|restart|enable|disable|pull|all|config|example|tun-on|tun-off|clear|list|setup|route-user|route-port|save)\)' "$script" 2>/dev/null | tr -d ' )' | sort -u | tr '\n' ' ' || true)
    fi
    [[ -z "$subs" ]] && subs="install"
    echo "$subs"
}

# --list-modules: TSV 输出模块名 + 支持子命令 + 描述（第 3 列）
show_list_modules() {
    local mod line reqs desc
    for mod in $_REGISTRY_MODULES; do
        local entry_script mod_path
        entry_script=$(registry_entry_script "$mod")
        mod_path=$(registry_path "$mod")
        local script="$SCRIPT_DIR/$mod_path/$entry_script"
        [[ -f "$script" ]] || continue
        line=$(module_subcommands "$mod")
        # 阶段 E：有 REQUIRES 时追加 requires: 列（逗号分隔），便于 AI/人类识别前置依赖
        reqs=$(registry_requires "$mod")
        [[ -n "$reqs" ]] && line="$line  requires:${reqs// /,}"
        # UX：末尾追加描述列（第 3 列，供人类/AI 识别模块用途；前两列语义不变）
        desc=$(registry_desc "$mod")
        printf '%s\t%s\t%s\n' "$mod" "$line" "$desc"
    done
}

# --list-categories: 按分类列出所有模块
show_list_categories() {
    local cat mod label
    for cat in $CATEGORY_ORDER; do
        local has_any=false
        local items=""
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] || continue
            has_any=true
            label=$(_reg_get "$mod" LABEL)
            items="$items $mod($label)"
        done
        $has_any || continue
        echo "[$cat]"
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] || continue
            label=$(_reg_get "$mod" LABEL)
            echo "  $mod	$label"
        done
        echo
    done
}

# --status-json: key:value 格式输出各模块状态（无颜色、无 emoji）
# 单模块故障（status 崩溃/超时/输出为空）不影响整体输出：批查恒定回填 unknown
show_status_json() {
    detect_os
    detect_arch
    echo "os:$OS_TYPE"
    echo "arch:$ARCH_TYPE"
    echo "version:$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"

    local mod state version line
    # shellcheck disable=SC2086  # $_REGISTRY_MODULES 为受控模块名列表，需要分词
    status_batch_query $_REGISTRY_MODULES
    for mod in $_REGISTRY_MODULES; do
        state=$(status_state_get "$mod")
        [[ -z "$state" ]] && state="unknown"
        version=$(_uxs_version_get "$mod")
        line="$mod:$state"
        [[ -n "$version" ]] && line="$line:$version"
        printf '%s\n' "$line"
    done
}

# ============================================================
# 卸载菜单（两级导航 + 状态图标）
# ============================================================
uninstall_menu_loop() {
    menu_status_ensure
    local page="main" cur_cat="" choice cats c n found input items max m i mod
    while true; do
        if [[ "$page" == "main" ]]; then
            clear 2>/dev/null || true
            header "🗑️  卸载服务与环境"
            echo "========================================"
            warn "注意：卸载操作将完全移除服务及其配置文件！"
            echo
            menu "请选择分类："
            echo
            n=1
            cats=$(registry_categories)
            for c in $cats; do
                if [[ -n "$(registry_modules_in_category "$c")" ]]; then
                    printf "  %d) %s\n" "$n" "$c"
                    n=$((n + 1))
                fi
            done
            echo "  0) 返回主菜单"
            echo
            echo "========================================"
            read -r -p "请输入选项: " choice
            if [[ "$choice" == "0" ]]; then return 0; fi
            if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
                menu_error "无效选项: $choice"
                continue
            fi
            n=1; found=""
            for c in $cats; do
                if [[ -n "$(registry_modules_in_category "$c")" ]]; then
                    if [[ $n -eq "$choice" ]]; then found="$c"; break; fi
                    n=$((n + 1))
                fi
            done
            if [[ -z "$found" ]]; then
                menu_error "无效选项: $choice"
                continue
            fi
            cur_cat="$found"; page="cat"
        else
            clear 2>/dev/null || true
            header "🗑️  卸载 · ${cur_cat}"
            echo "========================================"
            items=$(registry_modules_in_category "$cur_cat")
            max=$(printf '%s' "$items" | wc -w)
            i=1
            for m in $items; do
                printf "  %2d) %s %-18s %s\n" "$i" "$(status_icon "$(status_state_get "$m")")" "$m" "$(_reg_get "$m" LABEL)"
                i=$((i + 1))
            done
            echo "  0) 返回上级"
            echo "========================================"
            read -r -p "请输入要卸载的编号: " input
            if [[ "$input" == "0" ]]; then page="main"; continue; fi
            if ! [[ "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 || "$input" -gt "$max" ]]; then
                menu_error "无效编号: $input"
                continue
            fi
            i=1; mod=""
            for m in $items; do
                if [[ $i -eq "$input" ]]; then mod="$m"; break; fi
                i=$((i + 1))
            done
            local entry
            entry=$(registry_entry_script "$mod")
            if yes_no "确认卸载 $(_reg_get "$mod" LABEL)？"; then
                info "开始卸载..."
                run_in_dir "$(registry_path "$mod")" "$entry" uninstall
                status_state_refresh "$mod"
            fi
            echo
            read -r -p "按回车键继续..."
        fi
    done
}

# ============================================================
# 用法文本
# ============================================================
# show_search_results <关键字...> — search 子命令展示（批次③）。
# 人类模式按分类分组：<模块名>  <LABEL> — <DESC>  [别名: ..]；机器模式 TSV（模块名<TAB>DESC）。
# 缺关键字 / 无匹配 rc=1（供脚本判定），有匹配 rc=0。
show_search_results() {
    if [[ $# -eq 0 ]]; then
        error "用法: ./install.sh search <关键字> [关键字...]（匹配模块名/别名/描述，多关键字 AND）"
        return 1
    fi
    local -a hits=()
    local mod cat cat_mods group label desc aliases line
    while IFS= read -r mod; do
        [[ -n "$mod" ]] && hits+=("$mod")
    done < <(registry_search "$@")
    if [[ ${#hits[@]} -eq 0 ]]; then
        warn "无匹配模块。试试更短的关键字，或用 --list-categories 查看全部"
        return 1
    fi
    if uxs_is_machine_mode; then
        for mod in "${hits[@]}"; do
            printf '%s\t%s\n' "$mod" "$(registry_desc "$mod")"
        done
        return 0
    fi
    for cat in $CATEGORY_ORDER; do
        cat_mods=$(registry_modules_in_category "$cat")
        group=""
        for mod in "${hits[@]}"; do
            [[ " $cat_mods " == *" $mod "* ]] && group="$group $mod"
        done
        [[ -z "$group" ]] && continue
        echo "[$cat]"
        for mod in $group; do
            label=$(_reg_get "$mod" LABEL)
            desc=$(registry_desc "$mod")
            aliases=$(_reg_get "$mod" ALIASES)
            line="  $mod"
            [[ -n "$label" ]] && line="$line  $label"
            [[ -n "$desc" ]] && line="$line — $desc"
            [[ -n "$aliases" ]] && line="$line  [别名: $aliases]"
            printf '%s\n' "$line"
        done
    done
    info "共 ${#hits[@]} 个匹配"
    return 0
}

# show_next_steps <模块名> — 安装成功后的「下一步」引导块（批次②）。
# 条目来自 .manifest 的 NEXT_STEPS（分号分隔，条目内冒号分隔「说明:命令」）。
# 仅人类模式 + 非 dry-run 打印；机器模式与预览模式零输出。
show_next_steps() {
    local mod="$1" raw
    raw=$(registry_next_steps "$mod")
    [[ -z "$raw" ]] && return 0
    if uxs_is_machine_mode; then return 0; fi
    [[ "${UNIX_SCRIPT_DRY_RUN:-0}" == "1" ]] && return 0
    local IFS=';'
    local -a items
    read -ra items <<< "$raw"
    echo
    info "💡 下一步："
    local item
    for item in ${items[@]+"${items[@]}"}; do
        [[ -z "$item" ]] && continue
        if [[ "$item" == *:* ]]; then
            printf '   • %s → %s\n' "${item%%:*}" "${item#*:}"
        else
            printf '   • %s\n' "$item"
        fi
    done
}

show_usage() {
    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help        显示本帮助
  -v, --version     显示版本
  -s, --status      查看所有模块的安装状态后退出（非交互）
  --dry-run         预览模式：sudo/root 操作仅打印不执行（用户级操作仍会执行）
  --list            列出可用模块名后退出
  --list-modules    机器可读：模块名 + 支持子命令 + 描述（TSV，供 AI/脚本）
  --list-categories 按分类列出所有模块
  --status-json     机器可读：模块状态 key:value（无颜色，供 AI/脚本）
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库
  scaffold <名称>   生成新模块脚手架（--category <分类> --label <标签>）
  doctor            环境诊断：检查运行 unix_script 所需的前提条件
  cli               安装全局命令 uxs 到 ~/.tools/bin（之后可在任意目录 uxs <子命令>）
  uninstall-cli     卸载全局命令 uxs
  completions       安装 Tab 自动补全到当前 shell 配置

模块（按分类；别名与平台支持详见 --list-categories / README）:
EOF
    local cat mod label desc mods
    for cat in $CATEGORY_ORDER; do
        mods=$(registry_modules_in_category "$cat")
        if [[ -z "$mods" ]]; then continue; fi
        echo "  [$cat]"
        for mod in $mods; do
            label=$(_reg_get "$mod" LABEL)
            desc=$(registry_desc "$mod")
            printf '    %-22s %s\n' "$mod" "${desc:-$label}"
        done
    done
    cat <<'EOF'

示例:
  ./install.sh                       # 进入交互式主菜单（fzf 模糊搜索/多选；无 fzf 自动用分类菜单）
  ./install.sh --status              # 直接打印安装状态
  ./install.sh docker                # 直接安装 docker
  ./install.sh tailscale             # 直接安装 tailscale
  ./install.sh check-update          # 检查是否有新版本
  ./install.sh update                # 更新到最新版本（需确认）
  ./install.sh scaffold my-tool      # 生成名为 my-tool 的新模块脚手架
  ./install.sh doctor                # 环境诊断
  ./install.sh --dry-run docker      # 预览安装 docker 的操作（不实际执行）
  ./install.sh cli                   # 安装全局命令 uxs（之后可 uxs docker-image 等）
EOF
}

show_noninteractive_usage() {
    show_usage
}
