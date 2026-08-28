#!/usr/bin/env bash
#
# tests/unit_disk_smart.sh — sys-tools/disk SMART 判定纯函数单测
# 独立运行：bash tests/unit_disk_smart.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
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

# source 模块脚本取纯函数（source 后关闭 -e/-o pipefail，保留 -u，避免被测函数的预期非零返回中止测试）
# shellcheck source=../sys-tools/disk/install.sh
source "$REPO_DIR/sys-tools/disk/install.sh"
set +e +o pipefail

# ---------- fixtures ----------
ATA_H_PASSED='SMART overall-health self-assessment test result: PASSED'
ATA_H_FAILED='SMART overall-health self-assessment test result: FAILED!'
ATA_A_HEADER='ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE'
ATA_A_HEALTHY=$(printf '%s\n  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always   -           0\n187 Reported_Uncorrect      0x0032   100   100   000    Old_age   Always   -           0\n196 Reallocated_Event_Count 0x0032   100   100   000    Old_age   Always   -           0\n197 Current_Pending_Sector  0x0022   100   100   000    Old_age   Always   -           0\n198 Offline_Uncorrectable   0x0008   100   100   000    Old_age   Offline  -           0\n' "$ATA_A_HEADER")
ATA_A_PENDING=$(printf '%s\n197 Current_Pending_Sector  0x0022   088   088   000    Old_age   Always   -           8\n' "$ATA_A_HEADER")
ATA_A_REALLOC=$(printf '%s\n  5 Reallocated_Sector_Ct   0x0033   092   092   010    Pre-fail  Always   -           24\n' "$ATA_A_HEADER")
NVME_A_HEALTHY='Critical Warning:                   0x00
Available Spare:                    100%
Available Spare Threshold:          10%
Percentage Used:                    2%
Media and Data Integrity Errors:    0'
NVME_A_MEDIA='Critical Warning:                   0x00
Percentage Used:                    88%
Media and Data Integrity Errors:    24'
NVME_A_WORN='Critical Warning:                   0x00
Percentage Used:                    95%
Media and Data Integrity Errors:    0'
NVME_A_SPARE='Critical Warning:                   0x00
Available Spare:                    5%
Available Spare Threshold:          10%
Percentage Used:                    40%
Media and Data Integrity Errors:    0'

# ---------- 解析 helper ----------
t_eq "ata_raw: 5 号属性取 RAW" "24" "$(_smart_ata_raw "$ATA_A_REALLOC" 5)"
t_eq "ata_raw: 缺失属性为空" "" "$(_smart_ata_raw "$ATA_A_HEALTHY" 12)"
t_eq "ata_raw: 健康 0" "0" "$(_smart_ata_raw "$ATA_A_HEALTHY" 197)"
t_eq "nvme_val: Percentage Used" "95%" "$(_smart_nvme_val "$NVME_A_WORN" "Percentage Used:")"
t_eq "nvme_val: 不误配 Threshold 前缀" "10%" "$(_smart_nvme_val "$NVME_A_SPARE" "Available Spare Threshold:")"
t_eq "health_word: FAILED!→FAILED" "FAILED" "$(_smart_health_word "$ATA_H_FAILED")"
t_eq "pct: 去百分号" "95" "$(_smart_pct "95%")"
t_eq "num_gt: 空=0 不大于 0" "rc1" "$(_smart_num_gt "" 0 && echo rc0 || echo rc1)"

# ---------- verdict：ATA ----------
t_eq "ATA 全 0 → healthy" "healthy|" "$(_smart_verdict "$ATA_H_PASSED" "$ATA_A_HEALTHY" ata)"
t_eq "ATA pending>0 → critical" "critical|待定扇区(Current_Pending)=8" "$(_smart_verdict "$ATA_H_PASSED" "$ATA_A_PENDING" ata)"
t_eq "ATA 重映射>0 → warning" "warning|重映射扇区(Reallocated_Sector)=24" "$(_smart_verdict "$ATA_H_PASSED" "$ATA_A_REALLOC" ata)"
t_eq "ATA 总评 FAILED → critical" "critical|SMART 总评 FAILED" "$(_smart_verdict "$ATA_H_FAILED" "$ATA_A_HEALTHY" ata)"
t_eq "ATA 读不到 → unknown" "unknown|读不到 SMART 数据（USB 桥/RAID 背板不支持或权限不足）" "$(_smart_verdict "" "" ata)"

# ---------- verdict：NVMe ----------
t_eq "NVMe 干净 → healthy" "healthy|" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_HEALTHY" nvme)"
t_eq "NVMe media>0 → critical" "critical|介质错误(Media Errors)=24" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_MEDIA" nvme)"
t_eq "NVMe 寿命≥90 → warning" "warning|寿命已耗 95%" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_WORN" nvme)"
t_eq "NVMe 备用空间低于阈值 → critical" "critical|备用空间 5% 低于阈值 10%" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_SPARE" nvme)"

# ---------- 结论 ----------
echo "unit_disk_smart: 通过 $PASS / 失败 $FAIL"
(( FAIL == 0 ))
