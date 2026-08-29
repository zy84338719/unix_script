#!/usr/bin/env bash
#
# tests/unit_ops_kit.sh — sys-tools/ops-kit 纯函数与命令行为单测
# 独立运行：bash tests/unit_ops_kit.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
t_eq() {
    if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $1  期望='$2' 实际='$3'"; fi
}
# source 模块脚本取纯函数（source 后关闭 -e/-o pipefail，保留 -u）
# shellcheck source=../sys-tools/ops-kit/install.sh
source "$REPO_DIR/sys-tools/ops-kit/install.sh"
set +e +o pipefail

# ---------- fixtures ----------
DF_FIX=$(printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sda1  100 95 5 95%% /\ntmpfs 100 1 99 1%% /dev/shm\noverlay 100 50 50 50%% /var/lib/docker\n/dev/sdb1 100 82 18 82%% /data\n')
J1='Archived and active journals take up 3.9G in the file system.'
J2='Archived and active journals take up 512M in the file system.'
SS_FIX=$(printf 'Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\ntcp LISTEN 0 511 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3))\ntcp LISTEN 0 511 127.0.0.1:9000 0.0.0.0:* users:(("app",pid=2,fd=3))\nudp UNCONN 0 0 [::]:51820 [::]:* users:(("wg",pid=3,fd=5))\n')
LASTB_FIX=$(printf 'root ssh:noserver 1.2.3.4 Mon Jan 1 00:00 - 00:00 (00:00)\nadmin ssh:noserver 5.6.7.8 Mon Jan 1 00:01 - 00:00 (00:00)\n\nbtmp begins Mon Jan 1 00:00:00 2026\n')
FAILED_FIX=$(printf '  nginx.service loaded failed failed A high performance web server\n  0 loaded units listed.\n')
SSHD_T_FIX=$(printf 'permitrootlogin yes\npasswordauthentication no\nmaxauthtries 10\nx11forwarding no\n')
UPD_FIX=$(printf '30 packages can be upgraded.\n')

# ---------- _ops_size_to_mb ----------
t_eq "size: 3.9G→3993（截断）" "3993" "$(_ops_size_to_mb 3.9G)"
t_eq "size: 512M→512" "512" "$(_ops_size_to_mb 512M)"
t_eq "size: 1024K→1" "1" "$(_ops_size_to_mb 1024K)"
t_eq "size: 2T→2097152" "2097152" "$(_ops_size_to_mb 2T)"
t_eq "size: 空→0" "0" "$(_ops_size_to_mb "")"
t_eq "size: 垃圾→0" "0" "$(_ops_size_to_mb abc)"

# ---------- _ops_df_parse ----------
t_eq "df: 只留真实文件系统两行" "2" "$(printf '%s\n' "$(_ops_df_parse "$DF_FIX")" | grep -c '|')"
t_eq "df: / 95" "/|95" "$(printf '%s\n' "$(_ops_df_parse "$DF_FIX")" | grep '^/|' | head -1)"
t_eq "df: /data 82" "/data|82" "$(printf '%s\n' "$(_ops_df_parse "$DF_FIX")" | grep '^/data|')"

# ---------- journal ----------
t_eq "journal: 3.9G" "3.9G" "$(_ops_journal_usage_parse "$J1")"
t_eq "journal: 512M" "512M" "$(_ops_journal_usage_parse "$J2")"
t_eq "journal: 空输出→空" "" "$(_ops_journal_usage_parse '')"

# ---------- ss ----------
t_eq "ss: 保留 LISTEN 2 行（UNCONN 剔除）" "2" "$(printf '%s\n' "$(_ops_ss_parse "$SS_FIX")" | grep -c '|')"
t_eq "ss: sshd 行" 'tcp|0.0.0.0:22|sshd' "$(printf '%s\n' "$(_ops_ss_parse "$SS_FIX")" | grep sshd)"

# ---------- 地址判定 ----------
t_eq "addr: 0.0.0.0 是公网" "rc0" "$(_ops_is_public_addr '0.0.0.0:22' && echo rc0 || echo rc1)"
t_eq "addr: [::] 是公网" "rc0" "$(_ops_is_public_addr '[::]:51820' && echo rc0 || echo rc1)"
t_eq "addr: 127.0.0.1 不是" "rc1" "$(_ops_is_public_addr '127.0.0.1:9000' && echo rc0 || echo rc1)"
t_eq "addr: 192.168 不是" "rc1" "$(_ops_is_public_addr '192.168.1.5:80' && echo rc0 || echo rc1)"

# ---------- lastb / failed ----------
t_eq "lastb: 计数 2" "2" "$(_ops_lastb_count "$LASTB_FIX")"
t_eq "failed: 取 unit 名" "nginx.service" "$(_ops_failed_units "$FAILED_FIX" | head -1)"

# ---------- sshd ----------
t_eq "sshd: root=yes→crit" "crit|permitrootlogin=yes" "$(printf '%s\n' "$(_ops_sshd_check "$SSHD_T_FIX")" | grep permitrootlogin)"
t_eq "sshd: passwd=no→ok" "ok|passwordauthentication=no" "$(printf '%s\n' "$(_ops_sshd_check "$SSHD_T_FIX")" | grep passwordauthentication)"
t_eq "sshd: tries=10→warn" "warn|maxauthtries=10" "$(printf '%s\n' "$(_ops_sshd_check "$SSHD_T_FIX")" | grep maxauthtries)"
t_eq "sshd: tries=3→ok" "ok|maxauthtries=3" "$(printf '%s\n' "$(_ops_sshd_check 'maxauthtries 3')" | grep maxauthtries)"
t_eq "sshd: tries=99→crit" "crit|maxauthtries=99" "$(printf '%s\n' "$(_ops_sshd_check 'maxauthtries 99')" | grep maxauthtries)"
t_eq "sshd: x11=yes→warn" "warn|x11forwarding=yes" "$(printf '%s\n' "$(_ops_sshd_check 'x11forwarding yes')" | grep x11forwarding)"

# ---------- updates / json ----------
t_eq "updates: 30" "30" "$(_ops_updates_count "$UPD_FIX")"
t_eq "updates: 空→0" "0" "$(_ops_updates_count '')"
t_eq "updates: 无数字→0" "0" "$(_ops_updates_count 'nothing here')"
t_eq "json_escape: 引号斜杠剔除保留空格" "ab cd" "$(_ops_json_escape 'a"b c\d')"
t_eq "json_escape: 空" "" "$(_ops_json_escape '')"

# ---------- inspect 冒烟（stub 采集命令）----------
_inspect_stub_env() {  # 建 stub PATH；echo stub 目录
    local T; T=$(mktemp -d)
    printf '#!/bin/sh\necho "Filesystem 1K Used Avail Cap Mounted"\necho "dev/sda1 100 90 10 91%% /"\n' >"$T/df"
    printf '#!/bin/sh\necho "Archived and active journals take up 300M in the file system."\n' >"$T/journalctl"
    printf '#!/bin/sh\ncase "$*" in *--failed*) echo "0 loaded units listed.";; *is-system-running*) echo "running";; esac\n' >"$T/systemctl"
    printf '#!/bin/sh\necho "Netid State Local"\necho "tcp LISTEN 127.0.0.1:9000"\n' >"$T/ss"
    chmod +x "$T"/df "$T"/journalctl "$T"/systemctl "$T"/ss
    printf '%s' "$T"
}
t_eq "inspect: 汇总行+rc0" "rc0" "$(
    T=$(_inspect_stub_env)
    out=$(PATH="$T:$PATH" cmd_inspect </dev/null 2>&1); rc=$?
    rm -rf "$T"
    if printf '%s' "$out" | grep -q '巡检汇总' && [ "$rc" -eq 0 ]; then echo rc0; else echo "$out" | tail -3; echo rc1; fi)"
t_eq "inspect: 91% 判 crit" "rc0" "$(
    T=$(_inspect_stub_env)
    out=$(PATH="$T:$PATH" cmd_inspect </dev/null 2>&1); rm -rf "$T"
    printf '%s' "$out" | grep -q '🔴' && echo rc0 || echo rc1)"
t_eq "inspect: --json 合法" "rc0" "$(
    T=$(_inspect_stub_env)
    out=$(PATH="$T:$PATH" cmd_inspect --json </dev/null 2>&1); rc=$?
    rm -rf "$T"
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^{"summary":{"crit":[0-9]*,"warn":[0-9]*},"checks":\[{.*\]}$'; then
        # 有 python3 则做严格 JSON 校验（精简容器无 python3，回退结构校验）
        if command -v python3 >/dev/null 2>&1; then
            printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1 && echo rc0 || { echo "$out"; echo rc1; }
        else
            echo rc0
        fi
    else echo "$out"; echo rc1; fi)"

# ---------- log ----------
t_eq "log: vacuum 无参数拒绝" "rc1" "$(cmd_log vacuum </dev/null >/dev/null 2>&1 && echo rc0 || echo rc1)"
t_eq "log: 护栏文案存在" "rc0" "$(grep -qF '仅允许在交互终端执行' "$REPO_DIR/sys-tools/ops-kit/install.sh" && echo rc0 || echo rc1)"
t_eq "log: vacuum dry-run 只打印" "rc0" "$(
    T=$(mktemp -d)
    printf '#!/bin/sh\ncase "$*" in *--disk-usage*) echo "take up 300M";; *vacuum*) echo vacuumed;; esac\n' >"$T/journalctl"; chmod +x "$T/journalctl"
    out=$(UNIX_SCRIPT_DRY_RUN=1 PATH="$T:$PATH" cmd_log vacuum 200M </dev/null 2>&1); rc=$?
    rm -rf "$T"
    if printf '%s' "$out" | grep -q 'dry-run' && [ "$rc" -eq 0 ]; then echo rc0; else echo "$out" | tail -3; echo rc1; fi)"
t_eq "log: rotate list 注入目录" "rc0" "$(
    T=$(mktemp -d); mkdir -p "$T/etc"; echo 'nginx{}' >"$T/etc/nginx"
    out=$(OPS_LOGROTATE_DIR="$T/etc" cmd_log rotate list </dev/null 2>&1)
    printf '%s' "$out" | grep -q nginx && echo rc0 || echo rc1)"
t_eq "log: rotate show 无参拒绝" "rc1" "$(cmd_log rotate show </dev/null >/dev/null 2>&1 && echo rc0 || echo rc1)"
t_eq "log: rotate apply 未知模板拒绝" "rc1" "$(cmd_log rotate apply nosuch </dev/null >/dev/null 2>&1 && echo rc0 || echo rc1)"

# ---------- svc ----------
t_eq "svc: failed stub 输出 unit" "rc0" "$(
    T=$(mktemp -d)
    printf '#!/bin/sh\ncase "$*" in *--failed*) echo "nginx.service loaded failed failed";; *is-system-running*) echo degraded;; esac\n' >"$T/systemctl"; chmod +x "$T/systemctl"
    printf '#!/bin/sh\necho "Aug 28 log line"\n' >"$T/journalctl"; chmod +x "$T/journalctl"
    out=$(PATH="$T:$PATH" cmd_svc failed </dev/null 2>&1); rc=$?
    rm -rf "$T"
    if printf '%s' "$out" | grep -q 'nginx.service' && [ "$rc" -eq 0 ]; then echo rc0; else echo "$out" | tail -3; echo rc1; fi)"
t_eq "svc: 无 systemd 优雅降级" "rc0" "$(
    T=$(mktemp -d)
    out=$(PATH="$T" cmd_svc failed </dev/null 2>&1); rc=$?
    rm -rf "$T"; [ "$rc" -eq 0 ] && echo rc0 || echo rc1)"
t_eq "svc: stop 无 unit 拒绝" "rc1" "$(cmd_svc stop </dev/null >/dev/null 2>&1 && echo rc0 || echo rc1)"
t_eq "svc: logs 无 unit 拒绝" "rc1" "$(cmd_svc logs </dev/null >/dev/null 2>&1 && echo rc0 || echo rc1)"

# ---------- audit ----------
t_eq "audit: ssh 输出+指路" "rc0" "$(
    T=$(mktemp -d); printf '#!/bin/sh\necho "permitrootlogin yes"\n' >"$T/sshd"; chmod +x "$T/sshd"
    out=$(PATH="$T:$PATH" cmd_audit ssh </dev/null 2>&1); rc=$?
    rm -rf "$T"
    if printf '%s' "$out" | grep -q 'permitrootlogin' && printf '%s' "$out" | grep -q 'sys-setup ssh' && [ "$rc" -eq 0 ]; then echo rc0; else echo "$out" | tail -3; echo rc1; fi)"
t_eq "audit: ports 公网清单+ufw 指路" "rc0" "$(
    T=$(mktemp -d); printf '#!/bin/sh\necho "Netid State Local"\necho "tcp LISTEN 0.0.0.0:22 sshd"\n' >"$T/ss"; chmod +x "$T/ss"
    out=$(PATH="$T:$PATH" cmd_audit ports </dev/null 2>&1); rc=$?
    rm -rf "$T"
    if printf '%s' "$out" | grep -q '0.0.0.0:22' && printf '%s' "$out" | grep -q 'ufw' && [ "$rc" -eq 0 ]; then echo rc0; else echo "$out" | tail -3; echo rc1; fi)"
t_eq "audit: updates apt 计数" "rc0" "$(
    T=$(mktemp -d); printf '#!/bin/sh\necho "Inst pkg"\necho "Inst pkg2"\n' >"$T/apt-get"; chmod +x "$T/apt-get"
    out=$(PATH="$T:$PATH" cmd_audit updates </dev/null 2>&1); rc=$?; rm -rf "$T"
    if printf '%s' "$out" | grep -q '2 个' && [ "$rc" -eq 0 ]; then echo rc0; else echo "$out" | tail -3; echo rc1; fi)"
t_eq "audit: 未知目标拒绝" "rc1" "$(cmd_audit nosuch </dev/null >/dev/null 2>&1 && echo rc0 || echo rc1)"

# ---------- 结论 ----------
echo "unit_ops_kit: 通过 $PASS / 失败 $FAIL"
(( FAIL == 0 ))
