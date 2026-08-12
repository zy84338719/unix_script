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
source "$SCRIPT_DIR/lib/deps.sh"
source "$SCRIPT_DIR/lib/status.sh"
source "$SCRIPT_DIR/lib/profile.sh"
source "$SCRIPT_DIR/lib/submenus.sh"
source "$SCRIPT_DIR/lib/uxs_cli.sh"
source "$SCRIPT_DIR/lib/menu.sh"
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
    resolved=$(registry_resolve_alias "$name")

    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        error "未知模块: $name"
        show_noninteractive_usage
        exit 1
    fi

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
    run_in_dir "$mod_path" "$entry_script" "${action_args[@]}"
}

# 安装模块的缺失依赖（阶段 E）。
# resolve_deps 返回拓扑序（被依赖者在前），逐个检查状态，缺则先装。
ensure_module_deps() {
    local mod="$1"
    [[ "${UNIX_SCRIPT_NO_DEPS:-0}" == "1" ]] && return 0
    local deps
    deps=$(resolve_deps "$mod")
    [[ -z "$deps" ]] && return 0
    local dep dep_path dep_entry dep_state
    for dep in $deps; do
        dep_state=$(module_status_machine "$dep")
        if [[ "$dep_state" == "not_installed" ]]; then
            info "自动安装依赖模块：$dep（被 $mod 需要）"
            dep_path=$(registry_path "$dep")
            dep_entry=$(registry_entry_script "$dep")
            run_in_dir "$dep_path" "$dep_entry" install
        fi
    done
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

    # 处理参数
    case "$1" in
        --dry-run)
            export UNIX_SCRIPT_DRY_RUN=1
            info "启用 dry-run 模式（仅预览，不实际执行）"
            shift
            if [[ $# -eq 0 ]]; then
                show_usage
                exit 0
            fi
            # 继续处理剩余参数
            dispatch_module_or_passthrough "$@"
            exit $?
            ;;
        --no-deps)
            # 阶段 E：跳过依赖自动安装
            export UNIX_SCRIPT_NO_DEPS=1
            info "跳过依赖自动安装（--no-deps）"
            shift
            if [[ $# -eq 0 ]]; then
                show_usage
                exit 0
            fi
            dispatch_module_or_passthrough "$@"
            exit $?
            ;;
        -h|--help)    show_usage; exit 0 ;;
        -v|--version) echo "unix_script $(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
        -s|--status)  INTERACTIVE=false; show_installed_services; exit 0 ;;
        --list)
            # 动态列出所有有 manifest 的模块
            for mod in $_REGISTRY_MODULES; do printf '%s ' "$mod"; done
            echo
            exit 0
            ;;
        --list-modules)    show_list_modules; exit 0 ;;
        --list-categories) show_list_categories; exit 0 ;;
        --status-json)     show_status_json; exit 0 ;;
        check-update)
            info "检查远端最新版本..."
            if check_for_update 2>/dev/null; then
                warn "有新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST:-?}"
                info "运行 ./install.sh update 一键更新"
            else
                if [[ -n "${REMOTE_LATEST:-}" ]]; then
                    success "已是最新版本：$(get_local_version)（远端 ${REMOTE_LATEST}）"
                else
                    warn "无法获取远端版本（网络问题或未发布 release），当前版本 $(get_local_version)"
                fi
            fi
            exit 0
            ;;
        update)
            do_self_update
            exit $?
            ;;
        export|export-profile)
            export_profile "${@:2}"
            exit $?
            ;;
        apply|apply-profile)
            apply_profile "${@:2}"
            exit $?
            ;;
        cli|install-cli)
            install_cli
            exit $?
            ;;
        uninstall-cli|remove-cli)
            uninstall_cli
            exit $?
            ;;
        completions)
            install_completions
            exit $?
            ;;
        scaffold)
            if [[ $# -lt 2 ]]; then
                error "用法: ./install.sh scaffold <module_name> [--category <分类>] [--label <标签>]"
                exit 1
            fi
            local mod_name="$2"; shift 2
            local mod_cat="" mod_label=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --category) mod_cat="$2"; shift 2 ;;
                    --label)    mod_label="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            scaffold_module "$mod_name" "$mod_cat" "$mod_label"
            exit $?
            ;;
        doctor)
            run_doctor
            exit $?
            ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)  dispatch_module_or_passthrough "$@" ;;
    esac
}

# --- 脚本入口 ---
main "$@"
