# 平台抽象收敛：lib 动词层 + 模块 platform 拆分 — 设计

日期：2026-08-28
状态：待实现
关联：`2026-08-28-mirror-matrix-upgrade-design.md`（换源矩阵升级，本文 Phase 2 一并实现其全部内容）

## 背景与动机

讨论「是否拆分成多个项目」得出的结论：**不拆仓库**。理由：本项目是"框架 + 插件"
架构，`--status-json`、`export/apply` profile、`REQUIRES` 依赖图、bootstrap 一行
安装都要求全部模块在同一个命名空间；跨模块依赖仅 1 条（minikube→docker）；拆分
的经典动机（多团队、独立发版节奏、构建慢）一个都不占。

「不同操作系统独立维护」这一真实诉求的正确解法是**把 OS 边界放进代码，而不是
仓库边界**。现状数据（本次实测）：

| 事实 | 数据 |
|------|------|
| 统一包安装 `pkg_install` 采用率 | 18 个模块在用，仅 4 个手写 `sudo apt-get/dnf install` |
| 服务管理收敛 | **17 个模块手写 `systemctl enable --now`**，仅 1 个用 `service_start` |
| 平台逻辑最重的模块 | `essentials/sys-setup/install.sh` 789 行，其中换源 ~220 行 |
| 重复造轮子 | `do_mirror` 手写一套 `. /etc/os-release` + case 发行版识别，与 lib 的 `detect_distro` 完全重复 |
| 已有但未充分利用的 lib 抽象 | `pkg_install/pkg_remove/pkg_update/pkg_installed`、`service_start/stop/is_active`、`ensure_epel` |

目标：**lib 管"动词"，模块 platform 文件管"名词"**，以 sys-setup 为样板一次做
完 A+B（避免对同一模块二次重构），样板验证后滚动推广。

## 原则

1. **归属判断标准唯一**：一段平台分支若第二个模块也会用到 → 提到 lib；只有单
   个模块用但过长 → 留在模块内拆 `platform/` 文件。
2. **存量 helper 一律不改名不改签名**（`pkg_install`、`service_start` 等保持原
   样，避免大规模 churn）；**新增 helper 统一 `uxs_` 前缀**（与 `emit_status`、
   `uxs_is_machine_mode` 一致），避免与模块函数撞名（shell 无 namespace）。
3. **对外接口零变化**：菜单、`.manifest`、`--status-json`、profile export/apply、
   模块子命令全部不动。
4. **bash 3.2 兼容**（macOS 自带 bash）：不用关联数组（`declare -A`）、不用
   `${v,,}`，与现有 lib 代码纪律一致。
5. **不做一次性全量重构**：52 个模块按"改哪个顺手迁哪个"滚动推进。

## 一、lib 层新增（方案 A）

### 1.1 `uxs_os_release <KEY> [file]`

读取 os-release 风格文件的字段值（去引号）。`file` 缺省依次找
`/etc/os-release`、`/usr/lib/os-release`；文件不可读返回空；恒返回 0。
实现上直接复用现有私有函数 `_osr_field`（同文件内可见），`detect_distro`
不动。消除模块内 `$(. /etc/os-release 2>/dev/null && echo "$ID")` 式的重复
（仅 sys-setup 就有 4 处）。

### 1.2 `uxs_svc <action> <unit>...`

systemd 服务动作封装，Linux-only：

| action | 实际执行 |
|--------|---------|
| `start` / `stop` / `restart` / `reload` | `sudo systemctl <action> <unit>` |
| `enable` / `disable` | `sudo systemctl <action> <unit>` |
| `enable-now` | `sudo systemctl enable --now <unit>` |
| `is-active` | `systemctl is-active --quiet <unit>`（判断函数，无需 sudo） |

- 内部走 `dry_run_sudo`，天然兼容 `--dry-run`（现状模块手写 `sudo systemctl`
  只靠 sudo 遮蔽函数兜底，is-active 等无 sudo 调用更是完全绕过 dry-run 语义）。
- 非 Linux（darwin）：`warn "uxs_svc 仅支持 systemd"` 并返回 1。
- 与 `service_start/stop/is_active` 并存不冲突：那组是双平台签名
  （systemd_name + plist_path），给 macOS 兼容的服务模块用；Linux-only 模块
  用 `uxs_svc`，签名简单。spec 不迁移那 1 个 `service_start` 使用者。

### 1.3 本期不做的新 helper

`uxs_fw`（防火墙放行，ufw/firewalld 分发）：当前仅 2 个模块涉及
（cockpit、ufw 本身），YAGNI，列入后续评估。ufw `status` 中止
`--status-json` 的存量 bug 独立修复，不搭车。

## 二、sys-setup 样板拆分（方案 B）

> **2026-08-28 实现期修订**：换源镜像站按发行版固定（TUNA 优先，实测无货的
> 发行版改用有货的国内站：almalinux/anolis→阿里云、rocky→USTC），映射表与
> 逐站 curl 依据见实现计划 `docs/superpowers/plans/2026-08-28-platform-abstraction.md`。

### 2.1 目录结构

```
essentials/sys-setup/
├── install.sh          # 调度 + 平台无关子命令 + status/uninstall/usage
└── platform/
    ├── debian.sh       # ubuntu/debian/mint/deepin/uos/openkylin(桌面形态)
    ├── rhel.sh         # centos/almalinux/rocky/fedora/openeuler/anolis/kylin(服务器形态)
    ├── suse.sh         # opensuse-leap/tumbleweed/sles
    ├── arch.sh         # arch/manjaro/garuda（按 uname -m 分路径）
    └── alpine.sh       # alpine
```

族归属由 lib 的 `detect_distro` 给出（`DISTRO_FAMILY`），**删除 `do_mirror` 里
手写的 os_id→distro case**。麒麟桌面/服务器双形态由 `detect_distro` 的包管理
器实测逻辑自动归类，platform 文件内部再按 `DISTRO_ID` 细分——这正是 A+B 组合
的价值。

### 2.2 platform 文件的统一接口

每个 platform 文件导出三个函数，install.sh 只认接口不认发行版：

| 函数 | 职责 |
|------|------|
| `plat_mirror_preview` | echo 换源动作清单（逐行，供 #39 预览框架拼装） |
| `plat_mirror_apply` | 执行换源（备份→写模板/sed→刷新索引）；该发行版无法自动换源时输出指引并 return 0 |
| `plat_autoupdate` | 配置自动安全更新（unattended-upgrades / dnf-automatic / yum-cron / …） |

platform 文件内**不出现动词**：装包用 `pkg_install`、管服务用 `uxs_svc`、读
os-release 用 `uxs_os_release`，只保留"名词"（模板内容、路径、URL、sed 规则）。

### 2.3 install.sh 的重写边界

保留在 install.sh（平台无关）：

- `preflight`（detect_os + Linux-only + require_sudo）、`main` 调度、`usage`
- `status_sys_setup`、`uninstall_sys_setup`（原样不动）
- `do_timezone` / `do_ntp` / `do_optimize` / `do_ssh`：均为 systemd 通用逻辑，
  无 per-发行版分支（do_ntp/set_ntp_servers 的装 chrony 段改用
  `pkg_install` + `uxs_svc enable-now`，消掉最后一处 case PKG_MANAGER）
- `do_mirror` 重写为骨架：`detect_distro` → family 分发 → 调 `plat_mirror_preview`
  拼预览 → `yes_no` 确认 → 调 `plat_mirror_apply`
- `do_autoupdate` 缩为：family 分发 → 调 `plat_autoupdate`
- `do_ntp`/`set_ntp_servers` 的兜底装 chrony 段改用 `pkg_install` +
  `uxs_svc enable-now`；chrony 单元名（debian 系 `chrony`、rhel 系 `chronyd`）
  是名词，按 `DISTRO_FAMILY` 两行 case 留在 install.sh

调度与加载（两步判断：「发行版族未知」是 warn 跳过，「族已知但 platform 文件
缺失」是框架错误，二者不可混淆）：

```bash
if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
    warn "暂不支持该发行版（族未知），跳过换源"   # 语义与现状一致
    return 0
fi
local plat="$SCRIPT_DIR/platform/${DISTRO_FAMILY}.sh"
if [[ ! -f "$plat" ]]; then
    error "platform 文件缺失（框架错误）：$plat"
    return 1
fi
# shellcheck source=platform/debian.sh
source "$plat"
```

### 2.4 #39 换源矩阵的落地位置

#39 spec 的全部内容在 platform 文件内实现，两 spec 一并交付：

- 预览确认框架 → install.sh `do_mirror` 骨架（含非交互 stdin 跳过、默认 N）
- Alma/Rocky/Fedora 整写模板、openEuler/Anolis sed 替换、麒麟/openKylin 核对
  后定整写或指引 → `platform/rhel.sh`、`platform/debian.sh`
- Arch/Manjaro 按 `uname -m` 分 `archlinux`/`archlinuxarm` 等路径 →
  `platform/arch.sh`
- 模板以 TUNA help 页为准、`$releasever/$basearch` 用发行版原生变量等实现纪律
  → 原样继承 #39 第四节

## 三、数据流（以 mirror 为例）

```
install.sh main mirror
  → preflight（Linux-only、require_sudo）
  → detect_distro（lib，设置 DISTRO_ID/DISTRO_FAMILY）
  → source platform/${DISTRO_FAMILY}.sh
  → 收集检测信息（uxs_os_release ID / VERSION_CODENAME、uname -m、PKG_MANAGER）
  → plat_mirror_preview → 渲染「换源预览」框
  → 交互确认（非 TTY：warn 跳过 return 0）
  → plat_mirror_apply（内部 pkg_update 刷索引或按 #39 各分支自刷）
```

## 四、错误处理

| 场景 | 行为 |
|------|------|
| `platform/<family>.sh` 文件缺失（框架错误） | `error` + return 1（与"发行版不支持跳过"区分开） |
| `DISTRO_FAMILY=unknown` | mirror/autoupdate `warn` 跳过、return 0（保持现状语义，status 不受影响） |
| `plat_mirror_apply` 内部失败（如 codename 缺失） | return 1，`do_mirror` 不吞（与现状一致，`all` 模式下设 `set -e` 中止链） |
| 换源非交互环境 | warn + return 0（#39 严格档：不执行不阻断，无逃生开关） |

## 五、测试

1. **新增 `tests/unit_platform.sh`**（沿用 unit_disk_smart.sh 的组织方式）：
   - `uxs_os_release`：临时 fixture 文件断言 ID/VERSION_CODENAME/带引号值/缺文件空返回
   - `uxs_svc`：`UNIX_SCRIPT_DRY_RUN=1` 下断言打印 `sudo systemctl …` 且不执行；
     非 Linux 分支返回 1
2. **ci_run.sh 静态断言**（继承 #39 测试节全部条目，另加）：
   - `platform/*.sh` 五文件存在且 `do_mirror` 骨架含 `platform/` 引用
   - `do_mirror` 不再含 `\. /etc/os-release` 手写识别（防退化）
3. **routing 矩阵**：`sys-setup status|help` 在全部发行版容器 exit 0 + `set -u`
   契约不回退（现有腿天然覆盖 debian/ubuntu/almalinux/rocky/centos-stream/
   fedora/opensuse/arch/alpine/麒麟/uos/openEuler/deepin/openKylin）
4. **dry-run 回归**：`--dry-run` 下 mirror/optimize/ssh 全部只打印不执行
5. **实机验收**：murphy-server（Ubuntu 26.04）跑 `sys-setup mirror` 人工核对
   预览框与 deb822 重写结果

## 六、迁移计划

| 阶段 | 内容 | 交付 |
|------|------|------|
| Phase 1 | lib 新增 `uxs_os_release`、`uxs_svc` + `tests/unit_platform.sh` | PR 1（低风险，可独立合入） |
| Phase 2 | sys-setup 拆 platform/ 五文件 + `do_mirror` 骨架重写 + #39 矩阵全部落地 | PR 2（样板，CI 全矩阵 + 实机验收） |
| Phase 3 | 滚动迁移（不定期，改哪个模块顺手迁）：17 个手写 `systemctl enable --now` 的模块逐个换 `uxs_svc`（caddy/nginx/redis/postgres/gitea/grafana/prometheus/node_exporter/ddns-go/fail2ban/cockpit/docker/openlist/tailscale/clash/certbot/sys-setup 自身）；4 个手写 `apt-get/dnf install` 的模块换 `pkg_install` | 随各模块后续改动搭车，不单开 PR |

Phase 3 完成后 `grep -rl "systemctl enable --now" services essentials dev-tools`
应为空——作为收敛完成的验收口径（CI 可加可选断言）。

## 七、明确不做

- 不拆仓库、不改对外接口（菜单/manifest/`--status-json`/profile）
- 不改存量 `pkg_install`/`service_start` 等签名，不做统一改名
- 不一次性重构 52 个模块（Phase 3 滚动）
- 不做 `uxs_fw`（仅 2 处使用；ufw status 存量 bug 独立修）
- 不引入 bash 4+ 特性（关联数组等）
- 换源不做镜像站选择（固定 TUNA）、不做 RHEL 自动化、不加非交互逃生开关
  （继承 #39 第五节）
