# ops-kit · 运维工具箱

Linux 服务器一站式日常运维：**一键巡检报告 + 日志运维 + systemd 服务管理 + 安全基线自查**。只读优先，写操作三重护栏（显式参数 + 交互确认 + `--dry-run`）。

## 用法

```bash
./install.sh ops-kit inspect               # 聚合巡检（默认动作，只读）
./install.sh ops-kit inspect --json        # 机器可读巡检结果（AI/CI 友好）
./install.sh ops-kit log status            # journal 占用 + /var/log 大户 TOP5
./install.sh ops-kit log vacuum 200M       # 清理 journald（写操作，需交互确认）
./install.sh ops-kit log rotate list       # 查看 /etc/logrotate.d 现有条目
./install.sh ops-kit log rotate apply nginx  # 按内置模板生成 logrotate 条目
./install.sh ops-kit svc failed            # systemd 失败单元排查（unit/状态/journal 尾行）
./install.sh ops-kit svc logs nginx.service 100  # 查看服务日志
./install.sh ops-kit svc restart nginx.service   # systemctl 透传（危险动作需确认）
./install.sh ops-kit audit all             # SSH 基线 + 公网端口 + 待更新（只读）
./install.sh ops-kit status                # 依赖齐备度（UXS_STATUS_MODE=machine 机器可读）
```

## inspect 巡检项与分级

| 检查项 | 分级 |
|--------|------|
| 磁盘空间（df，剔除 tmpfs/overlay） | >80% ⚠️ / >90% 🔴 |
| SMART 总评（装了 smartmontools 才查） | PASSED ✅ / 其余 🔴 / 缺工具 ⬜ 跳过 |
| systemd 失败单元 | 0 ✅ / >0 🔴 |
| journal 占用 | >2G ⚠️ |
| SSH 基线摘要 | 取各键最大等级 |
| 公网监听（0.0.0.0/[::]） | 无 ✅ / 有 ⚠️ |
| 待更新（apt/dnf/yum/pacman/apk，只计数） | >50 🔴 / >0 ⚠️ |
| 登录失败（lastb） | 0 ✅ / >0 ⚠️ |

任一检查项依赖缺失即降级为 ⬜「跳过」，不中止整体；退出码恒 0（探测语义）。

## 安全基线（audit）

- **ssh**：核对 PermitRootLogin / PasswordAuthentication / MaxAuthTries / X11Forwarding 对照推荐值；加固指路 `./install.sh sys-setup ssh`
- **ports**：公网监听清单（进程/端口）；收口指路 `./install.sh ufw`
- **updates**：待更新计数；自动安装指路 `./install.sh sys-setup unattended`

## 护栏

- `log vacuum` / `log rotate apply` / `svc stop|restart|disable`：显式参数必填；非交互终端直接拒绝；交互终端需输入 yes 确认
- 全局 `--dry-run` 下写操作只打印不执行（sudo 被 lib/common.sh 遮蔽降级）
- 无 systemd 环境（容器/alpine）：相关项优雅降级，`status`/`help` 恒可用

## 平台

仅 Linux（依赖 systemd 工具链）。macOS 输出"不适用"退出 0。
