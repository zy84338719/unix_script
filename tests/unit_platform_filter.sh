#!/usr/bin/env bash
#
# tests/unit_platform_filter.sh — 平台可见性过滤单测
# 覆盖：PLATFORMS 解析 / uxs_module_supported / registry_visible_modules /
#       CLI 出口过滤 + SHOW_ALL / dispatch 护栏 / apply 跳过
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
        # 纵深防御：brew 的 status 在 Linux 须报 n/a（install 是 darwin-gated，二者须自洽）
        s=$(cd "$REPO_DIR/essentials/brew" && UXS_STATUS_MODE=machine bash install.sh status </dev/null 2>/dev/null | sed -n 's/^STATE=//p' | head -1)
        t_eq "status(linux): brew 报 n/a 而非 not_installed" "n/a" "$s"
        ;;
esac

# ---------- registry_visible_modules ----------
VIS=$(registry_visible_modules)
case "$OS_TYPE" in
    darwin)
        # shellcheck disable=SC2016  # \$VIS 交给 t_true 内 eval 展开（延迟求值）
        t_true "visible(darwin): 含 docker" "printf '%s' \"\$VIS\" | grep -qw docker"
        t_true "visible(darwin): 不含 ufw" "! printf '%s' \"\$VIS\" | grep -qw ufw"
        t_true "visible(darwin): 含 brew" "printf '%s' \"\$VIS\" | grep -qw brew"
        ;;
    linux)
        t_true "visible(linux): 含 ufw" "printf '%s' \"$VIS\" | grep -qw ufw"
        t_true "visible(linux): 不含 brew" "! printf '%s' \"$VIS\" | grep -qw brew"
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
        t_true "--list: 不含 ufw" "! printf '%s' \"$LST\" | grep -qw ufw"
        t_true "--list: 含 docker" "printf '%s' \"$LST\" | grep -qw docker"
        t_true "SHOW_ALL --list: 含 ufw" "printf '%s' \"$LST_ALL\" | grep -qw ufw"
        ;;
    linux)
        t_true "--list: 不含 brew" "! printf '%s' \"$LST\" | grep -qw brew"
        t_true "SHOW_ALL --list: 含 brew" "printf '%s' \"$LST_ALL\" | grep -qw brew"
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
    darwin) t_true "--list-categories: 无 ufw 行" "! printf '%s' \"$LC\" | grep -q '^  ufw'" ;;
    linux)  t_true "--list-categories: 无 brew 行" "! printf '%s' \"$LC\" | grep -q '^  brew'" ;;
esac

# ---------- category_items / 菜单可见性 ----------
case "$OS_TYPE" in
    darwin)
        CAT_ST=$(category_items 系统工具 "")
        t_true "category_items: 系统工具不含 ufw" "! printf '%s' \"$CAT_ST\" | grep -qw ufw"
        t_true "category_items: 系统工具含 disk-usage" "printf '%s' \"$CAT_ST\" | grep -qw disk-usage"
        ;;
    linux)
        CAT_ES=$(category_items 装机必备 "")
        t_true "category_items: 装机必备不含 brew" "! printf '%s' \"$CAT_ES\" | grep -qw brew"
        ;;
esac

# ---------- dispatch 平台护栏 ----------
if [[ "$OS_TYPE" == "darwin" ]]; then
    OUT=$(run_install ufw </dev/null 2>&1); t_rc "gate: darwin 分发 ufw rc=1" 1 $?
    t_true "gate: 报错含「不支持当前系统」" "printf '%s' \"\$OUT\" | grep -q '不支持当前系统'"
    t_true "gate: 提示 SHOW_ALL 逃生口" "printf '%s' \"\$OUT\" | grep -q 'UNIX_SCRIPT_SHOW_ALL=1'"
    OUT=$(UNIX_SCRIPT_SHOW_ALL=1 run_install ufw status </dev/null 2>&1); t_rc "gate: SHOW_ALL 放行透传 status rc=0" 0 $?
fi
if [[ "$OS_TYPE" == "linux" ]]; then
    OUT=$(run_install brew </dev/null 2>&1); t_rc "gate: linux 分发 brew rc=1" 1 $?
    t_true "gate: 报错含「不支持当前系统」" "printf '%s' \"\$OUT\" | grep -q '不支持当前系统'"
fi

# ---------- profile：export 过滤 / apply 跳过 ----------
if [[ "$OS_TYPE" == "darwin" ]]; then HIDDEN_MOD=ufw; else HIDDEN_MOD=brew; fi

PFILE=$(mktemp)
run_install export "$PFILE" >/dev/null 2>&1; t_rc "export: rc=0" 0 $?
t_true "export: 文件含头注" "grep -q '^# unix_script profile' \"\$PFILE\""
t_true "export: 不导出不适用模块 ${HIDDEN_MOD}" "! grep -q \"^${HIDDEN_MOD}\" \"\$PFILE\""
rm -f "$PFILE"

PROF=$(mktemp)
printf '%s   # 测试不适用行\n' "$HIDDEN_MOD" > "$PROF"
OUT=$(run_install apply "$PROF" --dry-run </dev/null 2>&1); t_rc "apply: 仅不适用行 rc=0（跳过不报错）" 0 $?
t_true "apply: 输出跳过原因（不支持当前系统）" "printf '%s' \"\$OUT\" | grep -q '不支持当前系统'"
t_true "apply: 汇总计跳过 1" "printf '%s' \"\$OUT\" | grep -q '跳过 1'"
rm -f "$PROF"

echo "unit_platform_filter: 通过 $PASS / 失败 $FAIL"
[[ $FAIL -eq 0 ]]
