#!/usr/bin/env bash
#
# lib/menu_fzf.sh
#
# fzf 交互菜单：模糊搜索 + TAB 多选 + 右侧 README 预览。
# 依赖 fzf（可选）：由 lib/menu.sh 的 resolve_menu_mode 保证仅在 fzf 存在时进入。
#
# 行格式（TAB 分隔，6 段）：图标\t名称\tLABEL\tDESC\t物理路径\t动作键
#
# 动作键（第 6 段）的三种取值：
#   空             ⇒ 模块行（第 2 段是模块名）
#   __uxs_admin_*  ⇒ 管理项（状态总览 / 卸载 / 检查更新 / 刷新缓存）
#   __uxs_cat_*    ⇒ 分类入口（进该分类的二级列表）
# 动作键放第 6 段并用 --with-nth=1..5 隐藏 ⇒ 列表里不出现内部标识。
#

# 幂等保护
if [[ -n "${_MENU_FZF_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_MENU_FZF_SH_LOADED=1

# ---------------- 预览命令（{5} = 模块物理路径） ----------------
# ★ 踩过的坑（2026-08 起就在，v2.2.0 才修）：fzf 把占位符替换成**shell 单引号包住**的值，
#   {5} ⇒ 'services/gitea'（实测 fzf 0.74.4）。
#   老写法 --preview 'head -30 "$UXS_REPO_DIR/{5}/README.md"'
#   ⇒ 路径里多了**字面单引号** ⇒ 必然找不到文件 ⇒ 预览面板永远只有「（无模块 README）」，
#   而 58 个模块**全都有** README.md ⇒ 这块预览从来没显示过任何内容。
#   正确写法：占位符**不要套在自己的引号里**，让 shell 去做拼接。
#
# 另：--with-nth=1..5 把第 6 段藏了 ⇒ 预览里 {6} 取不到（实测为空），
#   所以「这一行是不是模块」只能靠 {5} 是否为空来区分。
# 抽成全局变量：既给 fzf 用，也给测试用（测试要模拟 fzf 的占位符替换）。
# 主列表顶栏文案。
#
# ★ 措辞教训：早先写的是「顶部：管理项 4 行 + 分类入口 ▸ 行」，
#   但 fzf 有 layout=reverse（列表从下往上渲染，首批行贴着提示符）——
#   用户截图里管理项与分类入口明明在屏幕**下方**，「顶部」二字直接是错的。
#   ⇒ 不写死位置，改成直接点名这些行长什么样（图标 + 简称），用户一眼能认出来。
#   宽度控制在 80 列内（实测 76 列），免得窄终端被 fzf 截断。
_MENU_FZF_HEADER_MAIN="TAB 多选 · 回车执行默认动作 · ESC 退出 ｜ ⚙状态总览 🗑卸载 🔄更新 ⟳刷新 ▸分类"

# shellcheck disable=SC2016  # $p / $UXS_REPO_DIR 由 fzf 的 preview 子 shell 展开，非本 shell
_MENU_FZF_PREVIEW='p={5}; if [ -n "$p" ] && [ -f "$UXS_REPO_DIR/$p/README.md" ]; then head -30 "$UXS_REPO_DIR/$p/README.md"; else echo "（这一行不是模块，没有 README 预览）"; fi'

# fzf ≥ 0.20.0 才有 --preview；1.x 及以上恒真
_fzf_preview_supported() {
    command -v fzf >/dev/null 2>&1 || return 1
    local v maj min
    v=$(fzf --version 2>/dev/null | awk '{print $1}')
    maj=${v%%.*}
    min=${v#*.}; min=${min%%.*}
    [[ "$maj" =~ ^[0-9]+$ ]] || return 1
    if (( maj > 0 )); then return 0; fi
    [[ "$min" =~ ^[0-9]+$ ]] && (( min >= 20 ))
}

# ---------------- 管理项（与 bash 菜单的 s/u/c/f 一一对应） ----------------
# ★ 为什么必须有：fzf 模式接管后，bash 菜单（分类导航 + 状态/卸载/更新/刷新）
#   整个到不了 —— 列表里只有模块、选中只能执行默认动作（装），
#   「uxs 退化成只能装的搜索框」，老的交互手感全没了。
#   这里把四个管理入口补回列表顶部，与 bash 菜单对齐。
#
# 行格式（6 段）：图标\t标题\t说明\t(空)\t(空)\t动作键
menu_fzf_admin_rows() {
    printf '⚙\t状态总览\t查看所有模块的安装状态\t\t\t__uxs_admin_status__\n'
    printf '🗑\t卸载服务/环境\t交互式卸载已安装的模块\t\t\t__uxs_admin_uninstall__\n'
    printf '🔄\t检查更新\t检查并更新到最新版本\t\t\t__uxs_admin_update__\n'
    printf '⟳\t刷新状态缓存\t重新检测所有模块的安装状态\t\t\t__uxs_admin_refresh__\n'
}

# 管理项 → 实际动作（与 bash 菜单同款）
menu_fzf_run_admin() {
    case "$1" in
        __uxs_admin_status__) show_installed_services ;;
        __uxs_admin_uninstall__) uninstall_menu_loop ;;
        __uxs_admin_update__) menu_check_update ;;
        __uxs_admin_refresh__) menu_refresh_status_cache ;;
        *)
            menu_error "未知管理项: $1"
            return 1
            ;;
    esac
}

# ---------------- 分类入口（对齐 bash 菜单的「两级导航」） ----------------
# 老版 bash 菜单是「先选分类、再选模块」；fzf 若只留平铺搜索，
# 就丢了这条老路 —— 这里在列表顶部补分类入口，选中后弹第二个 fzf 列该分类的模块。
# 一维模糊搜索仍然保留（平铺模块行还在列表里），两级导航是并行入口，不是替代。
#
# 键：__uxs_cat_<分类名>（分类名不含空格：服务 / 装机必备 / 开发环境 / AI工具 / 系统工具）
menu_fzf_category_rows() {
    local cat mods mod state total installed
    for cat in $(registry_categories); do
        mods=$(category_items "$cat" "")
        [ -n "$mods" ] || continue
        total=0
        installed=0
        for mod in $mods; do
            total=$((total + 1))
            _uxs_state_out "$mod" state
            case "$state" in
                installed*|configured) installed=$((installed + 1)) ;;
            esac
        done
        printf '▸\t%s\t%d/%d 已装\t\t\t__uxs_cat_%s\n' "$cat" "$installed" "$total" "$cat"
    done
}

# 构造 fzf 列表：管理项 + 分类入口在最前，模块行随后（纯函数，可测）
menu_fzf_build_list() {
    local lines="" mod state icon label desc path
    # $() 会吃掉末尾换行 ⇒ 两段之间自己补一个
    lines=$(menu_fzf_admin_rows; menu_fzf_category_rows)
    lines+=$'\n'
    for mod in $(registry_visible_modules); do
        # 零 fork 出参（原每行 4 次 $( ) fork：state/icon/label/desc/path）
        _uxs_state_out "$mod" state
        _status_icon_out "$state" icon
        _reg_get_out "$mod" LABEL label
        _reg_get_out "$mod" DESC desc
        _reg_path_out "$mod" path
        lines+="${icon}	${mod}	${label}	${desc}	${path}	"$'\n'
    done
    printf '%s' "$lines"
}

# 动作键分类（纯函数，可测）：main 循环靠它分派，不靠字符串前缀散落各处
menu_fzf_key_kind() {
    case "$1" in
        __uxs_admin_*) echo admin ;;
        __uxs_cat_*) echo category ;;
        "") echo module ;;
        *) echo unknown ;;
    esac
}

# fzf 公共参数（主列表与分类子列表共用；预览需要仓库绝对路径）
# 用全局数组回传：bash 3.2 没有 nameref，命令替换会把数组吃掉
_MENU_FZF_ARGS=()
menu_fzf_setup_args() {
    local header="$1"
    _MENU_FZF_ARGS=(--multi --header="$header" --delimiter=$'\t' --with-nth=1..5)
    if _fzf_preview_supported; then
        # shellcheck disable=SC2016  # $UXS_REPO_DIR 由 fzf preview 子 shell 展开，非本 shell
        _MENU_FZF_ARGS+=(
            --preview "$_MENU_FZF_PREVIEW"
            --preview-window "right:40%:wrap"
        )
    fi
}

# 打开某个分类的模块选择（第二个 fzf，可多选）；每个选中的模块名输出一行
menu_fzf_pick_category() {
    local cat="$1" lines="" mod state icon label desc path selected
    for mod in $(category_items "$cat" ""); do
        _uxs_state_out "$mod" state
        _status_icon_out "$state" icon
        _reg_get_out "$mod" LABEL label
        _reg_get_out "$mod" DESC desc
        _reg_path_out "$mod" path
        lines+="${icon}	${mod}	${label}	${desc}	${path}	"$'\n'
    done
    [ -n "$lines" ] || return 0
    menu_fzf_setup_args "TAB 多选 · 回车执行默认动作 · ESC 返回（分类：$cat）"
    selected=$(printf '%s' "$lines" | fzf "${_MENU_FZF_ARGS[@]}") || return 0
    printf '%s\n' "$selected" | awk -F'\t' '$6 == "" {print $2}'
}

# 分类入口 → 二级列表 → 执行默认动作（分类是「页面」：执行完回到主列表）
menu_fzf_run_category() {
    local cat="$1" picked
    local -a mods=()
    picked=$(menu_fzf_pick_category "$cat")
    [ -n "$picked" ] || return 0
    read -ra mods <<< "$picked"
    [ ${#mods[@]} -gt 0 ] || return 0
    menu_exec_actions "${mods[@]}"
}

menu_fzf_main() {
    menu_status_ensure
    # preview 子 shell 需要仓库绝对路径
    export UXS_REPO_DIR="$SCRIPT_DIR"

    local selected key mods cat
    while true; do
        local lines
        lines=$(menu_fzf_build_list)
        # 每次循环都要重建参数：分类子列表会覆盖这份全局数组
        menu_fzf_setup_args "$_MENU_FZF_HEADER_MAIN"

        if ! selected=$(printf '%s' "$lines" | fzf "${_MENU_FZF_ARGS[@]}"); then
            # ESC / Ctrl-C / 无选择：静默返回
            return 0
        fi

        # 第 6 段非空 ⇒ 管理项或分类入口；否则第 2 段是模块名。
        # 用 awk 解析而不是 read：IFS=TAB 时连续 TAB 会被当成一个分隔符，
        # 空字段会被吞掉（管理项的第 4/5 段就是空的）。
        key=$(printf '%s\n' "$selected" | awk -F'\t' '$6 != "" {print $6; exit}')
        mods=$(printf '%s\n' "$selected" | awk -F'\t' '$6 == "" {print $2}')

        case "$(menu_fzf_key_kind "$key")" in
            admin)
                # 管理项是「页面」不是「动作」：执行完回到选择器，可以接着操作
                menu_fzf_run_admin "$key" || true
                continue
                ;;
            category)
                cat="${key#__uxs_cat_}"
                menu_fzf_run_category "$cat" || true
                continue
                ;;
            unknown)
                menu_error "未知入口: $key"
                continue
                ;;
        esac

        local -a mod_list=()
        if [[ -n "$mods" ]]; then
            read -ra mod_list <<< "$mods"
        fi
        [ ${#mod_list[@]} -gt 0 ] || continue
        menu_exec_actions "${mod_list[@]}"
        return 0
    done
}
