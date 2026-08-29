#!/usr/bin/env bash
#
# tests/unit_platform_filter.sh — 平台可见性过滤单测
# 覆盖：PLATFORMS 解析 / uxs_module_supported / registry_visible_modules /
#       CLI 出口过滤 + SHOW_ALL / dispatch 护栏 / apply 跳过（随任务分批追加）
# 独立运行：bash tests/unit_platform_filter.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}
t_rc() {  # t_rc <名称> <期望rc> <实际rc>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1  期望rc=$2 实际rc=$3"
    fi
}
t_true() {  # t_true <名称> <条件命令>
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1"
    fi
}

SCRIPT_DIR="$REPO_DIR"
# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=../lib/registry.sh
source "$REPO_DIR/lib/registry.sh"
set +e +o pipefail
detect_os >/dev/null 2>&1 || true
registry_scan

# ---------- PLATFORMS 解析 ----------
t_eq "registry_platforms(ufw)=linux" "linux" "$(registry_platforms ufw)"
t_eq "registry_platforms(sys-setup)=linux" "linux" "$(registry_platforms sys-setup)"
t_eq "registry_platforms(brew)=darwin" "darwin" "$(registry_platforms brew)"
t_eq "registry_platforms(docker)=空（全平台）" "" "$(registry_platforms docker)"

# ---------- uxs_module_supported 真值表（按宿主分支断言）----------
case "$OS_TYPE" in
    darwin)
        uxs_module_supported docker;    t_rc "supported(darwin): docker→0" 0 $?
        uxs_module_supported brew;      t_rc "supported(darwin): brew→0" 0 $?
        uxs_module_supported ufw;       t_rc "supported(darwin): ufw→1" 1 $?
        uxs_module_supported sys-setup; t_rc "supported(darwin): sys-setup→1" 1 $?
        ;;
    linux)
        uxs_module_supported docker;    t_rc "supported(linux): docker→0" 0 $?
        uxs_module_supported ufw;       t_rc "supported(linux): ufw→0" 0 $?
        uxs_module_supported brew;      t_rc "supported(linux): brew→1" 1 $?
        ;;
esac

# ---------- registry_visible_modules ----------
VIS=$(registry_visible_modules)
case "$OS_TYPE" in
    darwin)
        t_true "visible(darwin): 含 docker" 'case " $VIS " in *" docker "*) true;; *) false;; esac'
        t_true "visible(darwin): 不含 ufw" 'case " $VIS " in *" ufw "*) false;; *) true;; esac'
        t_true "visible(darwin): 含 brew" 'case " $VIS " in *" brew "*) true;; *) false;; esac'
        ;;
    linux)
        t_true "visible(linux): 含 ufw" 'case " $VIS " in *" ufw "*) true;; *) false;; esac'
        t_true "visible(linux): 不含 brew" 'case " $VIS " in *" brew "*) false;; *) true;; esac'
        ;;
esac
UNIX_SCRIPT_SHOW_ALL=1
VIS_ALL=$(registry_visible_modules)
unset UNIX_SCRIPT_SHOW_ALL
t_eq "visible: SHOW_ALL=1 输出全量注册表" "$_REGISTRY_MODULES" "$VIS_ALL"

echo "unit_platform_filter: 通过 $PASS / 失败 $FAIL"
[[ $FAIL -eq 0 ]]
