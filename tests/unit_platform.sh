#!/usr/bin/env bash
#
# tests/unit_platform.sh — lib 平台动词 helper（uxs_os_release / uxs_svc）单测
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

# ---------- uxs_os_release ----------
FIX=$(mktemp)
cat > "$FIX" <<'EOF'
ID="ubuntu"
VERSION_ID="24.04"
PRETTY_NAME='Ubuntu 24.04 LTS'
VERSION_CODENAME=noble
EOF
t_eq "os_release: 双引号值" "ubuntu" "$(uxs_os_release ID "$FIX")"
t_eq "os_release: 版本" "24.04" "$(uxs_os_release VERSION_ID "$FIX")"
t_eq "os_release: 单引号含空格" "Ubuntu 24.04 LTS" "$(uxs_os_release PRETTY_NAME "$FIX")"
t_eq "os_release: 无引号值" "noble" "$(uxs_os_release VERSION_CODENAME "$FIX")"
t_eq "os_release: 缺失键为空" "" "$(uxs_os_release ID_LIKE "$FIX")"
t_eq "os_release: 文件不可读为空" "" "$(uxs_os_release ID /nonexistent/os-release)"
rm -f "$FIX"

# ---------- detect_distro 文件模式回归（_osr_field 引号剥离被 uxs_os_release 复用） ----------
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

echo "unit_platform(os_release): 通过 $PASS / 失败 $FAIL"
(( FAIL == 0 ))
