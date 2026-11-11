#!/usr/bin/env bash
#
# lib/uxs_status.sh —— unix_script 的状态呈现层
#
# 能力来自 shellkit 的 status_* 系列（状态码有限集、机器模式输出 STATE=/VERSION=/EXTRA=）。
# unix_script 在这一层只做一件事：**把自己的旋钮名映射到 shellkit 的旋钮名**。
#
# 为什么不能只在加载时 export 一次：shellkit 的 status_* 在**调用时**读 SHELLKIT_STATUS_MODE，
# 而 unix_script 的旋钮叫 UXS_STATUS_MODE。两者不是同一个名字（通用库不该知道调用方的
# 旋钮名），映射必须在每次输出前做 —— 进程内改 UXS_STATUS_MODE 也要立刻生效
#（tests/unit_usability.sh 就这么用的）。
#
# 幂等保护
if [[ -n "${_UXS_STATUS_LOADED:-}" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
_UXS_STATUS_LOADED=1

# uxs_status_sync —— 把 unix_script 的旋钮映射到 shellkit 的旋钮
uxs_status_sync() {
    export SHELLKIT_STATUS_MODE="${UXS_STATUS_MODE:-human}"
}

# uxs_emit_status STATE HUMAN_MSG —— 输出状态（机器模式输出 STATE=，人类模式输出文案）
uxs_emit_status()  { uxs_status_sync; status_emit "$@"; }
uxs_emit_version() { uxs_status_sync; status_version "$@"; }
uxs_emit_extra()   { uxs_status_sync; status_extra "$@"; }

# uxs_is_machine_mode —— 机器模式返回 0，人类模式返回 1
uxs_is_machine_mode() { uxs_status_sync; status_is_machine; }
