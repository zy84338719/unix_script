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
# shellcheck source=../lib/menu.sh
source "$REPO_DIR/lib/menu.sh"
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

# ---------- CLI 出口过滤（子进程级，覆盖接线）----------
run_install() { bash "$REPO_DIR/install.sh" "$@"; }
LST=$(run_install --list)
LST_ALL=$(UNIX_SCRIPT_SHOW_ALL=1 run_install --list)
case "$OS_TYPE" in
    darwin)
        t_true "--list: 不含 ufw" 'case " $LST " in *" ufw "*) false;; *) true;; esac'
        t_true "--list: 含 docker" 'case " $LST " in *" docker "*) true;; *) false;; esac'
        t_true "SHOW_ALL --list: 含 ufw" 'case " $LST_ALL " in *" ufw "*) true;; *) false;; esac'
        ;;
    linux)
        t_true "--list: 不含 brew" 'case " $LST " in *" brew "*) false;; *) true;; esac'
        t_true "SHOW_ALL --list: 含 brew" 'case " $LST_ALL " in *" brew "*) true;; *) false;; esac'
        ;;
esac
N_ALL=$(printf '%s' "$LST_ALL" | wc -w | tr -d ' ')
N_VIS=$(printf '%s' "$LST" | wc -w | tr -d ' ')
t_true "--list: 可见数 ≤ 全量数（${N_VIS}/${N_ALL}）" "(( $N_VIS <= $N_ALL ))"

# --status-json 关键不变量：默认零 n/a 行；SHOW_ALL 行数=全量模块数；头 3 行元数据不动
J=$(run_install --status-json | tail -n +4)
J_ALL=$(UNIX_SCRIPT_SHOW_ALL=1 run_install --status-json)
t_eq "status-json: 默认零 n/a 行" "0" "$(printf '%s\n' "$J" | grep -c ':n/a' || true)"
t_eq "status-json: 默认行数=可见模块数" "$N_VIS" "$(printf '%s\n' "$J" | grep -c . || true)"
t_eq "status-json: SHOW_ALL 行数=全量模块数" "$N_ALL" "$(printf '%s\n' "$J_ALL" | tail -n +4 | grep -c . || true)"
t_eq "status-json: 头 3 行元数据仍在" "3" "$(printf '%s\n' "$J_ALL" | head -3 | grep -cE '^(os|arch|version):' || true)"

# search：隐藏模块无匹配 rc=1；SHOW_ALL 命中 rc=0
if [[ "$OS_TYPE" == "darwin" ]]; then
    run_install search ufw >/dev/null 2>&1; t_rc "search: darwin 搜 ufw 无匹配 rc=1" 1 $?
    UNIX_SCRIPT_SHOW_ALL=1 run_install search ufw >/dev/null 2>&1; t_rc "search: SHOW_ALL 搜 ufw rc=0" 0 $?
    run_install search 容器 >/dev/null 2>&1; t_rc "search: 通用关键字 rc=0" 0 $?
fi

# --list-categories 不含隐藏模块行
LC=$(run_install --list-categories)
case "$OS_TYPE" in
    darwin) t_true "--list-categories: 无 ufw 行" '! printf "%s" "$LC" | grep -q "^  ufw"' ;;
    linux)  t_true "--list-categories: 无 brew 行" '! printf "%s" "$LC" | grep -q "^  brew"' ;;
esac

# ---------- category_items / 菜单可见性 ----------
case "$OS_TYPE" in
    darwin)
        t_true "category_items: 系统工具不含 ufw" 'case " $(category_items 系统工具 "") " in *" ufw "*) false;; *) true;; esac'
        t_true "category_items: 系统工具含 disk-usage" 'case " $(category_items 系统工具 "") " in *" disk-usage "*) true;; *) false;; esac'
        ;;
    linux)
        t_true "category_items: 装机必备不含 brew" 'case " $(category_items 装机必备 "") " in *" brew "*) false;; *) true;; esac'
        ;;
esac

echo "unit_platform_filter: 通过 $PASS / 失败 $FAIL"
[[ $FAIL -eq 0 ]]
