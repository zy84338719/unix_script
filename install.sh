#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# unix_script — 服务与环境管理工具
#
# 本文件是入口骨架，所有业务逻辑在 lib/ 中：
#   lib/common.sh    - 共享函数库（颜色/平台检测/包管理/版本检查）
#   lib/core.sh      - 框架核心（run_in_dir / run_submenu）
#   lib/registry.sh  - 模块注册表（manifest 扫描/查询）
#   lib/status.sh    - 状态检查函数
#   lib/submenus.sh  - 子菜单回调
#   lib/uxs_cli.sh   - 全局命令 uxs 管理
#   lib/menu.sh      - 主菜单 / 交互循环 / 机器可读输出 / 卸载
#
# 模块元数据定义在各模块目录的 .manifest 文件中。
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享库
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/registry.sh"
source "$SCRIPT_DIR/lib/suggest.sh"
source "$SCRIPT_DIR/lib/deps.sh"
source "$SCRIPT_DIR/lib/status.sh"
source "$SCRIPT_DIR/lib/profile.sh"
source "$SCRIPT_DIR/lib/submenus.sh"
source "$SCRIPT_DIR/lib/uxs_cli.sh"
source "$SCRIPT_DIR/lib/menu.sh"
source "$SCRIPT_DIR/lib/cli_v2.sh"
source "$SCRIPT_DIR/lib/menu_fzf.sh"
source "$SCRIPT_DIR/lib/scaffold.sh"
source "$SCRIPT_DIR/lib/doctor.sh"

# 是否处于交互模式
INTERACTIVE=true

# 判断是否应在启动时自动检查更新
should_auto_check_update() {
    [[ "${UNIX_SCRIPT_NO_UPDATE_CHECK:-0}" == "1" ]] && return 1
    [[ "${CI:-false}" == "true" ]] && return 1
    [[ -t 1 ]] || return 1
    return 0
}

# ---------------- 模块名 -> 安装动作（非交互用，注册表驱动） ----------------
dispatch_module() {
    local name="$1"
    local resolved
    # registry_resolve_alias 未命中别名时 rc=1 且原样回显输入名；
    # set -e 下命令替换失败会静默退出，故 || true 兜底，由下方统一报错。
    resolved=$(registry_resolve_alias "$name" || true)

    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        error "未知模块: $name"
        local -a cand
        read -ra cand <<< "$(suggest_module "$name")"
        if [[ ${#cand[@]} -gt 0 ]]; then
            echo "  你是想输入 ${cand[0]} 吗？（$0 ${cand[0]}）"
            if [[ ${#cand[@]} -gt 1 ]]; then
                local others="${cand[*]:1}"
                echo "  其他候选: ${others}"
            fi
        fi
        info "查看全部模块: $0 --list-categories"
        exit "$SK_PRECOND"
    fi

    # 平台护栏：不适用模块在分发层拦截（模块内部检查保留为纵深防御）
    platform_gate_or_die "$resolved" "$name"

    local default_action
    default_action=$(registry_default_action "$resolved")

    # 所有模块（含 shutdown_timer / process_manager_tool）走统一的入口脚本默认动作分发；
    # 这两个模块的交互菜单通过 HAS_SUBMENU 由主菜单进入，非交互模式执行其 DEFAULT_ACTION。
    local -a action_args
    local mod_path entry_script
    mod_path=$(registry_path "$resolved")
    entry_script=$(registry_entry_script "$resolved")
    read -ra action_args <<< "$default_action"
    # 阶段 E：仅 install 动作自动安装缺失依赖（--no-deps / UNIX_SCRIPT_NO_DEPS=1 可跳过）
    if [[ "${action_args[0]:-}" == "install" ]]; then
        ensure_module_deps "$resolved"
    fi
    local rc=0
    run_in_dir "$mod_path" "$entry_script" "${action_args[@]}" || rc=$?
    # 批次②：默认安装动作成功后给「下一步」引导（内部有人类模式/dry-run gate）
    if [[ "$rc" -eq 0 ]] && [[ "${action_args[0]:-}" == "install" ]]; then
        show_next_steps "$resolved"
    fi
    return "$rc"
}

# ---------------- 模块透传（如 install.sh bun mirror） ----------------
dispatch_module_or_passthrough() {
    if [[ $# -ge 2 ]]; then
        # 解析模块名到物理路径与入口脚本（支持 ENTRY_SCRIPT 非 install.sh 的模块）
        local resolved mod_path entry_script
        resolved=$(registry_resolve_alias "$1")
        mod_path=$(registry_path "$resolved")
        entry_script=$(registry_entry_script "$resolved")
        if [[ -d "$SCRIPT_DIR/$mod_path" ]] && [[ -f "$SCRIPT_DIR/$mod_path/$entry_script" ]]; then
            platform_gate_or_die "$resolved" "$1"
            local mod="$1"; shift
            info "执行模块 $mod: $entry_script $*"
            run_in_dir "$mod_path" "$entry_script" "$@"
            return $?
        fi
    fi
    dispatch_module "$1"
}

# ---------------- 主函数 ----------------
main() {
    detect_os
    detect_arch
    registry_scan

    # 启动时自动检查远端新版本
    if should_auto_check_update; then
        print_update_hint 2>/dev/null || true
    fi

    # 无参数 -> 交互式
    if [[ $# -eq 0 ]]; then
        if [[ ! -t 0 ]]; then
            warn "检测到非交互环境（标准输入来自管道，无法显示菜单）。"
            echo
            info "若要使用交互式菜单，请先克隆仓库后在终端直接运行："
            echo "    git clone https://github.com/zy84338719/unix_script && cd unix_script && ./install.sh"
            echo
            info "或通过 bootstrap 透传参数（非交互），例如："
            echo "    curl -fsSL .../bootstrap.sh | bash -s -- --status"
            echo "    curl -fsSL .../bootstrap.sh | bash -s -- docker"
            echo
            show_usage
            exit 0
        fi
        interactive_main
        return
    fi

    # CLI v2：分组子命令面。
    # 首参是保留词 → 命令（各有自己的 flag 集合）；非保留词 → 模块直通。
    # 旧扁平写法已一次性删除（lib/cli_v2.sh 里命中即退出 2 并给迁移指引）。
    cli_v2_dispatch "$@"
}

# --- 脚本入口 ---
main "$@"
