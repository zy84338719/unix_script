#!/usr/bin/env bash
#
# tests/unit_cli_v2.sh — CLI v2 命令面单测
#
# 覆盖：保留词表 / 旧扁平写法必须失败 / 新命令的输出形状 / 帮助文本
# 独立运行：bash tests/unit_cli_v2.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
#
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

t_eq() { # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}
t_rc() { # t_rc <名称> <期望rc> <实际rc>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望rc=$2 实际rc=$3"
    fi
}
t_has() { # t_has <名称> <文本> <含该文本的串>
    if printf '%s' "$3" | grep -qF -- "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  串里找不到: $2"
    fi
}
t_hasnt() { # t_hasnt <名称> <文本> <不该含该文本的串>
    if printf '%s' "$3" | grep -qF -- "$2"; then
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  不该出现: $2"
    else
        PASS=$((PASS + 1))
    fi
}

# shellcheck source=../lib/cli_v2.sh
source "$REPO_DIR/lib/cli_v2.sh"

UXS="$REPO_DIR/install.sh"

# ---------------- 保留词表 ----------------
for w in install remove status list search info doctor export apply update scaffold completions cli help version; do
    cli_v2_is_command "$w"
    t_rc "保留词: $w" 0 $?
done
for w in docker ufw brew minikube zsh-setup; do
    cli_v2_is_command "$w"
    t_rc "非保留词: $w" 1 $?
done

# ---------------- 旧扁平写法必须失败（退出码 2 = 用法错）----------------
# 旧写法 → 新写法（迁移指引必须点名新写法）
while IFS='|' read -r old new; do
    [[ -z "$old" ]] && continue
    out=$("$UXS" "$old" 2>&1)
    rc=$?
    t_rc "旧写法 $old: 退出码 2" 2 "$rc"
    t_has "旧写法 $old: 迁移指引含 '$new'" "$new" "$out"
done <<'OLD_LIST'
--list|uxs list
--list-modules|uxs list --full
--list-categories|uxs list --grouped
--status|uxs status
--status-json|uxs status --json
--dry-run|uxs install
--no-deps|uxs install
check-update|uxs update --check
export-profile|uxs export
apply-profile|uxs apply
install-cli|uxs cli install
uninstall-cli|uxs cli uninstall
remove-cli|uxs cli uninstall
OLD_LIST

# ---------------- 未知模块 ----------------
out=$("$UXS" nosuchmodulexyz 2>&1)
rc=$?
t_rc "未知模块: 退出码 3" 3 "$rc"
t_has "未知模块: 报错含模块名" "nosuchmodulexyz" "$out"

# ---------------- list ----------------
out=$("$UXS" list 2>/dev/null)
rc=$?
t_rc "list: 退出码 0" 0 "$rc"
t_has "list: 含 docker" "docker" "$out"
n_all=$(printf '%s' "$out" | wc -w | tr -d ' ')
if [[ "$n_all" -ge 20 ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: list: 模块数 >= 20  实际=$n_all"
fi

tsv=$("$UXS" list --full 2>/dev/null)
t_rc "list --full: 退出码 0" 0 $?
bad=$(printf '%s' "$tsv" | awk -F'\t' 'NF<3 || $3==""')
t_eq "list --full: 每行三列且描述非空" "" "$bad"

grp=$("$UXS" list --grouped 2>/dev/null)
t_rc "list --grouped: 退出码 0" 0 $?
t_has "list --grouped: 含分类标题" "[" "$grp"

one=$("$UXS" list --category 服务 2>/dev/null | wc -w | tr -d ' ')
if [[ "$one" -gt 0 ]] && [[ "$one" -lt "$n_all" ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL: list --category: 过滤生效  实际=$one 全量=$n_all"
fi

# ---------------- status ----------------
js=$("$UXS" status --json 2>/dev/null)
t_rc "status --json: 退出码 0" 0 $?
t_eq "status --json: 头 3 行元数据" "3" "$(printf '%s\n' "$js" | head -3 | grep -cE '^(os|arch|version):')"
# 状态行格式：key:state[:version] —— version 里可能有冒号和空格（如 "nginx version: nginx/1.31.6"），
# 所以只校验 key 与 state 属于有限集，version 之后不约束。
t_eq "status --json: 状态行格式 key:state" "0" "$(printf '%s\n' "$js" | tail -n +4 | grep -cvE '^[a-z0-9_-]+:(not_installed|installed|installed:running|installed:stopped|configured|not_configured|n/a|unknown)(:.*)?$')"

one_js=$("$UXS" status docker --json 2>/dev/null)
t_has "status <模块> --json: 单行 key:state" "docker:" "$one_js"

# ---------------- info ----------------
info=$("$UXS" info docker 2>/dev/null)
t_rc "info docker: 退出码 0" 0 $?
t_has "info docker: 含 category" "category:" "$info"
t_has "info docker: 含 subcommands" "subcommands:" "$info"
t_has "info docker: 含 platforms" "platforms:" "$info"
"$UXS" info nosuchmodulexyz >/dev/null 2>&1
t_rc "info 未知模块: 退出码 3" 3 $?

# ---------------- search ----------------
hit=$("$UXS" search docker 2>/dev/null)
t_rc "search docker: 退出码 0" 0 $?
t_has "search docker: 有命中" "docker" "$hit"
"$UXS" search zzzqqq >/dev/null 2>&1
t_rc "search 无匹配: 退出码 1" 1 $?

# ---------------- 帮助文本 ----------------
h=$("$UXS" --help 2>&1)
for kw in install remove status list search info doctor export apply update scaffold completions cli; do
    t_has "help 含命令 $kw" "$kw" "$h"
done
for old in --list-modules --list-categories --status-json check-update install-cli remove-cli; do
    t_hasnt "help 不含旧写法 $old" "$old" "$h"
done

echo "unit_cli_v2: 通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
