# 平台抽象收敛 实现计划（lib helper + sys-setup platform 拆分）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 `docs/superpowers/specs/2026-08-28-platform-abstraction-design.md`：lib 新增 `uxs_os_release`/`uxs_svc` 两个动词 helper；sys-setup 拆分 `platform/` 五文件并同时实现换源矩阵升级（mirror-matrix spec 全部内容）。

**Architecture:** PR 1 只动 lib + tests（低风险先行）；PR 2 重构 `essentials/sys-setup`，`install.sh` 只留平台无关调度，per-族实现进 `platform/{debian,rhel,suse,arch,alpine}.sh`，每个文件导出 `plat_mirror_preview` / `plat_mirror_apply` / `plat_autoupdate` 三接口。

**Tech Stack:** bash 3.2 兼容 shell；测试用项目自带的 `t_eq`/`assert` 纯 bash 模式；CI 用 `tests/ci_run.sh`。

## Global Constraints

- bash 3.2 兼容：不用关联数组（`declare -A`）、不用 `${v,,}`
- 存量 lib 函数（`pkg_install`/`service_start` 等）一律不改名不改签名
- 新增 lib 函数统一 `uxs_` 前缀
- 对外接口零变化：模块子命令、`.manifest`、`--status-json`、菜单、profile
- 换源镜像站**按发行版固定**（2026-08-28 逐站 curl 实测选定，见下表），不提供用户选择 UI
- 换源必须预览确认；非交互 stdin 跳过不阻断（严格档，无逃生开关）
- 每个 Task 结束本地 commit；PR 边界 = Task 3 结束（PR 1）/ Task 9 结束（PR 2）

## 镜像站映射表（2026-08-28 实测，计划阶段 curl 验证）

| 发行版 (DISTRO_ID) | FAMILY | 站点 | 方式 | 实测依据 |
|---|---|---|---|---|
| ubuntu/linuxmint/debian | debian | 清华 TUNA | deb822 优先重写（已合入现状） | 现状 |
| deepin/uos | debian | TUNA `/deepin/` | 一行式 `main community` | `deepin/dists/` 200 |
| kylin(桌面)/openkylin | debian | — | 指引 | TUNA 无货 404 |
| centos (Stream 9) | rhel | TUNA | 整写 centos.repo（现状） | `centos-stream/9-stream/BaseOS` 200 |
| almalinux | rhel | **阿里云** | 整写 almalinux.repo，`$releasever` 原生（Alma 无小版本） | `9/{BaseOS,AppStream,CRB,extras}` 全 200 |
| rocky | rhel | **USTC** | 整写 rocky.repo，**主版本号**（USTC 按主版本组织，`$releasever`=9.6 会 404） | `9/{BaseOS,AppStream}` 200；`9.6` 404 |
| fedora | rhel | TUNA | 整写 fedora.repo + fedora-updates.repo | `releases/44`+`updates/44` 200；updates 路径无 `/os` 后缀 |
| openeuler | rhel | TUNA | sed 替换主机名 | 根 200 |
| anolis | rhel | **阿里云** | sed 替换主机名 | `anolis/8/BaseOS` 200 |
| rhel / kylin(服务器) | rhel | — | 指引 | 无公开镜像 |
| arch/manjaro | arch | TUNA | mirrorlist 整写，`uname -m` 分 x86_64/aarch64 路径 | `archlinuxarm/`、`manjaro/stable/` 200 |
| garuda | arch | — | 指引 | #39 纪律 |
| opensuse* | suse | TUNA | sed（现状） | 现状 |
| alpine | alpine | TUNA | repositories 整写（现状） | 现状 |

> 偏差说明：mirror-matrix spec 原定"固定 TUNA"，实测 TUNA 已无 almalinux/rocky/anolis，
> 按 spec 自带纪律（核对不过即降级）本应全降指引；本计划改为"按发行版固定到有货的
> 国内站"，保住"自动换源"目标。执行 PR 2 时同步修订两份 spec 的对应句子。

---

# PR 1：lib 动词 helper + 单测（分支 `feat/lib-platform-helpers`）

### Task 1: `uxs_os_release`（TDD）

**Files:**
- Create: `tests/unit_platform.sh`
- Modify: `lib/common.sh`（`detect_distro()` 函数结束的 `}` 之后插入，约 :183）

**Interfaces:**
- Produces: `uxs_os_release <KEY> [file]` — 输出字段值（去引号）；文件缺省依次 `/etc/os-release`、`/usr/lib/os-release`；不可读返回空；恒返回 0。内部复用 `_osr_field`（同文件私有函数，不动 `detect_distro`）

- [ ] **Step 1: 写失败测试** — 创建 `tests/unit_platform.sh`：

```bash
#!/usr/bin/env bash
#
# tests/unit_platform.sh — lib 平台动词 helper（uxs_os_release / uxs_svc）单测
# 独立运行：bash tests/unit_platform.sh（退出码 0=全过）
# 也被 tests/ci_run.sh 调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
set +e +o pipefail

# ---------- uxs_os_release ----------
FIX=$(mktemp)
cat > "$FIX" <<'EOF'
ID="ubuntu"
VERSION_ID="24.04"
PRETTY_NAME='Ubuntu 24.04 LTS'
VERSION_CODENAME=noble
EOF
t_eq "os_release: 双引号值" "ubuntu" "$(uxs_os_release ID "$FIX")"
t_eq "os_release: 版本" "24.04" "$(uxs_os_release VERSION_ID "$FIX")"
t_eq "os_release: 单引号含空格" "Ubuntu 24.04 LTS" "$(uxs_os_release PRETTY_NAME "$FIX")"
t_eq "os_release: 无引号值" "noble" "$(uxs_os_release VERSION_CODENAME "$FIX")"
t_eq "os_release: 缺失键为空" "" "$(uxs_os_release ID_LIKE "$FIX")"
t_eq "os_release: 文件不可读为空" "" "$(uxs_os_release ID /nonexistent/os-release)"
rm -f "$FIX"

echo "unit_platform(os_release): 通过 $PASS / 失败 $FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: 跑测试确认失败** — `bash tests/unit_platform.sh`；预期 `FAIL: os_release: 双引号值 ...`（函数不存在）
- [ ] **Step 3: 最小实现** — `lib/common.sh` 的 `detect_distro()` 之后插入：

```bash
# 读 os-release 风格文件的字段值：uxs_os_release <KEY> [file]
# file 缺省依次尝试 /etc/os-release、/usr/lib/os-release；均不可读返回空。
# 供模块替代手写 `$(. /etc/os-release && echo "$ID")`；恒返回 0。
uxs_os_release() {
    local key="$1" rel_file="${2:-}"
    if [[ -z "$rel_file" ]]; then
        for rel_file in /etc/os-release /usr/lib/os-release; do
            [[ -r "$rel_file" ]] && break
            rel_file=""
        done
    fi
    _osr_field "$rel_file" "$key"
}
```

- [ ] **Step 4: 跑测试确认通过** — `bash tests/unit_platform.sh`；预期 `通过 6 / 失败 0`，退出 0
- [ ] **Step 5: Commit** — `git add lib/common.sh tests/unit_platform.sh && git commit -m "feat(lib): uxs_os_release 读 os-release 字段，替代模块手写识别"`

### Task 2: `uxs_svc`（TDD）

**Files:**
- Modify: `tests/unit_platform.sh`（追加 uxs_svc 段）
- Modify: `lib/common.sh`（「服务管理封装」注释块 `service_start()` 之后插入）

**Interfaces:**
- Consumes: `dry_run_sudo`（已存在）、`warn`/`error`（已存在）、全局 `OS_TYPE`（调用方需已跑 `detect_os`；未设置按非 Linux 拒绝）
- Produces: `uxs_svc <action> <unit>...` — action ∈ `start|stop|restart|reload|enable|disable|enable-now|is-active`；非 Linux `warn` 并返回 1；`is-active` 直跑（只读无 sudo）；其余走 `dry_run_sudo`，天然兼容 `--dry-run`

- [ ] **Step 1: 追加失败测试** — 在 `tests/unit_platform.sh` 的 `echo "unit_platform(os_release)..."` 行之前插入：

```bash
# ---------- uxs_svc ----------
UNIX_SCRIPT_DRY_RUN=1
OS_TYPE=linux
out=$(uxs_svc enable-now nginx)
t_eq "svc: dry-run enable-now 打印且不执行" \
    "[dry-run] systemctl enable --now: sudo systemctl enable --now nginx" "$out"
out=$(uxs_svc restart docker)
t_eq "svc: dry-run restart" "[dry-run] systemctl restart: sudo systemctl restart docker" "$out"
rc=0; uxs_svc bogus-action nginx >/dev/null 2>&1 || rc=$?
t_eq "svc: 未知 action 返回 1" "1" "$rc"
OS_TYPE=darwin
rc=0; uxs_svc restart nginx >/dev/null 2>&1 || rc=$?
t_eq "svc: darwin 拒绝返回 1" "1" "$rc"
```

- [ ] **Step 2: 跑测试确认失败** — `bash tests/unit_platform.sh`；预期 `uxs_svc: command not found` 类失败
- [ ] **Step 3: 最小实现** — `lib/common.sh` 的 `service_start()` 之后插入：

```bash
# uxs_svc <action> <unit>... — systemd 服务动作封装（Linux-only）。
# action: start|stop|restart|reload|enable|disable|enable-now|is-active。
# 除只读的 is-active 外均走 dry_run_sudo（--dry-run 下仅打印）；非 Linux 返回 1。
# 与 service_start/stop/is_active 并存：那组是 systemd+launchd 双平台签名，
# Linux-only 模块用本函数，签名更简单。
uxs_svc() {
    local action="$1"; shift
    if [[ $# -lt 1 ]]; then
        error "uxs_svc: 缺少 unit 参数"
        return 1
    fi
    if [[ "${OS_TYPE:-}" != "linux" ]]; then
        warn "uxs_svc 仅支持 systemd（Linux），当前：${OS_TYPE:-unknown}"
        return 1
    fi
    case "$action" in
        is-active)  systemctl is-active --quiet "$@" ;;
        start|stop|restart|reload|enable|disable)
            dry_run_sudo "systemctl $action" systemctl "$action" "$@" ;;
        enable-now) dry_run_sudo "systemctl enable --now" systemctl enable --now "$@" ;;
        *)          error "uxs_svc: 未知 action：$action"; return 1 ;;
    esac
}
```

- [ ] **Step 4: 跑测试确认通过** — `bash tests/unit_platform.sh`；预期 `通过 10 / 失败 0`
- [ ] **Step 5: Commit** — `git add lib/common.sh tests/unit_platform.sh && git commit -m "feat(lib): uxs_svc systemd 动作封装，dry-run 原生兼容"`

### Task 3: CI 挂载单测 + 文档 + PR 1 收尾

**Files:**
- Modify: `tests/ci_run.sh:334` 附近（disk 单测 assert 之后）
- Modify: `AGENTS.md`（status 契约 helper 表附近新增平台 helper 小节）

- [ ] **Step 1:** `tests/ci_run.sh` 在 `assert "disk: smart 判定单测全过" ...` 行后加：

```bash
    assert "platform: lib helper 单测全过" bash "$REPO_DIR/tests/unit_platform.sh"
```

- [ ] **Step 2:** `AGENTS.md` 的「机器可读 status」小节后新增：

```markdown
### 平台动词 helper（lib 层收敛）

模块内跨发行版重复的平台操作优先用 lib helper，勿手写 `sudo apt-get`/`systemctl`：

| Helper | 说明 |
|--------|------|
| `uxs_os_release <KEY> [file]` | 读 os-release 字段值（ID/VERSION_ID/VERSION_CODENAME…），替代手写 `. /etc/os-release` |
| `uxs_svc <action> <unit>...` | systemd 服务动作（start/stop/restart/reload/enable/enable-now/is-active），原生兼容 `--dry-run`；双平台（macOS launchd）场景仍用 `service_start` 等 |
| `pkg_install` / `pkg_remove` / `pkg_installed` | 跨包管理器安装/卸载/查询（存量，直接用） |

归属原则：跨模块复用的「动词」进 lib；单模块专用的平台差异放模块内 `platform/` 文件（样板见 `essentials/sys-setup`）。
```

- [ ] **Step 3:** 全量回归：`bash tests/unit_platform.sh && bash tests/unit_disk_smart.sh && NO_COLOR=1 bash tests/ci_run.sh --phase static 2>&1 | tail -5`（static 阶段若整体不适用于 macOS 则至少跑 unit 两个文件 + `bash -n tests/ci_run.sh`）
- [ ] **Step 4: Commit + 建分支名** — `git checkout -b feat/lib-platform-helpers`（若尚未建分支）；`git add tests/ci_run.sh AGENTS.md && git commit -m "test(ci): 挂载 unit_platform；docs: 平台动词 helper 使用说明"`

---

# PR 2：sys-setup platform 拆分 + 换源矩阵（分支 `feat/syssetup-platform-split`，基于 PR 1）

### Task 4: `platform/debian.sh`（ubuntu/mint/debian 搬迁 + deepin/uos 新增 + kylin 桌面指引）

**Files:**
- Create: `essentials/sys-setup/platform/debian.sh`

**Interfaces:**
- Consumes: `uxs_os_release`（Task 1）、`error/warn/success/info`、`DISTRO_ID`（由调用方 `detect_distro` 设置）
- Produces: `plat_mirror_preview` / `plat_mirror_apply` / `plat_autoupdate`；模块私有 `_deb_primary_target`、`_apt_disable_distro_sources`（自 install.sh 迁入，原样）

- [ ] **Step 1: 写文件**：

```bash
#!/usr/bin/env bash
#
# essentials/sys-setup/platform/debian.sh
#
# Debian 族（DISTRO_FAMILY=debian）平台实现。
# 覆盖 DISTRO_ID：ubuntu / linuxmint / debian / deepin / uos；
# kylin(桌面)/openkylin 无公开镜像，降级指引。
# 只含「名词」：模板、路径、清单；动词（pkg_install 等）来自 lib。

MIRROR_BASE="https://mirrors.tuna.tsinghua.edu.cn"

# 停用除主文件外仍指向发行版归档的 apt 源文件（deb822 与一行式都查），
# 避免新旧源并存。停用方式 = 重命名为 *.bak.<ts>（apt 只读 .list/.sources 后缀）。
_apt_disable_distro_sources() {
    local primary="$1" ts="$2" f
    local pattern='(archive|security|azure|cn)\.ubuntu\.com|(deb|security)\.debian\.org|mirrors\.[A-Za-z.]+/(ubuntu|debian)'
    local -a candidates=(/etc/apt/sources.list)
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$f" ]] && candidates+=("$f")
    done
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$primary" ]] && continue
        if sudo grep -Eq "$pattern" "$f" 2>/dev/null; then
            sudo mv "$f" "${f}.bak.$ts" 2>/dev/null || { warn "停用失败（权限？）：$f"; continue; }
            warn "已停用重复/残留源文件：$f（恢复：sudo mv ${f}.bak.$ts $f）"
        fi
    done
}

# apt 主源文件：deb822 优先（Ubuntu 24.04+/Debian 13 起发行版源在
# sources.list.d/*.sources），无则回退传统 sources.list。
_deb_primary_target() {
    case "$DISTRO_ID" in
        ubuntu|linuxmint)
            if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
                echo /etc/apt/sources.list.d/ubuntu.sources; return
            fi ;;
        debian)
            if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
                echo /etc/apt/sources.list.d/debian.sources; return
            fi ;;
    esac
    echo /etc/apt/sources.list
}

plat_mirror_preview() {
    local codename primary
    case "$DISTRO_ID" in
        ubuntu|linuxmint|debian)
            codename=$(uxs_os_release VERSION_CODENAME)
            primary=$(_deb_primary_target)
            echo "  1. 备份并重写 ${primary} 为清华 TUNA（${DISTRO_ID}/${codename:-?}）"
            echo "  2. 停用其余发行版归档 apt 源（重命名 *.bak.<ts>，可随时恢复）"
            echo "  3. sudo apt-get update" ;;
        deepin|uos)
            codename=$(uxs_os_release VERSION_CODENAME)
            echo "  1. 备份并重写 /etc/apt/sources.list 为清华 TUNA（${DISTRO_ID}/${codename:-?}，main community）"
            echo "  2. 停用其余发行版归档 apt 源"
            echo "  3. sudo apt-get update" ;;
        *)
            echo "  1. ${DISTRO_ID} 暂无公开镜像仓库，仅打印指引（不改动系统）" ;;
    esac
}

plat_mirror_apply() {
    local codename ts primary
    codename=$(uxs_os_release VERSION_CODENAME)
    ts=$(date +%s)
    case "$DISTRO_ID" in
        ubuntu|linuxmint|debian)
            if [[ -z "$codename" ]]; then
                error "无法识别发行版代号（VERSION_CODENAME）"; return 1
            fi
            primary=$(_deb_primary_target)
            sudo cp -a "$primary" "${primary}.bak.$ts" 2>/dev/null || true
            if [[ "$primary" == *.sources ]]; then
                if [[ "$DISTRO_ID" == "debian" ]]; then
                    sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 ${primary}.bak.$ts）
Types: deb
URIs: ${MIRROR_BASE}/debian/
Suites: ${codename} ${codename}-updates ${codename}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${MIRROR_BASE}/debian-security/
Suites: ${codename}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
                else
                    sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 ${primary}.bak.$ts）
Types: deb
URIs: ${MIRROR_BASE}/ubuntu/
Suites: ${codename} ${codename}-updates ${codename}-backports ${codename}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
                fi
            elif [[ "$DISTRO_ID" == "debian" ]]; then
                sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 .bak.*）
deb ${MIRROR_BASE}/debian/ ${codename} main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian/ ${codename}-backports main contrib non-free non-free-firmware
deb ${MIRROR_BASE}/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
            else
                sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 .bak.*）
deb ${MIRROR_BASE}/ubuntu/ ${codename} main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-updates main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-backports main restricted universe multiverse
deb ${MIRROR_BASE}/ubuntu/ ${codename}-security main restricted universe multiverse
EOF
            fi
            _apt_disable_distro_sources "$primary" "$ts"
            success "apt 源已更换为清华镜像（${DISTRO_ID}/${codename}），原文件已备份"
            sudo apt-get update ;;
        deepin|uos)
            if [[ -z "$codename" ]]; then
                error "无法识别发行版代号（VERSION_CODENAME）"; return 1
            fi
            primary=/etc/apt/sources.list
            sudo cp -a "$primary" "${primary}.bak.$ts" 2>/dev/null || true
            sudo tee "$primary" >/dev/null <<EOF
# 由 unix_script sys-setup 生成（原文件已备份为 ${primary}.bak.$ts）
deb ${MIRROR_BASE}/deepin/ ${codename} main community
EOF
            _apt_disable_distro_sources "$primary" "$ts"
            success "apt 源已更换为清华镜像（${DISTRO_ID}/${codename}）"
            sudo apt-get update ;;
        *)
            warn "银河麒麟/openKylin 暂无公开镜像仓库，保持系统源不变"
            warn "如需换源请参考系统自带「软件源」工具或服务器版官方文档" ;;
    esac
}

plat_autoupdate() {
    case "$DISTRO_ID" in
        deepin|uos)
            warn "${DISTRO_ID} 的自动安全更新由系统更新器管理，跳过" ;;
        *)
            pkg_install unattended-upgrades apt-listchanges
            sudo dpkg-reconfigure -fnoninteractive -plow unattended-upgrades 2>/dev/null || true
            success "已启用 Debian/Ubuntu/Mint 自动安全更新（unattended-upgrades）" ;;
    esac
}
```

- [ ] **Step 2:** `bash -n essentials/sys-setup/platform/debian.sh` 语法过
- [ ] **Step 3: Commit** — `git add essentials/sys-setup/platform/debian.sh && git commit -m "feat(sys-setup): debian 族 platform——apt 换源矩阵 + deepin/uos 新增"`

### Task 5: `platform/rhel.sh`（centos 现状 + alma→阿里云 + rocky→USTC + fedora→TUNA + openeuler/anolis sed + rhel/kylin 指引）

**Files:**
- Create: `essentials/sys-setup/platform/rhel.sh`

**Interfaces:**
- Consumes: `uxs_os_release`、`DISTRO_ID`、`ARCH_TYPE_LOWER`（如需）、`pkg_install`
- Produces: `plat_mirror_preview` / `plat_mirror_apply` / `plat_autoupdate`；私有 `_rhel_major`

- [ ] **Step 1: 写文件**：

```bash
#!/usr/bin/env bash
#
# essentials/sys-setup/platform/rhel.sh
#
# RHEL 族（DISTRO_FAMILY=rhel）平台实现。
# 覆盖 DISTRO_ID：centos / almalinux / rocky / fedora / openeuler / anolis；
# rhel / kylin(服务器) 无公开镜像，降级指引。
# 镜像站按发行版固定（2026-08-28 逐站实测）：
#   almalinux→阿里云  rocky→USTC(主版本目录)  fedora→TUNA  openeuler→TUNA(sed)  anolis→阿里云(sed)

_rhel_backup_repos() {
    local ts="$1"
    sudo cp -a /etc/yum.repos.d "/etc/yum.repos.d.bak.$ts" 2>/dev/null || true
}

# Rocky 的 $releasever 展开为 9.6 这类小版本，而 USTC 目录按主版本组织（9 ✅ 9.6 ❌），
# 故 URL 用主版本号；gpgkey 文件名同样是主版本。
_rhel_major() {
    local m vid
    m=$(rpm -E '%{rhel}' 2>/dev/null || true)
    if [[ "$m" =~ ^[0-9]+$ ]]; then echo "$m"; return; fi
    vid=$(uxs_os_release VERSION_ID)
    echo "${vid%%.*}"
}

plat_mirror_preview() {
    case "$DISTRO_ID" in
        centos)
            echo "  1. 备份 /etc/yum.repos.d"
            echo "  2. 重写 centos.repo 为清华 TUNA（CentOS Stream）"
            echo "  3. sudo dnf clean all && makecache" ;;
        almalinux)
            echo "  1. 备份 /etc/yum.repos.d"
            echo "  2. 整写 almalinux.repo 指向阿里云镜像（BaseOS/AppStream/CRB/extras）"
            echo "  3. sudo dnf clean all && makecache" ;;
        rocky)
            echo "  1. 备份 /etc/yum.repos.d"
            echo "  2. 整写 rocky.repo 指向中科大 USTC 镜像（BaseOS/AppStream/CRB/Extras，主版本路径）"
            echo "  3. sudo dnf clean all && makecache" ;;
        fedora)
            echo "  1. 备份 /etc/yum.repos.d"
            echo "  2. 整写 fedora.repo 与 fedora-updates.repo 指向清华 TUNA"
            echo "  3. sudo dnf clean all && makecache" ;;
        openeuler)
            echo "  1. 备份 /etc/yum.repos.d"
            echo "  2. sed 将 mirror.openeuler.org / repo.openeuler.org 替换为清华 TUNA（保留原 repo 结构）"
            echo "  3. sudo dnf clean all && makecache" ;;
        anolis)
            echo "  1. 备份 /etc/yum.repos.d"
            echo "  2. sed 将 openanolis/anolis 官方源替换为阿里云镜像（保留原 repo 结构）"
            echo "  3. sudo dnf clean all && makecache" ;;
        *)
            echo "  1. ${DISTRO_ID} 暂无公开镜像，仅打印指引（不改动系统）" ;;
    esac
}

plat_mirror_apply() {
    local ts
    ts=$(date +%s)
    case "$DISTRO_ID" in
        centos)
            local is_stream
            is_stream=$(uxs_os_release NAME | grep -qi stream && echo yes || echo no)
            _rhel_backup_repos "$ts"
            if [[ "$is_stream" == "yes" ]]; then
                sudo tee /etc/yum.repos.d/centos.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— CentOS Stream 清华 TUNA 镜像
[baseos]
name=CentOS Stream $releasever - BaseOS
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/$releasever-stream/BaseOS/$basearch/os
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
gpgcheck=1
enabled=1

[appstream]
name=CentOS Stream $releasever - AppStream
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/$releasever-stream/AppStream/$basearch/os
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
gpgcheck=1
enabled=1

[crb]
name=CentOS Stream $releasever - CRB
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/$releasever-stream/CRB/$basearch/os
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
gpgcheck=1
enabled=1

[extras-common]
name=CentOS Stream $releasever - Extras packages
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-stream/SIGs/$releasever-stream/extras/$basearch/extras-common
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Extras-SHA512
gpgcheck=1
enabled=1
EOF
                success "CentOS Stream 源已更换为清华镜像（原 /etc/yum.repos.d 已备份）"
            else
                warn "CentOS 7/8（EOL）请参考 vault：https://mirrors.tuna.tsinghua.edu.cn/help/centos-vault/"
                warn "已备份原 /etc/yum.repos.d 到 /etc/yum.repos.d.bak.${ts}，请按指引手动替换 baseurl"
            fi ;;
        almalinux)
            _rhel_backup_repos "$ts"
            sudo tee /etc/yum.repos.d/almalinux.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— AlmaLinux 阿里云镜像
[BaseOS]
name=AlmaLinux $releasever - BaseOS
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever

[AppStream]
name=AlmaLinux $releasever - AppStream
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/AppStream/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever

[CRB]
name=AlmaLinux $releasever - CRB
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/CRB/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever

[extras]
name=AlmaLinux $releasever - Extras
baseurl=https://mirrors.aliyun.com/almalinux/$releasever/extras/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-$releasever
EOF
            success "AlmaLinux 源已更换为阿里云镜像（原 /etc/yum.repos.d 已备份）" ;;
        rocky)
            local major
            major=$(_rhel_major)
            _rhel_backup_repos "$ts"
            sudo tee /etc/yum.repos.d/rocky.repo >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— Rocky Linux 中科大 USTC 镜像（主版本 ${major}）
[BaseOS]
name=Rocky Linux ${major} - BaseOS
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}

[AppStream]
name=Rocky Linux ${major} - AppStream
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}

[CRB]
name=Rocky Linux ${major} - CRB
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/CRB/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}

[Extras]
name=Rocky Linux ${major} - Extras
baseurl=https://mirrors.ustc.edu.cn/rocky/${major}/Extras/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${major}
EOF
            success "Rocky Linux 源已更换为中科大镜像（原 /etc/yum.repos.d 已备份）" ;;
        fedora)
            _rhel_backup_repos "$ts"
            sudo tee /etc/yum.repos.d/fedora.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— Fedora 清华 TUNA 镜像
[fedora]
name=Fedora $releasever - $basearch
baseurl=https://mirrors.tuna.tsinghua.edu.cn/fedora/releases/$releasever/Everything/$basearch/os/
#metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch
EOF
            sudo tee /etc/yum.repos.d/fedora-updates.repo >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— Fedora updates 清华 TUNA 镜像
[updates]
name=Fedora $releasever - $basearch - Updates
baseurl=https://mirrors.tuna.tsinghua.edu.cn/fedora/updates/$releasever/Everything/$basearch/
#metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch
EOF
            success "Fedora 源已更换为清华镜像（原 /etc/yum.repos.d 已备份）" ;;
        openeuler)
            _rhel_backup_repos "$ts"
            sudo sed -i.bak \
                -e 's|mirror.openeuler.org|mirrors.tuna.tsinghua.edu.cn/openeuler|g' \
                -e 's|repo.openeuler.org|mirrors.tuna.tsinghua.edu.cn/openeuler|g' \
                /etc/yum.repos.d/*.repo 2>/dev/null || true
            success "openEuler 源已替换为清华镜像（原 repo 已备份 *.bak）" ;;
        anolis)
            _rhel_backup_repos "$ts"
            sudo sed -i.bak \
                -e 's|mirrors.openanolis.cn|mirrors.aliyun.com/anolis|g' \
                -e 's|mirrors.anolis.org|mirrors.aliyun.com/anolis|g' \
                /etc/yum.repos.d/*.repo 2>/dev/null || true
            success "Anolis OS 源已替换为阿里云镜像（原 repo 已备份 *.bak）" ;;
        *)
            warn "RHEL/麒麟(服务器) 无公开镜像（订阅授权），保持系统源不变"
            warn "RHEL 请使用订阅管理（subscription-manager）；麒麟请使用系统自带更新源" ;;
    esac
    sudo dnf clean all 2>/dev/null || sudo yum clean all 2>/dev/null || true
    sudo dnf makecache 2>/dev/null || sudo yum makecache 2>/dev/null || true
}

plat_autoupdate() {
    if command -v dnf >/dev/null 2>&1; then
        pkg_install dnf-automatic
        sudo sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null || true
        uxs_svc enable-now dnf-automatic.timer
        success "已启用 dnf-automatic"
    else
        pkg_install yum-cron
        uxs_svc enable-now yum-cron
        success "已启用 yum-cron"
    fi
}
```

> 注意：rocky 分支的 heredoc **必须不带引号**（要展开 `${major}`），其中 `$basearch` 写成 `\$basearch` 保留给 dnf 展开；其余分支 quoted heredoc 原样保留 `$releasever`/`$basearch`。

- [ ] **Step 2:** `bash -n essentials/sys-setup/platform/rhel.sh`；并抽查 rocky 模板变量转义：`bash -c 'major=9; cat <<EOF\nbaseurl=https://mirrors.ustc.edu.cn/rocky/${major}/BaseOS/\\$basearch/os/\nEOF'` 输出应为 `.../rocky/9/BaseOS/$basearch/os/`
- [ ] **Step 3: Commit** — `git add essentials/sys-setup/platform/rhel.sh && git commit -m "feat(sys-setup): rhel 族 platform——alma/rocky/fedora/openeuler/anolis 自动换源"`

### Task 6: `platform/suse.sh` + `platform/arch.sh` + `platform/alpine.sh`（搬迁现状 + Arch ARM 修复）

**Files:**
- Create: `essentials/sys-setup/platform/suse.sh`、`platform/arch.sh`、`platform/alpine.sh`

- [ ] **Step 1: suse.sh**（autoupdate 用 openSUSE 现状文案）：

```bash
#!/usr/bin/env bash
#
# essentials/sys-setup/platform/suse.sh — SUSE 族（opensuse-leap/tumbleweed/sles）

plat_mirror_preview() {
    echo "  1. 备份 /etc/zypp/repos.d"
    echo "  2. sed 将 download.opensuse.org 替换为清华 TUNA（保留原 repo 结构）"
    echo "  3. sudo zypper --non-interactive refresh"
}

plat_mirror_apply() {
    local ts; ts=$(date +%s)
    sudo cp -a /etc/zypp/repos.d "/etc/zypp/repos.d.bak.$ts" 2>/dev/null || true
    sudo sed -i.bak \
        -e 's|download.opensuse.org|mirrors.tuna.tsinghua.edu.cn/opensuse|g' \
        -e 's|download.tumbleweed|mirrors.tuna.tsinghua.edu.cn/opensuse/tumbleweed|g' \
        /etc/zypp/repos.d/*.repo 2>/dev/null || true
    sudo zypper --non-interactive refresh 2>/dev/null || true
    success "openSUSE 源已替换为清华镜像（原 /etc/zypp/repos.d 已备份）"
}

plat_autoupdate() {
    pkg_install yast2-online-update-configuration 2>/dev/null || true
    info "openSUSE 建议用 yast2 online_update 配置自动补丁；或定期执行 sudo zypper patch"
}
```

- [ ] **Step 2: arch.sh**（修 ARM 路径 bug，含 garuda 指引）：

```bash
#!/usr/bin/env bash
#
# essentials/sys-setup/platform/arch.sh — Arch 族（arch/manjaro/garuda）
# mirrorlist 按 ID + uname -m 选路径：
#   arch    x86_64→archlinux    aarch64→archlinuxarm
#   manjaro x86_64→manjaro/stable  aarch64→manjaro-arm/stable
#   garuda  无把握路径，降级指引

_arch_mirror_line() {
    local m; m=$(uname -m)
    case "$DISTRO_ID" in
        arch)
            case "$m" in
                x86_64) echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' ;;
                aarch64) echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$repo/os/$arch' ;;
            esac ;;
        manjaro)
            case "$m" in
                x86_64) echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/manjaro/stable/$repo/$arch' ;;
                aarch64) echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/manjaro-arm/stable/$repo/$arch' ;;
            esac ;;
    esac
}

plat_mirror_preview() {
    case "$DISTRO_ID" in
        arch|manjaro)
            echo "  1. 备份 /etc/pacman.d/mirrorlist"
            echo "  2. 重写为清华 TUNA（${DISTRO_ID} · $(uname -m) 路径）"
            echo "  3. sudo pacman -Sy" ;;
        *)
            echo "  1. ${DISTRO_ID} 暂无把握的镜像路径，仅打印指引（不改动系统）" ;;
    esac
}

plat_mirror_apply() {
    local line ts
    line=$(_arch_mirror_line)
    ts=$(date +%s)
    if [[ -z "$line" ]]; then
        warn "${DISTRO_ID} · $(uname -m) 暂无把握的镜像路径，保持 mirrorlist 不变"
        return 0
    fi
    sudo cp -a /etc/pacman.d/mirrorlist "/etc/pacman.d/mirrorlist.bak.$ts" 2>/dev/null || true
    sudo tee /etc/pacman.d/mirrorlist >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— ${DISTRO_ID} 清华镜像（$(uname -m)）
${line}
EOF
    sudo pacman -Sy 2>/dev/null || true
    success "${DISTRO_ID} mirrorlist 已替换为清华镜像（$(uname -m) 路径）"
}

plat_autoupdate() {
    pkg_install pacman-contrib 2>/dev/null || true
    info "Arch 为滚动发布，建议定期执行 sudo pacman -Syu 保持更新"
}
```

- [ ] **Step 3: alpine.sh**：

```bash
#!/usr/bin/env bash
#
# essentials/sys-setup/platform/alpine.sh — Alpine

plat_mirror_preview() {
    echo "  1. 备份 /etc/apk/repositories"
    echo "  2. 重写为清华 TUNA（v$(uxs_os_release VERSION_ID) main+community）"
    echo "  3. sudo apk update"
}

plat_mirror_apply() {
    local ver ts
    ver=$(uxs_os_release VERSION_ID)
    [[ -z "$ver" ]] && ver="latest-stable"
    ts=$(date +%s)
    sudo cp -a /etc/apk/repositories "/etc/apk/repositories.bak.$ts" 2>/dev/null || true
    sudo tee /etc/apk/repositories >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— Alpine 清华镜像
https://mirrors.tuna.tsinghua.edu.cn/alpine/v${ver}/main
https://mirrors.tuna.tsinghua.edu.cn/alpine/v${ver}/community
EOF
    sudo apk update 2>/dev/null || true
    success "Alpine 源已替换为清华镜像"
}

plat_autoupdate() {
    info "Alpine 无原生自动安全更新；建议定期执行 sudo apk upgrade"
}
```

- [ ] **Step 4:** 三个文件 `bash -n` 语法过
- [ ] **Step 5: Commit** — `git add essentials/sys-setup/platform/ && git commit -m "feat(sys-setup): suse/arch/alpine platform——arch 修 aarch64 路径 bug"`

### Task 7: 重写 `install.sh`（调度骨架 + 预览确认 + autoupdate 分发 + ntp/timezone 迁移）

**Files:**
- Modify: `essentials/sys-setup/install.sh`（删除 `_apt_disable_distro_sources`、`MIRROR_BASE`、`do_mirror` 主体、`do_autoupdate` 的 case 体；新增 `_load_platform`、新 `do_mirror`、新 `do_autoupdate`；`set_ntp_servers`/`do_timezone` 的装 chrony 段改用 `pkg_install`+`uxs_svc`）

**Interfaces:**
- Consumes: 五个 platform 文件的 `plat_*` 接口、`uxs_os_release`、`uxs_svc`、`detect_distro`（设置 `DISTRO_ID`/`DISTRO_FAMILY`）
- Produces: 模块对外子命令不变（mirror/timezone/ntp/optimize/ssh/autoupdate/all/status/help/uninstall）

- [ ] **Step 1: 新增 `_load_platform` 与新 `do_mirror`**（替换原 `do_mirror` 全体；删除原 `MIRROR_BASE` 常量与 `_apt_disable_distro_sources`）：

```bash
# 加载当前发行版族的 platform 实现。
# 返回：0=已加载；2=发行版族未知（调用方 warn 跳过）；1=platform 文件缺失（框架错误）。
_load_platform() {
    detect_distro
    if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
        return 2
    fi
    local plat="$SCRIPT_DIR/platform/${DISTRO_FAMILY}.sh"
    if [[ ! -f "$plat" ]]; then
        error "platform 文件缺失（框架错误）：$plat"
        return 1
    fi
    # shellcheck source=platform/debian.sh
    source "$plat"
}

do_mirror() {
    preflight
    detect_pkg_manager
    local rc=0
    _load_platform || rc=$?
    if [[ "$rc" == "2" ]]; then
        warn "暂不支持该发行版（族未知），跳过换源"
        return 0
    fi
    if [[ "$rc" != "0" ]]; then
        return 1
    fi

    # 严格档：换源属破坏性操作，非交互环境跳过不阻断（无逃生开关）
    if [[ ! -t 0 ]]; then
        warn "换源需交互确认，已跳过（非交互环境）"
        return 0
    fi

    info "🌐 更换软件源为国内镜像"
    echo "── 换源预览 ──────────────────────────────"
    echo "检测到:  ${DISTRO_NAME:-${DISTRO_ID:-未知}} $(uxs_os_release VERSION_ID)$( [[ -n "$(uxs_os_release VERSION_CODENAME)" ]] && echo " ($(uxs_os_release VERSION_CODENAME))" ) · $(uname -m) · ${PKG_MANAGER:-?}"
    echo "执行动作:"
    plat_mirror_preview
    echo "──────────────────────────────────────────"
    if ! yes_no "确认执行换源？"; then
        info "已取消换源"
        return 0
    fi
    plat_mirror_apply
}
```

- [ ] **Step 2: 新 `do_autoupdate`**（替换原 case 体）：

```bash
do_autoupdate() {
    preflight
    info "🛡️  启用自动安全更新"
    local rc=0
    _load_platform || rc=$?
    if [[ "$rc" == "2" ]]; then
        warn "暂不支持该发行版（族未知），跳过自动更新配置"
        return 0
    fi
    if [[ "$rc" != "0" ]]; then
        return 1
    fi
    plat_autoupdate
}
```

- [ ] **Step 3: `set_ntp_servers` 兜底安装段**（替换原 `case "$PKG_MANAGER"` 段；函数开头加 `detect_distro`）：

```bash
    else
        warn "未检测到 NTP 服务，尝试安装 chrony..."
        if pkg_install chrony; then
            local unit="chronyd"
            [[ "$DISTRO_FAMILY" == "debian" ]] && unit="chrony"
            if uxs_svc enable-now "$unit"; then
                if _configure_chrony "$servers"; then
                    success "已安装 chrony 并配置: $servers"
                else
                    error "配置 chrony 失败"; return 1
                fi
            else
                error "chrony 服务启用失败"; return 1
            fi
        else
            error "chrony 安装失败，请手动安装"
            return 1
        fi
    fi
```

- [ ] **Step 4: `do_timezone` 回退段**（替换原 `case "$PKG_MANAGER"` 段；函数开头加 `detect_distro`）：

```bash
    if ! systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        if pkg_install chrony 2>/dev/null; then
            local unit="chronyd"
            [[ "$DISTRO_FAMILY" == "debian" ]] && unit="chrony"
            uxs_svc enable-now "$unit" 2>/dev/null || true
            success "已安装并启用 chrony 时间同步"
        else
            warn "chrony 安装失败，跳过时间同步服务配置"
        fi
    fi
```

- [ ] **Step 5: 校验** — `bash -n essentials/sys-setup/install.sh`；`grep -c '/etc/os-release' essentials/sys-setup/install.sh` 应为 `0`
- [ ] **Step 6: Commit** — `git add essentials/sys-setup/install.sh && git commit -m "refactor(sys-setup): install.sh 收敛为调度骨架，平台实现下沉 platform/；换源加预览确认"`

### Task 8: status/uninstall 核对（零行为变化）

**Files:**
- 只读核对 `essentials/sys-setup/install.sh` 的 `status_sys_setup`/`uninstall_sys_setup`

- [ ] **Step 1:** 确认两函数未被 Task 7 误改：`git diff HEAD~1 -- essentials/sys-setup/install.sh | grep -E 'status_sys_setup|uninstall_sys_setup'` 应无输出
- [ ] **Step 2:** 本机（macOS）跑 `./essentials/sys-setup/install.sh status` 应输出 `n/a`；`help` 正常；未知子命令退出 1
- [ ] **Step 3:** 无代码改动则无 commit（本任务是核对门）

### Task 9: CI 静态断言 + 全量回归

**Files:**
- Modify: `tests/ci_run.sh`（9c 段断言目标迁移 + 新增 9d 段）

- [ ] **Step 1: 修正 9c** — 原 `ss_path/install.sh` 的两条断言改为指向 `platform/debian.sh`：

```bash
    assert "sys-setup: mirror 重写 deb822 ubuntu.sources" bash -c "grep -q 'sources.list.d/ubuntu.sources' \"$REPO_DIR/$ss_path/platform/debian.sh\""
    assert "sys-setup: 停用残留源逻辑存在" bash -c "grep -q '_apt_disable_distro_sources()' \"$REPO_DIR/$ss_path/platform/debian.sh\""
```

- [ ] **Step 2: 新增 9d 段**（9c 之后）：

```bash
    # 9d. sys-setup：platform 拆分 + 换源矩阵（platform-abstraction 2026-08-28）
    assert "sys-setup: platform 五文件齐全" bash -c "for f in debian rhel suse arch alpine; do test -f \"$REPO_DIR/$ss_path/platform/\$f.sh\"; done"
    assert "sys-setup: do_mirror 含预览确认" bash -c "grep -q '换源预览' \"$REPO_DIR/$ss_path/install.sh\""
    assert "sys-setup: 非交互跳过逻辑" bash -c "grep -q '非交互环境' \"$REPO_DIR/$ss_path/install.sh\""
    assert "sys-setup: alma/rocky/fedora 模板指向实测可用站" bash -c "grep -q 'mirrors.aliyun.com/almalinux' \"$REPO_DIR/$ss_path/platform/rhel.sh\" && grep -q 'mirrors.ustc.edu.cn/rocky' \"$REPO_DIR/$ss_path/platform/rhel.sh\" && grep -q 'mirrors.tuna.tsinghua.edu.cn/fedora' \"$REPO_DIR/$ss_path/platform/rhel.sh\""
    assert "sys-setup: openEuler/Anolis sed 存在" bash -c "grep -q 'mirror.openeuler.org' \"$REPO_DIR/$ss_path/platform/rhel.sh\" && grep -q 'openanolis' \"$REPO_DIR/$ss_path/platform/rhel.sh\""
    assert "sys-setup: arch 分支含 archlinuxarm 与 uname -m" bash -c "grep -q 'archlinuxarm' \"$REPO_DIR/$ss_path/platform/arch.sh\" && grep -q 'uname -m' \"$REPO_DIR/$ss_path/platform/arch.sh\""
    assert "sys-setup: 不再手写 os-release 识别" bash -c "! grep -qE '\. /etc/os-release' \"$REPO_DIR/$ss_path/install.sh\""
```

- [ ] **Step 3: 本地全量** — `bash tests/unit_platform.sh && bash tests/unit_disk_smart.sh && bash -n tests/ci_run.sh`；可行则跑 `NO_COLOR=1 bash tests/ci_run.sh --phase static`
- [ ] **Step 4: dry-run 回归** — `UNIX_SCRIPT_DRY_RUN=1 ./install.sh sys-setup mirror </dev/null` 应输出"非交互跳过"；`echo 1 | UNIX_SCRIPT_DRY_RUN=1 ./install.sh sys-setup ssh` 类确认流只打印
- [ ] **Step 5: Commit** — `git add tests/ci_run.sh && git commit -m "test(ci): sys-setup platform 拆分静态断言（矩阵站点/预览/防退化）"`

### Task 10: spec 文档同步 + PR 2 收尾

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-mirror-matrix-upgrade-design.md`（第五节"不做镜像站选择"改为"按发行版固定站点"；rpm 系节补 Alma→阿里云、Rocky→USTC、Anolis→阿里云、fedora updates 路径无 `/os`）
- Modify: `docs/superpowers/specs/2026-08-28-platform-abstraction-design.md`（§2.4 补一句镜像站映射表引用）

- [ ] **Step 1:** 两份 spec 按实测结论修订（记录 2026-08-28 实测依据），commit：`git commit -am "docs(spec): 换源矩阵镜像站按发行版固定（2026-08-28 实测：TUNA 无 alma/rocky/anolis）"`
- [ ] **Step 2:** 推送分支并建 PR（`feat/lib-platform-helpers` → PR 1；`feat/syssetup-platform-split` → PR 2，描述附镜像站实测表）——**此步执行前向用户确认**（对外动作）
- [ ] **Step 3:** 实机验收（用户侧）：murphy-server（Ubuntu 26.04）`./install.sh sys-setup mirror` 核对预览框与 deb822 重写；macOS 本机 `status`/`help` 回归
