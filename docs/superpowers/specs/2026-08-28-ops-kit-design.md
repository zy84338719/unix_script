# ops-kit 运维工具箱 设计

日期：2026-08-28 · 状态：已批准 · 目标版本：v1.12.0

## 背景与目标

现有 53 模块的运维能力呈点状分布：诊断靠 sys-cmd（瞬时快照）、磁盘有 disk/disk-usage、安全有 ufw/fail2ban，但**巡检聚合、日志运维、systemd 服务运维、安全基线自查**四块空白。本设计新增一个运维工具箱模块 `sys-tools/ops-kit` 补齐。

目标：一条命令看清系统健康（巡检），并提供日志/服务/安全三组日常运维动作。只读优先、写操作有护栏。

## 非目标（YAGNI）

- 不做定时巡检、不落盘快照（需要时用户自接 cron）
- 不自动修复：audit/inspect 只报告 + 指向既有模块（sys-setup ssh / ufw / sys-setup unattended）
- 不重复管理 fail2ban/ufw 配置

## 定位与注册表

- `sys-tools/ops-kit/`，单文件 `install.sh` + `.manifest`（学 sys-cmd 的"多子命令工具箱"模式）
- Linux-only：systemd 为骨干；macOS 输出"不适用"；无 systemd 环境（alpine/部分容器）各检查项优雅降级为"不可用"，status/help 正常退出 0
- `.manifest`：`LABEL=运维工具箱` `CATEGORY=系统工具` `ALIASES=ops,opskit` `DEFAULT_ACTION=inspect`（只读，非交互安全）`DESC` `HAS_SUBMENU=ops-kit`（入口函数 `manage_ops_kit`）

## 子命令接口

统一契约四件套之外，扩展子命令：

```
ops-kit inspect [--json]                          # 聚合巡检（默认动作，只读）
ops-kit log    status|vacuum <N M|Nweeks>|rotate list|show|apply <app>
ops-kit svc    failed|status <unit>|logs <unit> [n]|start|stop|restart|enable|disable <unit>
ops-kit audit  ssh|ports|updates|all              # 只读
ops-kit install|uninstall|status|help
```

### inspect 聚合巡检

固定检查项，每项分级 ✅/⚠️/🔴/跳过，末尾汇总行（🔴 n ⚠️ m）：

| 检查项 | 数据源 | 分级 |
|--------|--------|------|
| 磁盘空间 | `df`（物理文件系统，排除 tmpfs/overlay） | >80% ⚠️ / >90% 🔴 |
| SMART 总评 | `smartctl -H`（存在才查，逐整盘） | PASSED ✅ / 其余 🔴 / 缺工具 跳过 |
| systemd 失败单元 | `systemctl --failed --no-legend` | 0 ✅ / >0 🔴 |
| journal 占用 | `journalctl --disk-usage` 解析 | >2G ⚠️ |
| SSH 基线 | 同 audit ssh（摘要行） | 汇最大等级 |
| 公网监听 | `ss -tulpn` 中 0.0.0.0/[::] 项 | 仅有 127.0.0.1 监听 ✅；有公网监听 ⚠️（清单） |
| 待更新 | apt/dnf/yum/pacman/apk 计数（只计数） | >0 ⚠️（>50 🔴） |
| 登录失败 | `lastb`（存在才查，近 50 条计数） | 0 ✅ / >0 ⚠️ |

`--json` 输出结构化结果（`{"checks":[{name,level,detail}], "summary":{...}}`），供 AI/CI 消费（模块级 --json 有 zsh-setup 先例）。任一检查项内部失败不中止整体——分级记"跳过"，退出码始终 0（探测语义）。

### log 日志运维

- `status`（只读）：journal 磁盘占用 + /var/log 大户 top5（du）
- `vacuum <200M|2weeks>`：`journalctl --vacuum-size/--vacuum-time`。**写操作**：显式参数必填（无参数报用法）、交互终端二次确认、非交互拒绝（学 disk 护栏）、`--dry-run` 下仅打印将执行的命令
- `rotate list|show <app>|apply <app>`：查看现有 `/etc/logrotate.d/`；`apply` 按内置模板（nginx/redis/journal 等常见服务）生成条目——写前备份原文件、预览确认、`--dry-run` 支持

### svc 服务运维

- `failed`：失败单元汇总（unit 名 + since + journal 尾行 3 行）——排障第一入口
- `logs <unit> [n]`：`journalctl -u <unit> -n <n|50> --no-pager`
- `status|start|stop|restart|enable|disable <unit>`：透传 systemctl，输出统一格式
- 写操作（start/stop/restart/enable/disable）走全局 `--dry-run` 机制；stop/disable 在交互终端确认一次

### audit 安全基线

纯只读，每项给 ⚠️/🔴 + 修复指路：

- `ssh`：从 `sshd -T`（root 可用时）或 sshd_config 解析 PermitRootLogin / PasswordAuthentication / MaxAuthTries / X11Forwarding / ClientAliveInterval；对照推荐值分级；建议行指向 `./install.sh sys-setup ssh`
- `ports`：公网监听清单（进程/端口），建议收口指向 `./install.sh ufw`
- `updates`：待更新计数 + 安全更新计数（apt-security/dnf-security 可分辨时标注）；安装指向 `sys-setup unattended`
- `all`：依序执行三项

## 护栏与降级原则

1. 只读命令永不改系统；写操作三件套：显式参数 + 交互确认 + --dry-run
2. 依赖缺失（smartctl/lastb/sshd 等）→ 该项"跳过/不可用"，不报错不中止
3. 无 systemd → inspect 相关项"不可用"，svc 提示环境不支持，status/help 正常
4. 全程遵守 `NO_COLOR` / `UXS_STATUS_MODE=machine` / `UXS_DEBUG` 等库约定；status 用 `emit_status` 契约输出依赖齐备度

## 测试策略

学 disk 模块 stub 套路：

- 纯函数单测 `tests/unit_ops_kit.sh`：df/lastb/journalctl 解析、分级阈值、--json 结构、sshd_config 解析（stub 输入）
- routing 断言：manifest 字段、子命令枚举完整（供 --list-modules/补全解析）、护栏结构（vacuum 无参数拒绝、交互确认文案）、单测全过
- alpine（无 systemd）腿：status/help 退出 0（降级路径），routing 的 status 契约循环天然覆盖
- 模块内 `UXS_STATUS_MODE=machine` 输出 `STATE=` + `EXTRA=`（依赖齐备度）

## 实现量

单文件约 700-900 行（对标 disk），submenu 回调（lib/submenus.sh 注册 manage_ops_kit）、README、manifest、单测、routing 断言。
