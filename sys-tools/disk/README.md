# disk · 磁盘管理工具箱

Linux 服务器磁盘一站式管理：列盘 / 分区 / 格式化 / 挂载 / fstab 持久化 / SMART 健康 / 擦除签名。交互菜单与 CLI 双轨（主菜单 → 系统工具 → 磁盘管理）。

## 用法

```bash
./install.sh disk list                 # 列出块设备 + 受保护设备
./install.sh disk wizard               # 新盘一键上线：分区→格式化→挂载→fstab
./install.sh disk partition sdb        # GPT 单分区全盘
./install.sh disk format sdb1 xfs      # 格式化（ext4/xfs/vfat/exfat/ntfs，默认 ext4）
./install.sh disk mount sdb1 /data --fstab   # 挂载并持久化
./install.sh disk umount /data         # 卸载
./install.sh disk fstab list|add|remove
./install.sh disk smart sda            # SMART 健康检查
./install.sh disk wipe sdb1            # 清除文件系统签名
./install.sh disk status               # 依赖齐备度（UXS_STATUS_MODE=machine 机器可读）
```

## 安全护栏（严格，无 --yes 绕过）

1. **硬拒绝**：根分区、`/boot`、`/boot/efi`、激活 swap 及其**所在整盘**禁止破坏性操作；使用中设备（已挂载 / swap / raid·lvm 成员）硬拒绝
2. **输入确认**：破坏性操作仅限交互终端，执行前展示设备详情，需手动输入完整设备名（如 `sdb`）确认
3. **回滚**：fstab 写入前备份 `/etc/fstab.bak.<ts>`，`mount -a` 验证失败自动恢复

## 依赖

`install` 子命令按发行版补装：parted / xfsprogs / dosfstools / exfatprogs / ntfs-3g / smartmontools（lsblk 等 util-linux 工具系统自带）。缺失的可选工具在对应功能首次使用时也会自动补装。
