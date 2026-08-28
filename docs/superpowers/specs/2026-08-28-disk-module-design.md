# 磁盘管理工具箱模块设计（sys-tools/disk）

日期：2026-08-28
状态：已确认（用户选定：完整工具箱 + 新盘向导 + 严格护栏）

## 目标

为 Linux 服务器提供新盘上线一站式能力：列盘、分区、格式化、挂载/卸载、fstab 持久化、SMART 健康、擦除签名。CLI 子命令与交互子菜单双轨。

## 形态

- 目录 `sys-tools/disk/`：`.manifest` + `install.sh` + `README.md`
- `.manifest`：`LABEL=磁盘管理`、`HAS_SUBMENU=disk`、`DEFAULT_ACTION=list`（非交互默认列盘，最安全）
- 子菜单入口 `manage_disk()`（遵守 `manage_<HAS_SUBMENU>` 命名约定，CI 已有全局一致性断言）
- 仅 Linux；macOS 下 `status` 输出 `STATE=n/a` 退出 0，其余子命令报错退出非 0

## 子命令

| 子命令 | 功能 |
|---|---|
| `list` | lsblk 列盘 + 受保护设备清单 |
| `wizard` | 新盘上线向导：选盘 → GPT 单分区 → 选文件系统 → 挂载点 → fstab（UUID）→ `mount -a` 验证 |
| `partition <盘>` | GPT 单分区全盘（parted，先 wipefs 清签名） |
| `format <设备> [类型]` | ext4（默认）/xfs/vfat/exfat/ntfs；缺工具自动补装 |
| `mount <设备> <挂载点> [--fstab]` | 挂载；`--fstab` 顺带持久化（含验证+回滚） |
| `umount <挂载点\|设备>` | 卸载 |
| `fstab list\|add\|remove` | UUID 方式管理 fstab；写前备份 `fstab.bak.<ts>`、写后 `mount -a` 验证失败自动回滚 |
| `smart <盘>` | smartctl -H/-A；未装 smartmontools 时自动补装 |
| `wipe <设备>` | wipefs -a 清文件系统签名 |
| `install` | 按发行版补装 parted/xfsprogs/dosfstools/exfatprogs/ntfs-3g/smartmontools |
| `uninstall` | 移除上述辅助工具包（含确认；不碰任何磁盘数据与 fstab） |
| `status` | 机器可读：核心工具（lsblk/parted/mkfs.ext4）齐备 → installed，否则 not_installed；EXTRA 报可选工具缺失与整盘数 |

## 严格护栏（三层，无 --yes 绕过）

1. **硬拒绝（代码保证，不可达）**：根分区、`/boot`、`/boot/efi`、激活 swap，以及它们所在的**整块盘**（经 PKNAME 反查基盘）；使用中设备（有挂载点 / swap 激活 / raid·lvm 成员签名）
2. **交互确认**：format/partition/wipe/wizard 仅允许交互终端（`[[ -t 0 ]]`）；执行前展示目标设备详情（SIZE/TYPE/FSTYPE/LABEL/MOUNTPOINT/MODEL），要求**手动输入完整设备名**且与目标一致
3. **回滚**：fstab 写入前备份，`mount -a` 验证失败自动恢复备份

## 错误处理

- 设备不存在/非块设备/输入不一致 → 报错退出非 0，不产生任何副作用
- parted/mkfs 失败 → set -e 中止，已完成的步骤保留（可单独续跑子命令）
- smartctl 健康异常时 exit 非零是正常语义 → `|| true` 以输出为准

## 测试

- routing 阶段：status/help exit 0 + `set -u` 契约（注册表驱动，容器矩阵自动覆盖各发行版）；HAS_SUBMENU ↔ manage_disk 一致性由既有全局断言覆盖
- 新增断言：manifest 字段、usage 子命令枚举（供 --list-modules/补全解析）
- 破坏性路径无法在 CI 真跑：护栏判定做成纯函数（`_disk_is_protected`/`_disk_in_use`），本地可用临时块设备或观察输出验证；CI 以静态 grep 断言护栏代码存在
