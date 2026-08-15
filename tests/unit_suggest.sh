#!/usr/bin/env bash
#
# tests/unit_suggest.sh — lib/suggest.sh 纯函数单测
# 独立运行：bash tests/unit_suggest.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
#
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望输出> <实际输出>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

t_rc() {  # t_rc <名称> <期望rc:0|1> <实际rc>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望rc=$2 实际rc=$3"
    fi
}

SCRIPT_DIR="$REPO_DIR"
# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=../lib/registry.sh
source "$REPO_DIR/lib/registry.sh"
# shellcheck source=../lib/suggest.sh
source "$REPO_DIR/lib/suggest.sh"
# shellcheck source=../lib/menu.sh
source "$REPO_DIR/lib/menu.sh"
detect_os >/dev/null 2>&1 || true
registry_scan

# ---- levenshtein ----
t_eq "lev(docker,docker)=0"   0 "$(levenshtein docker docker)"
t_eq "lev(doker,docker)=1"    1 "$(levenshtein doker docker)"
t_eq "lev(,abc)=3"            3 "$(levenshtein '' abc)"
t_eq "lev(cat,)=3"            3 "$(levenshtein cat '')"
t_eq "lev(kitten,sitting)=3"  3 "$(levenshtein kitten sitting)"
t_eq "lev(flaw,lawn)=2"       2 "$(levenshtein flaw lawn)"

# ---- suggest_module ----
t_eq "suggest(doker)=docker"      "docker"   "$(suggest_module doker)"
t_eq "suggest(post)=postgres"     "postgres" "$(suggest_module post)"
t_eq "suggest(zzzqqq) 为空"       ""         "$(suggest_module zzzqqq)"

# ---- parse_multiselect ----
t_eq "parse(1)"            "1"           "$(parse_multiselect 1 10)"
t_eq "parse(1,3)"          "1 3"         "$(parse_multiselect 1,3 10)"
t_eq "parse(2-5)"          "2 3 4 5"     "$(parse_multiselect 2-5 10)"
t_eq "parse(1,3,5-8)"      "1 3 5 6 7 8" "$(parse_multiselect 1,3,5-8 10)"
t_eq "parse(3,1) 排序"     "1 3"         "$(parse_multiselect 3,1 10)"
t_eq "parse(1,1) 去重"     "1"           "$(parse_multiselect 1,1 10)"
parse_multiselect 0 10 >/dev/null 2>&1;      t_rc "parse(0) 越界 rc1"     1 "$?"
parse_multiselect 11 10 >/dev/null 2>&1;     t_rc "parse(11) 越界 rc1"    1 "$?"
parse_multiselect 8-2 10 >/dev/null 2>&1;    t_rc "parse(8-2) 逆序 rc1"   1 "$?"
parse_multiselect "a,1" 10 >/dev/null 2>&1;  t_rc "parse(a,1) 非法 rc1"   1 "$?"

# ---- module_subcommands（menu.sh 重构产物）----
case " $(module_subcommands docker) " in
    *" mirror "*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL: module_subcommands(docker) 含 mirror，实际: $(module_subcommands docker)" ;;
esac
case " $(module_subcommands bun) " in
    *" uninstall "*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL: module_subcommands(bun) 含 uninstall，实际: $(module_subcommands bun)" ;;
esac

echo "unit_suggest: 通过 $PASS / 失败 $FAIL"
[[ $FAIL -eq 0 ]]
