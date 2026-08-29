# 换源矩阵升级 + 执行前预览确认 — 设计

日期：2026-08-28
状态：待实现
前置依赖：`fix/apt-deb822-mirror` 分支（deb822 重写 + 残留源停用）需先合入，本设计在其上叠加。

## 背景与目标

`sys-setup mirror`（`essentials/sys-setup/install.sh` 的 `do_mirror`）当前仅对
Ubuntu/Debian/Mint、CentOS Stream 9、openSUSE、Arch 系、Alpine 做自动换源；
Alma/Rocky/RHEL/Fedora 只打印帮助链接（却被提示文案列为"支持"）；Arch 在 aarch64
机器上会写入错误的 `archlinux` 路径（ARM 应为 `archlinuxarm`）；换源检测完直接
执行，没有任何预览确认。

本次升级目标（用户已确认范围）：

1. 执行前展示「检测信息 + 动作预览」，用户确认后才改写；非交互环境跳过不阻断
2. 补 AlmaLinux / Rocky / Fedora 自动换源（RHEL 无公开镜像，维持指引）
3. 修 Arch 系按 `uname -m` 区分源路径，顺带修 Manjaro 误写 `archlinux` 路径的问题
4. 纳入国产系：openEuler、Anolis OS、openKylin/银河麒麟、deepin

## 一、预览确认框架（所有分支统一前置）

在 `do_mirror` 识别发行版之后、写任何文件之前：

```
── 换源预览 ──────────────────────────────
检测到:  Ubuntu 25.10 (resolute) · x86_64 · apt
执行动作:
  1. 备份 /etc/apt/sources.list.d/ubuntu.sources → *.bak.<ts>
  2. 重写为清华 TUNA（https://mirrors.tuna.tsinghua.edu.cn/ubuntu/）
  3. 停用其余发行版归档源（检测到 2 个）
  4. sudo apt-get update
──────────────────────────────────────────
确认执行换源？[y/N]
```

- 检测信息：`$ID`、`$VERSION_ID`/`$VERSION_CODENAME`、`uname -m`、包管理器
- 动作清单按 distro 分支生成（见下）；第 3 类"停用 N 个残留源"在 apt 分支
  先 dry 扫描计数，让用户知道波及面
- `yes_no` 默认 N；输入非 y 一律取消（返回 0，不做任何改动）
- **非交互（stdin 非 TTY）**：不执行、不中断——`warn "换源需交互确认，已跳过"`
  并返回 0（保证 `sys-setup all` 非交互场景其余步骤不受阻）。无逃生开关
  （与磁盘模块"严格档"一致：破坏性操作必须有人在场）

## 二、各分支动作清单（升级后）

### apt 系（Ubuntu/Debian/Mint/deepin）

- Ubuntu/Debian/Mint：沿用 deb822 优先逻辑（前置分支已实现），无结构变化
- **deepin（新增）**：`ID=deepin|uos` → apt 分支。components 与 Ubuntu 不同，
  模板用 `main community`；codename 取 `VERSION_CODENAME`（UOS 20=eagle、
  deepin 23=crimson 等）。**实现前核对 TUNA `/help/deepin` 页面**；若 TUNA
  路径/组件与模板不符，降级为打印指引（同 Alma 现状），不硬写

### rpm 系

> **2026-08-28 实测修订**：TUNA 已无 almalinux/rocky/anolis 仓库（逐站 curl 验证），
> 原"固定 TUNA"约束按发行版调整为"按发行版固定到有货的国内站"（仍无用户选择 UI）：
> almalinux→阿里云、rocky→USTC、anolis→阿里云(sed)、fedora/openeuler→TUNA。

- **CentOS Stream 9**：现状保留（整写 centos.repo）
- **AlmaLinux（新增）**：整写 `/etc/yum.repos.d/almalinux.repo`，
  BaseOS/AppStream/CRB/extras 四节，`https://mirrors.aliyun.com/almalinux/$releasever/.../$basearch/os/`
  （阿里云四节路径 200 实测；Alma 的 `$releasever` 无小版本，可原生交给 dnf 展开），
  gpgkey 沿用 `file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever`
- **Rocky（新增）**：整写 `rocky.repo`，指向 USTC
  `https://mirrors.ustc.edu.cn/rocky/<主版本>/.../$basearch/os/`。
  **注意 USTC 目录按主版本组织**（`/rocky/9/` 200、`/rocky/9.6/` 404，实测），
  而 Rocky 的 `$releasever` 展开为 `9.6`，故 URL/gpgkey 用主版本号
  （`rpm -E '%{rhel}'` 取值，回退 `VERSION_ID` 首段）
- **Fedora（新增）**：整写 `fedora.repo` + `fedora-updates.repo`
  （`/fedora/releases/$releasever/Everything/$basearch/os/` 与
  `/fedora/updates/$releasever/Everything/$basearch/`——TUNA 帮助页核对，
  updates 路径无 `/os` 后缀）
- **openEuler（新增）**：sed `mirror.openeuler.org`（及 `repo.openeuler.org`）→
  `mirrors.tuna.tsinghua.edu.cn/openeuler`（TUNA 仓库 200 实测），作用于
  `/etc/yum.repos.d/*.repo`
- **Anolis OS（新增）**：sed `mirrors.openanolis.cn` / `mirrors.anolis.org` →
  `mirrors.aliyun.com/anolis`（阿里云 `anolis/8/BaseOS` 200 实测）
- **RHEL / 麒麟(服务器)**：无公开镜像（订阅授权；TUNA kylin 路径 404 实测），
  维持打印指引，`*)` 兜底提示文案与实际行为一致
- 整写前备份整个 `/etc/yum.repos.d`（现状已有）；写后 `dnf clean all && makecache`

### Arch 系（修路径 bug）

mirrorlist 模板按 `ID` + `uname -m` 选择：

| ID | x86_64 | aarch64 |
|---|---|---|
| arch | `archlinux/$repo/os/$arch` | `archlinuxarm/$repo/os/$arch` |
| manjaro | `manjaro/stable/$repo/$arch` | `manjaro-arm/stable/$repo/$arch` |
| garuda | TUNA `/help/garuda` 核对后定；核对不清降级指引 | — |

### 国产系（新增）

优先级原则：**能 sed 替换主机名的 sed（保留原 repo 结构），不能的整写官方
模板，两者都不稳的打印指引**。

- **openEuler**：sed `mirror.openeuler.org`（及 `repo.openeuler.org`）→
  `mirrors.tuna.tsinghua.edu.cn/openeuler`，作用于 `/etc/yum.repos.d/*.repo`
- **Anolis OS**：sed `mirrors.openanolis.cn` / `mirrors.anolis.org` → TUNA
  `/anolis`
- **银河麒麟/openKylin**：TUNA 路径结构待核对（`/kylin`、`/openkylin`），
  核对通过则整写模板，否则指引
- 识别入口：`os-release` 的 `ID`/`ID_LIKE`（openEuler、anolis、kylin、
  openkylin、deepin/uos）；`ID_LIKE` 仅作辅助，不盲目按 ID_LIKE=fedora
  走 rpm 模板

## 三、提示文案修正

`*)` 兜底 warn 与各分支 info 文案改为与实际行为一致：自动换源清单 = 现有
五系 + Alma/Rocky/Fedora + openEuler/Anolis（麒麟/deepin 视核对结果）；
仅指引清单 = CentOS 7/8（EOL vault）、RHEL、核对未通过的项。

## 四、测试

- routing 阶段（容器矩阵天然覆盖 almalinux-9/rocky-9/centos-stream9/fedora/
  opensuse/arch/alpine/debian-12/ubuntu）：`status`/`help` exit 0 + `set -u`
  契约不回退
- 新增静态断言（ci_run.sh）：`do_mirror` 含预览确认调用（`换源预览`）；
  Alma/Rocky/Fedora/openEuler/Anolis 各自的关键字存在；Arch 分支含
  `archlinuxarm` 与 `uname -m`
- 预览确认的分支逻辑（确认/取消/非交互跳过）无法在 CI 真跑，靠沙盒脚手架
  验证 + 实机人工验收

## 五、明确不做

- 不做镜像站选择（固定清华 TUNA，与现状一致）
- 不做 RHEL 自动化（无公开镜像）
- 不加任何非交互逃生开关（严格档）
- 不动第三方 repo（docker、grafana 等自有源）
