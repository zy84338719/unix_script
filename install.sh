#!/usr/bin/env bash
set -e

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
source "$SCRIPT_DIR/lib/status.sh"
source "$SCRIPT_DIR/lib/submenus.sh"
source "$SCRIPT_DIR/lib/uxs_cli.sh"
source "$SCRIPT_DIR/lib/menu.sh"

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

    # 特殊模块：需要子菜单或特殊动作
    case "$name" in
        npm-mirror|npm_mirror|npmmirror)
            run_in_dir dev-mirror install.sh install npm taobao
            return $?
            ;;
    esac

    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        error "未知模块: $name"
        show_noninteractive_usage
        exit 1
    fi

    local default_action
    default_action=$(registry_default_action "$resolved")

    # 特殊模块：有子菜单的在非交互模式下执行默认动作
    case "$resolved" in
        shutdown_timer)
            manage_shutdown_timer
            return $?
            ;;
        process_manager_tool)
            manage_process_tool
            return $?
            ;;
    esac

    local action_args=($default_action)
    run_in_dir "$resolved" install.sh "${action_args[@]}"
}

# ---------------- 模块透传（如 install.sh bun mirror） ----------------
dispatch_module_or_passthrough() {
    if [[ $# -ge 2 ]] && [[ -d "$SCRIPT_DIR/$1" ]] && [[ -f "$SCRIPT_DIR/$1/install.sh" ]]; then
        local mod="$1"; shift
        info "执行模块 $mod: install.sh $*"
        run_in_dir "$mod" install.sh "$@"
    else
        dispatch_module "$1"
    fi
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
        -h|--help)    show_usage; exit 0 ;;
        -v|--version) echo "unix_script $(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
        -s|--status)  INTERACTIVE=false; show_installed_services; exit 0 ;;
        --list)
            # 动态列出所有有 manifest 的模块
            for mod in $_REGISTRY_MODULES; do printf '%s ' "$mod"; done
            echo
            exit 0
            ;;
        --list-modules) show_list_modules; exit 0 ;;
        --status-json)  show_status_json; exit 0 ;;
        check-update)
            info "检查远端最新版本..."
            if check_for_update 2>/dev/null; then
                warn "有新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST}"
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
        cli|install-cli)
            install_cli
            exit $?
            ;;
        uninstall-cli|remove-cli)
            uninstall_cli
            exit $?
            ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)  dispatch_module_or_passthrough "$@" ;;
    esac
}

# --- 脚本入口 ---
main "$@"
