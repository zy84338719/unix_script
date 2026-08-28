# disk · 磁盘管理工具箱

Linux 服务器磁盘一站式管理：列盘 / 分区 / 格式化 / 挂载 / fstab 持久化 / SMART 健康 / 坏块扫描 / 擦除签名。交互菜单与 CLI 双轨（主菜单 → 系统工具 → 磁盘管理）。

## 用法

```bash
./install.sh disk list                 # 列出块设备 + 受保护设备
./install.sh disk wizard               # 新盘一键上线：分区→格式化→挂载→fstab
./install.sh disk partition sdb        # GPT 单分区全盘
./install.sh disk format sdb1 xfs      # 格式化（ext4/xfs/vfat/exfat/ntfs，默认 ext4）
./install.sh disk mount sdb1 /data --fstab   # 挂载并持久化
./install.sh disk umount /data         # 卸载
./install.sh disk fstab list|add|remove
./install.sh disk smart                # SMART 体检：全部整盘一行式概览
./install.sh disk smart sda            # SMART 体检：单盘详情 + 判读结论
./install.sh disk scan sdb             # 盘面坏块只读扫描（分区 sdb1 也可）
./install.sh disk wipe sdb1            # 清除文件系统签名
./install.sh disk status               # 依赖齐备度（UXS_STATUS_MODE=machine 机器可读）
```

## 健康体检与坏块扫描

- **`smart [整盘]`**：SMART 健康体检。无参数=遍历全部整盘输出一行式概览（✅健康/🟡注意/🔴危险/未知 + 原因）；指定整盘=详情（设备信息、总评、温度/通电时长、属性表 + 判读结论）。
  - 判读规则：ATA 看 5/196 重映射（→注意）、187/197/198 不可纠正与待定扇区（→危险）；NVMe 看 critical_warning、介质错误、备用空间低于阈值（→危险）、寿命耗用 ≥90%（→注意）。
  - `UXS_STATUS_MODE=machine` 下输出 `STATE=<verdict>` + `EXTRA=dev=... model=... reasons=...`。
  - 判读支持 ATA/NVMe；SAS 盘仅总评可判。smartctl 自动探测失败（SAT 层提示）时自动以 `-d ata` 重试。
- **`scan <整盘|分区>`**：盘面坏块只读扫描（`badblocks -sv`，**不写盘**，数据零风险）。扫描前展示设备详情与按容量的耗时预估（~150MB/s 折算）；使用中/系统盘仅警告 IO 竞争不拒绝。发现坏块时列出 LBA 清单并给出备份/查 SMART/换盘建议，退出码非 0；0 坏块退出 0。TB 级机械盘可能耗时数小时，建议放 tmux/screen。

## 安全护栏（严格，无 --yes 绕过）

1. **硬拒绝**：根分区、`/boot`、`/boot/efi`、激活 swap 及其**所在整盘**禁止破坏性操作；使用中设备（已挂载 / 激活中的 LVM LV·RAID）硬拒绝，且**逐条列出占用详情**（哪个分区已挂载、哪个是 LVM PV 及其 VG、哪个被激活的内核设备持有）与解除方法
2. **输入确认**：破坏性操作仅限交互终端，执行前展示设备详情，需手动输入完整设备名（如 `sdb`）确认
3. **wipe 特例**：设备无任何挂载、无激活占用时，允许 `wipe` 清除旧签名（swap / LVM PV 残留）——擦签名正是解除它们的操作；format/partition 仍会被旧签名阻断并提示先用 wipe 解除
4. **回滚**：fstab 写入前备份 `/etc/fstab.bak.<ts>`，`mount -a` 验证失败自动恢复
5. **只读体检例外**：`smart`/`scan` 不写盘，不受上述破坏性护栏限制；`scan` 对使用中设备仅警告

## 依赖

`install` 子命令按发行版补装：parted / xfsprogs / dosfstools / exfatprogs / ntfs-3g / smartmontools（lsblk 等 util-linux 工具系统自带；`scan` 用的 badblocks 属 e2fsprogs，缺了也会自动补装）。缺失的可选工具在对应功能首次使用时也会自动补装。
