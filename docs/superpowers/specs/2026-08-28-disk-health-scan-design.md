# 设计：disk 模块健康诊断升级——smart 判定 + scan 坏块扫描

**日期**: 2026-08-28
**状态**: 设计已确认（用户拍板：扩展 disk 模块 / 只读扫描 / 前台运行 / 双子命令）
**作者**: brainstorming 会话产出
**分支**: `feat/disk-health-scan`（基于 `release/v1.10.0`，因 disk 模块 #41 尚未合入 main）

---

## 背景与动机

v1.10.0 的 `sys-tools/disk` 已提供分区/格式化/挂载/fstab/擦除一站式管理，其中的 `smart` 子命令只是把 `smartctl -H`/`-A` 的输出原样打印——用户要自己看懂英文属性表才能得出结论，且**完全不覆盖盘面坏块检测**（SMART 自评不扫描盘面，盘上已有坏块但尚未触发重映射判定时总评仍可能是 PASSED）。

本次把 disk 模块升级为真正的"故障检查"工具：

1. `smart` 从"原样输出"升级为"逐项判读 + 中文结论"，支持无参数全盘概览；
2. 新增 `scan` 子命令，用 `badblocks` 只读扫描盘面坏块（固态/机械通吃）。

## 目标

- `disk smart`（无参）：遍历所有整盘，每盘一行健康结论（典型用法：跑一遍看全盘概览）。
- `disk smart <整盘>`：单盘详情——smartctl 总评 + 关键属性逐项判读 + 分级结论（✅健康/🟡注意/🔴危险）。
- `disk scan <整盘|分区>`：badblocks 只读坏块扫描，实时进度，结束输出坏块数与建议。
- 机器可读：`smart` 子命令支持 `UXS_STATUS_MODE=machine` 输出每盘判定（便于脚本消费）。
- 全程只读：不提供任何写盘模式，扫描对数据零风险。

## 非目标（YAGNI，刻意不做）

| 不做 | 原因 |
|------|------|
| badblocks 写测试（`-n`/`-w`） | 有数据风险；只读扫描已覆盖"故障检查"诉求 |
| 后台扫描 + 进度/结果查询命令 | 复杂度显著上升；文档提示长扫描放 tmux/screen 即可 |
| 模块级 `status` 加健康字段 | smartctl 读设备需要 sudo，不适合 `--status-json` 快速契约 |
| nvme-cli 依赖 | NVMe 统一走 smartctl（对 NVMe 支持良好），不引第二个包 |
| 定时自动扫描 / 邮件告警 | 超出脚本库定位 |

## 详细设计

### 1. `smart` 子命令（升级 `cmd_smart`）

```
disk smart            # 无参：所有整盘逐块概览（每盘一行：设备/型号/容量/结论）
disk smart <整盘>     # 单盘详情：总评 + 关键属性判读 + 结论
```

**判定核心**：抽纯函数 `_smart_verdict`（输入：smartctl 输出文本 + 盘类型；输出：verdict + 原因列表），SATA/机械（ATA 属性表）与 NVMe 各一套判读规则：

| 分级 | ATA 条件（属性 raw 值判读） | NVMe 条件 |
|------|-----------------------------|-----------|
| 🔴 危险（critical） | 总评 FAILED；或 197 Current_Pending / 198 Offline_Uncorrectable / 187 Reported_Uncorrect >0 | critical_warning≠0；media_errors>0；Available Spare 低于阈值 |
| 🟡 注意（warning） | 5 Reallocated_Sector / 196 Reallocation_Event >0（盘在自愈，关注趋势） | Percentage Used ≥90% |
| 🟡 未知（unknown） | USB 桥/RAID 背板导致读不到属性表 | 同左 |
| ✅ 健康（healthy） | 总评 PASSED 且上述全 0 | 总评 PASSED 且上述全干净 |

- ATA 属性解析对 `-A` 表做 `awk` 行匹配（ID + NAME + RAW 值列），raw 值语义：这些计数属性 0 即健康、>0 即有事件。不追求 48 位打包值的极端特例（主流判读即如此）。
- NVMe 指标从 `smartctl -A` 的 NVMe 输出解析（`Critical Warning`/`Media and Data Integrity Errors`/`Available Spare`/`Percentage Used`）。
- 单盘详情额外展示：温度、通电时长、主寄存器读写量（信息性，不参与判定）。
- 机器模式（`UXS_STATUS_MODE=machine`）：概览每盘输出 `STATE=<verdict>` + `EXTRA=dev=... model=... reasons=...`；人类模式保持带颜色 emoji 的结论行。
- smartmontools 缺失时沿用现状自动补装。

### 2. `scan` 子命令（新增 `cmd_scan`）

```
disk scan <整盘|分区>
```

- 实现：`badblocks -sv -b 4096 <dev>` 只读扫描（`-s` 进度、`-v` 详细、坏块清单落临时文件）。
- 依赖：`badblocks` 属 e2fsprogs（ext4 必备包，发行版基本预装），缺失时 `pkg_install e2fsprogs` 自动补装。
- 扫描前：展示 `_disk_show_detail` 设备详情 + 按容量估算耗时（按 ~150MB/s 折算，机械盘 TB 级数小时）+ 提示长扫描建议 tmux/screen。
- **护栏策略（与破坏性操作不同）**：只读扫描**不走** `_disk_guard_destructive`——不拒绝任何设备；但若目标在使用中（挂载/swap/LVM）或属系统盘，打印黄字警告"IO 竞争会显著变慢"后继续。输出中明确声明"只读扫描，不写盘"。
- 扫描后：
  - 0 坏块 → 绿色"盘面完好"结论；
  - >0 → 红色危险结论 + 坏块 LBA 清单 + 建议（立即备份 → `disk smart` 查重映射趋势 → 评估换盘）。
- 退出码沿用 badblocks 语义：发现坏块退出非 0（注意 `set -e` 下用 `||` 捕获后判定，不中断脚本）。
- Ctrl-C 中断友好：已扫描进度随 badblocks 自身输出保留。

### 3. 配套改动

- `usage()`：smart 两行用法 + scan 条目 + 安全护栏说明补充"scan 为只读"。
- `lib/submenus.sh` 的 `manage_disk()` 子菜单加 `scan` 条目。
- 模块 `README.md`、CHANGELOG `[Unreleased]` 新增条目。
- `cmd_status` 不改动（见非目标）。

## 错误处理

| 场景 | 行为 |
|------|------|
| macOS / 非 Linux | 沿用 `_linux_require`，报"仅支持 Linux"返回 1 |
| 设备不存在/非块设备 | `_disk_resolve` 报错返回 1 |
| smartctl 读不到（USB 桥等） | verdict=unknown，黄字提示，退出 0（探测性结论而非失败） |
| badblocks 缺失 | 自动补装 e2fsprogs 后继续 |
| 扫描被中断 | 提示已扫描部分无效，可直接重跑 |

## 测试策略

1. **纯函数桩单测**（CI 可跑）：`_smart_verdict` 及 ATA/NVMe 解析函数，用固定 smartctl 输出样本覆盖四类：健康 ATA / 危险 ATA（pending>0）/ 注意 ATA（重映射>0）/ NVMe media_errors>0 / USB unknown；坏块计数与退出码逻辑单测。
2. **静态**：bash -n + shellcheck 干净（`tests/ci_run.sh --phase static`）。
3. **routing**：子命令路由、usage 文案、菜单入口（`--phase routing`）。
4. **远程真机**（murphy-server 192.168.108.66）：`smart sda`/`smart sdb` 真盘直跑核对判定；`scan` 用 loopback 设备验证全链路（真盘全盘扫描太慢）；对真实分区跑短时扫描确认进度输出后中断。

## 分支与发布策略

- 基于 `origin/release/v1.10.0` 开 `feat/disk-health-scan`（disk 模块 #41 目前只在该分支，main 未合入）。
- 发布顺序：disk 模块先进 main 后，本分支 rebase 后独立 PR（与 `2026-08-28-disk-module-design.md` 的交付物同源演进）。
- 与 main 上进行中的 mirror-matrix 工作互不触碰（worktree 隔离）。
