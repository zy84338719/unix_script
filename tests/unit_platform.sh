#!/usr/bin/env bash
#
# tests/unit_platform.sh — lib 平台动词 helper（os_release_field / uxs_svc）单测
# 独立运行：bash tests/unit_platform.sh（退出码 0=全过）
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

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
set +e +o pipefail

# ---------- os_release_field ----------
FIX=$(mktemp)
cat > "$FIX" <<'EOF'
ID="ubuntu"
VERSION_ID="24.04"
PRETTY_NAME='Ubuntu 24.04 LTS'
VERSION_CODENAME=noble
EOF
t_eq "os_release: 双引号值" "ubuntu" "$(os_release_field ID "$FIX")"
t_eq "os_release: 版本" "24.04" "$(os_release_field VERSION_ID "$FIX")"
t_eq "os_release: 单引号含空格" "Ubuntu 24.04 LTS" "$(os_release_field PRETTY_NAME "$FIX")"
t_eq "os_release: 无引号值" "noble" "$(os_release_field VERSION_CODENAME "$FIX")"
t_eq "os_release: 缺失键为空" "" "$(os_release_field ID_LIKE "$FIX")"
t_eq "os_release: 文件不可读为空" "" "$(os_release_field ID /nonexistent/os-release)"
rm -f "$FIX"

# ---------- detect_distro 文件模式回归（_osr_field 引号剥离被 os_release_field 复用） ----------
FIX=$(mktemp)
cat > "$FIX" <<'EOF'
ID=debian
ID_LIKE="ubuntu debian"
PRETTY_NAME='Debian GNU/Linux 13'
VERSION_ID="13"
EOF
detect_distro "$FIX"
t_eq "detect_distro: 文件模式族判定" "debian" "$DISTRO_FAMILY"
t_eq "detect_distro: 单引号 PRETTY_NAME 剥引号" "Debian GNU/Linux 13" "$DISTRO_NAME"
rm -f "$FIX"

# ---------- uxs_svc ----------
UNIX_SCRIPT_DRY_RUN=1
OS_TYPE=linux
out=$(uxs_svc enable-now nginx)
t_eq "svc: dry-run enable-now 打印且不执行" \
    "[INFO] [dry-run] systemctl enable --now: sudo systemctl enable --now nginx" "$out"
out=$(uxs_svc restart docker)
t_eq "svc: dry-run restart" "[INFO] [dry-run] systemctl restart: sudo systemctl restart docker" "$out"
rc=0; uxs_svc bogus-action nginx >/dev/null 2>&1 || rc=$?
t_eq "svc: 未知 action 返回 1" "1" "$rc"
OS_TYPE=darwin
rc=0; uxs_svc restart nginx >/dev/null 2>&1 || rc=$?
t_eq "svc: darwin 拒绝返回 1" "1" "$rc"

echo "unit_platform: 通过 $PASS / 失败 $FAIL"
(( FAIL == 0 ))
