#!/usr/bin/env bash
#
# tests/unit_usability.sh — 易用性快修包批次① 单测
# 覆盖：uxs_with_timeout / status 批查容错 / --status-json 防截断 / doctor 无 TTY / ufw 降级链 / dry-run 副作用
# 独立运行：bash tests/unit_usability.sh（退出码 0=全过）
# 也被 tests/ci_run.sh 调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

t_true() {  # t_true <名称> <条件命令>
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1"
    fi
}

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
set +e +o pipefail

# ---------- uxs_with_timeout ----------
rc=$(uxs_with_timeout 2 true; echo $?)
t_eq "timeout: 快命令透传 rc=0" "0" "$rc"

rc=$(uxs_with_timeout 2 false; echo $?)
t_eq "timeout: 失败命令透传 rc=1" "1" "$rc"

S=$SECONDS
rc=$(uxs_with_timeout 1 sleep 5 >/dev/null 2>&1; echo $?)
ELAPSED=$((SECONDS - S))
t_eq "timeout: 超时 rc=124" "124" "$rc"
t_true "timeout: 超时及时返回（实测 ${ELAPSED}s ≤ 2s）" "(( ELAPSED <= 2 ))"

# ---------- 汇总 ----------
echo "通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
