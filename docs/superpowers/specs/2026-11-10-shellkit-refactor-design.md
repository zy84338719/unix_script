# unix_script × shellkit 重构设计（程序级）

日期：2026-11-10
状态：待评审
适用仓库：`zy84338719/unix_script`（主）、`shellkit`（上游库）

---

## 0. 一句话

把 unix_script 里手写的通用能力（日志、包管理、服务管理、校验、下载、超时、i18n、状态契约、模块注册表）下沉到 shellkit，
unix_script 只保留「模块领域逻辑 + 交互 UI」，并把 78 个模块的面向用户文案全量改为 gettext 机制、
CLI 一次性切换到新的分组子命令面。

---

## 1. 背景

unix_script 是 78 个模块、约 3 万行 shell 的脚本库。它的 `lib/` 层自己实现了一整套本该由库提供的通用能力：

| `lib/common.sh` 里的通用能力 | unix_script 自己的实现 |
|---|---|
| 彩色日志 | `info/success/warn/error/header/menu`（6 个函数，877 行文件的一部分） |
| 平台探测 | `detect_os/detect_arch` |
| 发行版/桌面检测 | `detect_distro/detect_desktop`（含麒麟/统信/openEuler 词表与 CI 真值断言） |
| 包管理 | `detect_pkg_manager/pkg_install/pkg_remove/pkg_installed/pkg_update/ensure_epel`（自带 sudo 提权、pacman、brew） |
| 命令存在性 | `command_exists/check_commands` |
| 下载校验 | `verify_sha256` |
| GitHub API | `github_latest_tag/github_release_asset_url`（jq + grep 双路径） |
| 版本比较 | `version_gt` |
| dry-run | `dry_run_exec/dry_run_sudo/uxs_install_sudo_shim`（**用同名 bash 函数遮蔽 `sudo` 二进制**） |
| 超时 | `uxs_with_timeout/uxs_func_with_timeout`（perl fork + alarm / 后台 watchdog） |
| 服务管理 | `uxs_svc/service_start/service_stop/service_is_active/install_systemd_unit` |

shellkit 已经是一个成熟的通用 Bash 库（18 模块、退出码契约 0/1/2/3/4/5、gettext 化、bash 3.2 基线、自带门禁），
但缺 unix_script 需要的这些能力。反过来，unix_script 有一批**领域能力**（manifest 注册表、平台可见性、依赖拓扑、
STATE 状态契约、profile 导出/应用）是可以通用化的。

结论：两边都动 —— shellkit 抽出通用部分，unix_script 用上。

---

## 2. 现状盘点

### 2.1 unix_script

- **规模**：78 个带 `.manifest` 的模块（services 34 / sys-tools 16 / dev-tools 19 / essentials 6 / ai-tools 3），
  134 个 shell 文件、约 3 万行。最大模块 `sys-tools/disk-usage/install.sh` 855 行。
- **框架层** `lib/`：`common.sh`(877) `menu.sh`(621) `submenus.sh`(380) `status.sh`(272) `registry.sh`(276)
  `profile.sh`(209) `uxs_cli.sh`(217) `scaffold.sh`(165) `doctor.sh`(141) `deps.sh`(82) `menu_fzf.sh`(59)
  `core.sh`(49) `suggest.sh`(115)。
- **入口**：`install.sh`（292 行，扁平 flag 分发）+ `bootstrap.sh`（克隆整仓后透传参数）。
- **模块契约**：每个模块目录下 `.manifest`（11 个字段：`LABEL/DESC/CATEGORY/DEFAULT_ACTION/ALIASES/NEXT_STEPS/
  PLATFORMS/HAS_SUBMENU/REQUIRES/EXPORTABLE/ENTRY_SCRIPT`）+ `install.sh`（子命令 `install|uninstall|status|help`）。
- **机器契约**：`UXS_STATUS_MODE=machine` 下输出 `STATE=/VERSION=/EXTRA=` 行；`--status-json` 输出 `key:value`；
  `--list-modules` 输出 TSV。AI agent 的 `AGENTS.md` 明确依赖这些形状。
- **交付形态**：`curl | bash` 引导 → 克隆整仓到 `~/.local/share/unix_script` → 跑 `install.sh`。
  ⇒ **仓库内自带一份 shellkit 副本是可行的**（克隆即带，无需目标机预装）。
- **测试**：`tests/ci_run.sh --phase static|routing|install` + 6 个 `unit_*.sh`。

### 2.2 shellkit

- 18 个模块：`i18n log error str validate trap fs os scaffold run retry lock net http config prompt cli man`。
- 亮点：唯一入口 `lib/bootstrap.sh`（`SHELLKIT_MODULES` 按需加载）、模块清单唯一真相源 `lib/modules.txt`、
  退出码契约（0 成功 / 1 一般错 / 2 用法错 / 3 前置不满足 / 4 网络 / 5 校验失败）、
  stdout 只给数据日志走 stderr、出参用 `printf -v`、bash 3.2 基线、gettext（msgid 英文，`locale/{en,zh_CN,zh_Hant}`）。
- 门禁：`make check` = syntax + test + lint + module-order-check + check-exitcode-docs + local-names-check +
  module-count-check + pipe-safety-check + docs-check + versions-check + check-docs + cookbook-check +
  messages-check + examples + fmt。CI 是 macOS 3.2 / Ubuntu 5.x 双矩阵。
- 版本纪律：0.x 内**只加不改**；改既有函数的结果要升 minor 并写 `docs/MIGRATING.md`；只加不改升 patch。

### 2.3 能力差表（缺口清单）

| 能力 | unix_script | shellkit | 结论 |
|---|---|---|---|
| 彩色日志 | 有 | 有 | 直接换 |
| 平台/架构探测 | 有 | 有 | 直接换（全局变量 → 函数） |
| 发行版/桌面检测 | 有 | **无** | shellkit 新增 |
| 包管理（提权/pacman/brew/remove/installed） | 有 | 部分（无提权、无 pacman/brew、无 remove） | shellkit 新增，既有 `os_pkg_*` 语义不动 |
| systemd/launchd 服务动词 | 有 | **无** | shellkit 新增 `svc` 模块 |
| 版本比较 | 有 | **无** | shellkit 新增 `ver` 模块 |
| GitHub release 查询 | 有 | 有 http 但无 GitHub 语义 | shellkit 新增（基于 `net_json`） |
| 超时包装 | 有 | **无** | shellkit 新增（`run_timeout`） |
| STATE 状态契约 | 有 | **无** | shellkit 新增 `status` 模块 |
| manifest 注册表 + 依赖拓扑 | 有 | **无** | shellkit 新增 `registry` 模块（通用 KV 注册表，字段语义留给 unix_script） |
| profile 导出/应用 | 有 | **无** | shellkit 新增 `profile` 模块 |
| 多域 i18n + 无 gettext 兜底 | 无（中文硬编码） | 单域、缺 gettext 时回落英文 | shellkit 扩展 |
| 菜单/fzf/doctor/自更新/suggest | 有 | 无 | 留 unix_script |
| CLI 框架 | 扁平 flag | `cli_cmd` 注册式 | unix_script 改用 `cli` 框架 |

---

## 3. 目标与非目标

### 3.1 目标

1. unix_script 的通用能力全部由 shellkit 提供，unix_script 不再自造轮子。
2. shellkit 补齐「模块化安装框架」所需的通用机制（注册表 / 状态契约 / profile / 服务 / 包管理 / 发行版）。
3. 78 个模块的面向用户文案全量转为 gettext（msgid 英文 + `zh_CN` 译文），框架层与模块层口径一致。
4. CLI 一次性切换到分组子命令面，旧扁平 flag 全部删除，同步更新 `AGENTS.md`/`README.md`/`docs/`/`bootstrap.sh`/CI。
5. 全过程保持 unix_script 的领域能力不丢失：78 个模块、manifest 11 字段、平台可见性、依赖拓扑、
   状态契约语义、profile 语义、菜单体验。
6. 两个仓库各自的门禁始终绿；unix_script 额外获得「行为快照对比」门禁。

### 3.2 非目标

- 不重写模块的**业务逻辑**（装什么、怎么装、装到哪），只换实现底座与文案抽取方式。
- 不改变 `.manifest` 的 11 个字段名与含义（模块数量与元数据保持兼容）。
- 不引入 shellkit 之外的第三方运行时依赖（bash 3.2 / coreutils / curl 级别）。
- 不在本程序内做 unix_script 的功能新增（只做重构与必要的兼容修复）。

---

## 4. 总体架构

### 4.1 分层

```
┌──────────────────────────────────────────────────────────────┐
│ unix_script 领域层                                            │
│   78 个模块脚本（业务逻辑 + msgid 化文案）                     │
│   菜单 UI（menu / menu_fzf / submenus）· doctor · 自更新        │
│   模块脚手架 scaffold · suggest · uxs 全局命令                 │
└───────────────┬──────────────────────────────┬───────────────┘
                │ 领域适配层 lib/uxs_*.sh      │ 通用能力
                │ （薄转发 + 少量 unix_script   ▼
                │   特有语义：manifest 字段名、  shellkit 通用层
                │   分类目录布局、裸 sudo 遮蔽）   lib/core/*.sh
                ▼                             log error str validate trap
     vendor/shellkit/（随仓分发）             fs os scaffold run retry lock
                                              net http config prompt cli man i18n
                                              + 新增：svc ver status registry profile
```

### 4.2 依赖方向

- **单向**：unix_script → shellkit。shellkit **不得**引用 unix_script 的任何概念（不出现 `unix_script`、
  `UXS_`、`manifest` 字段名等）。
- shellkit 提供**机制**，unix_script 提供**语义**：例如 `registry` 模块提供「扫描 KV 清单、查询字段、
  按平台过滤、依赖拓扑」；哪些字段叫 `LABEL`/`PLATFORMS` 是 unix_script 的事。

### 4.3 vendor 与版本纪律

- unix_script 仓内放 `vendor/shellkit/`（由 `shellkit vendor` 同步），随仓库分发，克隆即带。
- 门禁 `tools/check_vendor.sh`：比对 `vendor/shellkit/` 与 `shellkit vendor --check` 的结果，
  不一致即红（防止手改副本或忘记同步）。
- shellkit 侧遵守 0.x「只加不改」：Stage 1 的新增全部是**新函数/新模块**，
  既有 `os_pkg_install`、`os_pkg_update`、`_t` 等语义保持不变，需要新行为就开新函数。
- 版本：Stage 1 的 shellkit 变更全是新增 ⇒ 按 shellkit 纪律升 patch（0.10.1），
  但新增 6 个模块属于能力扩展，是否升 minor 由发版时按 `docs/MIGRATING.md` 的判定执行。

---

## 5. 能力归属裁决

| 现有符号（unix_script） | 目标归属 | 目标 API | 迁移策略 |
|---|---|---|---|
| `info/success/warn/error` | shellkit | `log_info/log_ok/log_warn/log_error` | Stage 1 删除，适配层转发 |
| `header/menu` | shellkit | `log_section` + unix_script 自留 `uxs_menu`（外观属 UI） | 保留 UI 层 |
| `detect_os/detect_arch` | shellkit | `os_name/os_arch` | 删除全局 `OS_TYPE/ARCH_TYPE`，改函数调用 |
| `detect_distro/detect_desktop` | shellkit | `os_distro_id/os_distro_family/os_release_field/os_desktop_env` | 新增，unix_script 转发 |
| `detect_pkg_manager` | shellkit | `os_pkg_manager` | 直接换 |
| `pkg_install/pkg_remove/pkg_installed/pkg_update` | shellkit | `os_pkg_install_root/os_pkg_remove/os_pkg_installed/os_pkg_update_root` | **新函数**，既有 `os_pkg_*` 不动 |
| `ensure_epel` | unix_script | — | 领域特定，留 unix_script |
| `command_exists/check_commands` | shellkit | `os_has_cmd/require_cmd` | 直接换 |
| `require_sudo` | shellkit | `os_sudo_ready`（保证可用 sudo 而非「必须 root」） | 新增，语义与 `require_root` 分开 |
| `dry_run_exec/dry_run_sudo` | shellkit | `run` / `run --always` | 直接换 |
| `uxs_install_sudo_shim` | shellkit（机制）+ unix_script（启用） | `run_install_sudo_shim` | 新增：shellkit 提供实现，unix_script 在 dry-run 时调用 |
| `verify_sha256` | shellkit | `net_verify` | 直接换 |
| `github_latest_tag/github_release_asset_url` | shellkit | `http_github_latest_tag/http_github_release_asset` | 新增（基于 `net_json`，无 jq 依赖） |
| `version_gt` | shellkit | `ver_gt/ver_cmp` | 新增 |
| `uxs_with_timeout/uxs_func_with_timeout` | shellkit | `run_timeout/run_func_timeout` | 新增 |
| `get_local_ip` | unix_script | — | 领域特定，留 |
| `uxs_svc/service_*/install_systemd_unit` | shellkit | `svc_*` | 新增 `svc` 模块 |
| `emit_status/emit_version/emit_extra/uxs_is_machine_mode` | shellkit | `status_emit/status_version/status_extra/status_is_machine` | 新增 `status` 模块 |
| `registry_*`（11 字段语义） | shellkit（机制）+ unix_script（字段语义） | `registry_*` | 新增 `registry` 模块，字段名由 unix_script 传入 |
| `resolve_deps/topo_sort_all` | shellkit | `registry_deps/registry_topo` | 新增 |
| `export_profile/apply_profile` | shellkit | `profile_export/profile_apply` | 新增 `profile` 模块 |
| `suggest_module`（levenshtein） | shellkit | `str_suggest` | 新增（放 `str`） |
| `menu/menu_fzf/interactive_main/submenus` | unix_script | — | UI 层，留 |
| `run_doctor` | unix_script | — | 诊断规则是领域知识，留 |
| `scaffold_module` | unix_script（底座用 shellkit `scaffold`） | — | 留 |
| `check_for_update/do_self_update/print_update_hint` | unix_script（用 shellkit 的 GitHub 查询） | — | 留 |
| `lib/uxs_cli.sh`（uxs 全局命令） | unix_script | — | 留 |

---

## 6. shellkit 侧规格（Stage 1）

每个新增模块都遵守 shellkit 既有约定：公开函数上方紧邻注释行、注释里写 `@exitcode`、
模块清单 `lib/modules.txt` 按拓扑序声明依赖、每个模块配 `tests/test_<name>.sh`。

### 6.1 `i18n` 扩展（只加不改：默认行为逐字不变）

现状：`_t` 依赖 `gettext` 二进制，缺失时回落英文。对 unix_script 这种「中文优先」的产品，
缺 gettext ⇒ 输出变英文，是不可接受的。

**纪律**：以下能力全部由新环境变量开关，**不设时 `_t` 的行为与现状逐字一致** ⇒ 属「只加不改」，
可按 patch 版本发布；若将来要改默认值则必须按 minor + `docs/MIGRATING.md` 处理。

**新增能力**（不改 `_t` 的既有签名与行为）：

1. **多目录 / 多域查找**：新增 `SHELLKIT_I18N_DIRS`（冒号分隔的目录列表）与 `SHELLKIT_I18N_DOMAIN`（域覆盖）。
   `_t` 先查 `$SHELLKIT_I18N_DOMAIN`（默认 `shellkit`）在 `$SHELLKIT_I18N_DIRS` 各目录下的
   `<lang>/LC_MESSAGES/<domain>.mo`；命中即用；未命中再按既有单域逻辑走。
   ⇒ unix_script 侧：`SHELLKIT_I18N_DIRS="<repo>/locale:$SHELLKIT_HOME/locale"`、`SHELLKIT_I18N_DOMAIN=unix_script`。
2. **纯 bash 兜底表**：新增 `locale/<lang>/messages.sh`（构建产物，**入库**），内含一个巨型 `case`：
   ```bash
   _sk_msg_lookup() {
     case "$1" in
       'invalid command name') printf '%s' '非法的命令名' ;;
       ...
     esac
   }
   ```
   `_t` 在**没有 gettext** 时：若 `messages.sh` 存在则查表，命中返回译文；
   未命中回落 msgid（英文）。
   ⇒ 保证「目标机没装 gettext 时，unix_script 仍然输出中文」。
   构建链：`po/messages.sh` 增加一步，用 `awk` 从 `.po` 生成 `messages.sh`（纯文本解析，无需 msgfmt）。
3. **上下文变量支持**：可选 `SHELLKIT_I18N_CTX` 走 `msgctxt`（unix_script 首轮不用，留接口）。

**验收**：① 有 gettext 时译文正确；② 把 gettext 从 PATH 摘掉后译文仍正确；
③ `make messages-check` 仍绿（pot/po 与源码 msgid 一致）；④ 新增 msgid 必须同时进 `po` 与 `messages.sh`（门禁查）。

### 6.2 `os` 扩展（新增函数，既有函数语义不动）

```
os_release_field KEY [FILE]      读 os-release 风格文件字段；恒 0，读不到返回空
os_distro_id [FILE]              小写发行版 ID（ubuntu/debian/kylin/uos/openeuler…）
os_distro_family [FILE]          debian|rhel|suse|arch|alpine|unknown
os_distro_name [FILE]            PRETTY_NAME
os_desktop_env                   ukui|dde|gnome|kde|xfce|mate|cinnamon|lxqt|budgie|none
os_is_desktop                    0/1
os_pkg_install_root PKG...       提权安装（root 直跑，否则 sudo）；支持 apt-get/dnf/yum/zypper/pacman/apk/brew
os_pkg_remove_root PKG...        提权卸载
os_pkg_update_root               提权刷新索引
os_pkg_installed PKG             0=已装
os_sudo_ready                    sudo 可用（root 直过；否则 `sudo -n true` 或 `sudo -v` 提示一次）
```

- 族判定沿用 unix_script 的三段式（包管理器实测 → `ID_LIKE` 词表 → `ID` 词表），**麒麟不入 ID 硬表**的既有教训保留。
- 提权与 dry-run：`os_pkg_install_root` 在 `SHELLKIT_DRY_RUN=1` 时只打印不执行（与 `run` 一致）。

### 6.3 新模块 `svc`（服务动词）

```
svc_start UNIT | svc_stop UNIT | svc_restart UNIT | svc_reload UNIT
svc_enable UNIT | svc_disable UNIT | svc_enable_now UNIT | svc_disable_now UNIT
svc_is_active UNIT | svc_is_enabled UNIT
svc_daemon_reload
svc_install_unit NAME             从 stdin 读 unit 内容写入系统目录并 daemon-reload
svc_platform                     systemd|launchd|none
```

- Linux → systemd；macOS → launchd（`svc_install_unit` 在 macOS 返回 3 前置不满足）。
- 写类动作全部支持 `SHELLKIT_DRY_RUN=1`（只打印）。
- 退出码：0 成功 / 2 用法错 / 3 当前平台不支持 / 4 systemd 自身失败。
- 依赖：`error i18n log os run`。

### 6.4 新模块 `ver`（版本比较）

```
ver_cmp A B         打印 -1 / 0 / 1（A<B / A=B / A>B）
ver_gt A B           A > B 时 0
ver_lt A B           A < B 时 0
ver_eq A B           相等时 0
```

- 去掉前导 `v`/`V`；非法版本串**保守判否**（不误报有更新），与 unix_script 既有 `version_gt` 口径一致。
- 不依赖 GNU `sort -V`（macOS BSD sort 支持但行为差异多）⇒ 纯 bash 分段比较。

### 6.5 新模块 `status`（机器可读状态契约）

```
status_emit STATE HUMAN_MSG      机器模式打印 "STATE=<state>"；人类模式打印人类文案
status_version VERSION           机器模式打印 "VERSION=<v>"
status_extra KEY=VALUE           机器模式打印 "EXTRA=<k=v>"
status_is_machine                机器模式 0 / 人类模式 1
status_state                     合法状态码集合校验
```

- 状态码有限集：`not_installed / installed / installed:running / installed:stopped /
  configured / not_configured / n/a`。
- 机器模式判定走 `SHELLKIT_STATUS_MODE=machine`（unix_script 侧保留 `UXS_STATUS_MODE` 兼容读取）。

### 6.6 新模块 `registry`（KV 清单注册表 + 依赖拓扑）

通用机制，不含 unix_script 的字段名：

```
registry_scan DIR PATTERN         扫描目录下的清单文件，建立索引
registry_get MODULE KEY           取字段值（支持逗号分隔列表的按元素查询）
registry_list [FILTER]            列出已注册条目
registry_visible MODULE           平台可见性判定（清单里的 PLATFORMS 类字段）
registry_deps MODULE              传递依赖（拓扑序）
registry_topo                     全体拓扑序
```

- 清单格式：**每行 `KEY=VALUE`**，与 unix_script 的 `.manifest` 同构 ⇒ unix_script 的 11 个字段零改动直接被索引。
- 平台字段、依赖字段的名字由调用方传入（`registry_scan` 的参数），shellkit 内部不出现 `PLATFORMS`/`REQUIRES` 字面量。
- 依赖拓扑：bash 3.2 兼容（空格分隔集合 + 后序 DFS），环检测报错并返回非 0。

### 6.7 新模块 `profile`（配置复现）

```
profile_export FILE MODULE...     导出（每行 "MODULE key=value ..."）
profile_apply FILE [FORCE]        应用（把 key=value 注入为环境变量传给模块）
profile_parse FILE                解析为 "MODULE<TAB>k=v,k=v"
```

- 格式与 unix_script 现状一致 ⇒ 存量 profile 文件继续可读。

### 6.8 `http` 扩展（GitHub）

```
http_github_latest_tag REPO       最新 release 的 tag（去 v 前缀）
http_github_release_asset REPO PATTERN   匹配 browser_download_url
```

- 基于 `net_json`，不依赖 jq；支持 `GH_TOKEN`/`GITHUB_TOKEN` 认证头；网络失败返回 4（SK_NET）。

### 6.9 `run` 扩展

```
run_timeout SEC CMD...            超时返回 124（对齐 GNU timeout）；无 perl 时退化为无超时
run_func_timeout SEC FN [ARG...]  对当前 shell 的函数加超时（返回 143）
run_install_sudo_shim             安装同名 bash 函数遮蔽 sudo 二进制（仅 dry-run 时调用）
```

- `run_install_sudo_shim` 是**显式调用才生效**的全局副作用，shellkit 默认不调用（保持「不改变调用方 shell 行为」的既有纪律）。

### 6.10 `str` 扩展

```
str_suggest WORD [CANDIDATE...]   编辑距离最近的候选（纯 bash，bash 3.2 兼容）
```

---

## 7. unix_script 侧规格

### 7.1 vendor 接入与门禁

- `vendor/shellkit/` 入库（`lib/` `locale/` `templates/` `tests/{test_helper.sh,run.sh}` `VERSION`
  `shellkit` `LICENSE` `NOTICE`，与 `shellkit vendor` 产出一致）。
- 新增 `tools/check_vendor.sh`：跑 `vendor/shellkit/shellkit vendor --check` 等价校验，副本与上游不一致即红。
- 所有模块脚本与 lib 通过**一个入口**加载 shellkit：
  ```bash
  source "${SCRIPT_DIR}/vendor/shellkit/lib/bootstrap.sh"
  ```
  并设置 `SHELLKIT_MODULES` 按需加载（模块脚本通常只要 `log os run net`）。

### 7.2 `lib/` 瘦身（文件级）

| 文件 | Stage 1 动作 | 最终归属 |
|---|---|---|
| `lib/common.sh` | **拆解**：通用函数删除，保留项改为转发到 shellkit；剩余领域件移入 `lib/uxs_compat.sh` | 过渡门面，Stage 3 模块迁完后删除 |
| `lib/uxs_compat.sh`（新） | 旧符号 → shellkit 新 API 的薄转发（`info→log_info`、`pkg_install→os_pkg_install_root`…） | Stage 3 删除 |
| `lib/uxs_i18n.sh`（新） | 设置 `SHELLKIT_I18N_DOMAIN/DIRS`、加载 unix_script 域的 `messages.sh` | 留 |
| `lib/registry.sh` | 保留字段语义（LABEL/DESC/…），扫描与查询改调 `registry_*` | 留（薄） |
| `lib/deps.sh` | 改为调用 `registry_deps/registry_topo`，保留环检测错误文案 | 留（薄） |
| `lib/status.sh` | 改调 `status_*`，保留 `--status-json` 的输出形状（CLI v2 前） | 留 |
| `lib/profile.sh` | 改调 `profile_*` | 留 |
| `lib/core.sh` `lib/menu.sh` `lib/menu_fzf.sh` `lib/submenus.sh` `lib/suggest.sh` `lib/doctor.sh` `lib/scaffold.sh` `lib/uxs_cli.sh` | 逻辑不变（仅日志改用 shellkit） | 留 |

> **过渡门面是必须的**：Stage 1 不动 78 个模块脚本，若直接删除 `info/pkg_install` 等旧名，全部模块立刻崩。
> 门禁靠「行为快照对比」保证门面转发与原实现**逐字等价**。

**Stage 1 的细化（实施时确定，写入实施计划）**：

1. **只换「能力函数」，不换「呈现函数」**。`info/success/warn/error/header/menu` 走 **stdout**
   且标签是 `[SUCCESS]`/`[WARNING]`；shellkit 的 `log_*` 走 **stderr** 且标签是 `[ OK ]`/`[WARN]`。
   直接换会同时打破快照与 AI agent 的解析约定 ⇒ 呈现函数留到 **Stage 3 随 78 个模块的 msgid 化一起收敛**。
2. **快照只覆盖三类确定性输出**：`--list` / `--list-modules` / `--list-categories`。
   `--status-json` 与各模块 `status` 依赖**本机实际安装状态**，跨机器必然不同 ⇒ 改成**结构判据**
   （每行 `key:value`、状态码在有限集里），不做逐字基线。
3. **profile 模块在 shellkit 侧只提供文件格式原语**（写/追加/解析/转环境变量）；
   「导哪些模块、哪些键」「apply 时怎么装」是领域逻辑，留 unix_script。

### 7.3 模块契约 v2

- `.manifest` 的 11 个字段名与含义**不变**（`registry` 模块直接索引）。
- 模块子命令 `install|uninstall|status|help` 不变；额外子命令（`bun mirror` 等）不变。
- `status` 子命令**恒返回 0**（既有纪律），机器模式输出 `STATE=/VERSION=/EXTRA=` 不变。

### 7.4 CLI v2（Stage 2）

新命令面（分组子命令）：

```
uxs install <mod> [--no-deps] [--dry-run]     uxs list [--all] [--category <cat>]
uxs remove <mod>                               uxs search <kw>
uxs status [mod...] [--json] [--all]           uxs info <mod>
uxs doctor        uxs export [--out FILE]      uxs apply <profile> [--force] [--dry-run]
uxs update        uxs scaffold <mod>            uxs completions <shell>
uxs --help / --version / --list-all
```

**删除的旧 flag（一次性，无兼容期）**：
`--list` `--list-modules` `--list-categories` `--status` `--status-json` `search` `export`/`export-profile`
`apply`/`apply-profile` `cli`/`install-cli` `uninstall-cli`/`remove-cli` `completions` `scaffold` `doctor`
`check-update` `update`。

**必须同步更新的位置**（漏一处即破）：
`unix_script/AGENTS.md`（AI agent 工作流整章重写）、`README.md`、`docs/`、`bootstrap.sh` 的用法注释、
`lib/menu.sh` 的自更新提示、`tests/ci_run.sh` 的 routing 阶段、`.github/workflows/ci.yml`、
以及文档站（若 unix_script 有站点）。

### 7.5 i18n 全量转换

**规则**：

1. 面向用户的**全部**文案（log 文案、菜单项、提示、报错、状态人类文案、模块 help）改为 `_t 'english msgid'`。
2. msgid 一律**英文**；中文译文进 `unix_script/locale/zh_CN/LC_MESSAGES/unix_script.po`。
3. 机器契约输出（`STATE=` `VERSION=` `EXTRA=` `--status-json` 的 key）**不翻译**。
4. msgid 里不插值变量：用 `printf` 组合（`_t 'installing'` + 值），或用 `%s` 占位 + shellkit 侧的格式化约定；
   **禁止**把值拼进 msgid（会制造 msgid 爆炸）。
5. 每个模块的文案在自己的 po 段里归拢，便于按模块维护。

**构建链**：`unix_script/po/messages.sh`（仿 shellkit 的 `po/messages.sh`）：
xgettext（扫 `lib/` + `*/*/*.sh`）→ pot → msgmerge → po → msgfmt → mo **+** 生成 `messages.sh` 兜底表。

**门禁**：`tools/check_messages.sh`（对齐 shellkit 的 `messages-check`）：
pot 与源码 msgid 一致、po 无缺失 msgid、`messages.sh` 与 po 一致、**死 msgid**（源码已删）报警。

**工作量**：78 模块 × 平均 10~30 条文案 ⇒ 约 1500~2500 条 msgid。分批随 Stage 3 迁移进行。

### 7.6 退出码统一

- 全库统一到 shellkit 的 0/1/2/3/4/5：
  0 成功 / 1 一般错误 / 2 用法错 / 3 前置不满足（缺命令、非 root、无默认值）/ 4 网络失败 / 5 校验失败。
- `status` 类子命令恒 0（既有纪律不变）。
- Stage 1 只在**框架层**统一（install.sh 分发、doctor、export/apply），模块脚本的退出码在 Stage 3 随迁移统一。

---

## 8. 分阶段路线与验收

| 阶段 | 范围 | 产出 | 验收门禁 |
|---|---|---|---|
| **Stage 0 基线** | unix_script 开分支 `refactor/shellkit`；建行为快照门禁 | `tools/snapshot/` + `tools/check_snapshot.sh`；快照基线入库 | 快照生成可重复；对现有 CLI 产出稳定基线 |
| **Stage 1 库换壳** | shellkit 补齐 10 处能力（i18n 扩展 / os 扩展 / svc / ver / status / registry / profile / http / run / str）+ unix_script `lib/` 换壳 + vendor 接入 | shellkit 新版本发布；unix_script `lib/common.sh` 拆解为转发门面 | 两仓 `make check` 绿；unix_script 快照**零差异**；`make vendor-check` 绿 |
| **Stage 2 CLI v2** | 新分组子命令面 + 删旧 flag + 文档/AGENTS/CI 同步 | CLI v2 + 快照基线重生成 | CLI v2 快照基线入库；`ci_run.sh routing` 改写并通过 |
| **Stage 3 模块迁移** | 78 模块分 5 批（services → sys-tools → dev-tools → essentials → ai-tools），每批：换 shellkit API + 文案 msgid 化 + 退出码统一 | 迁移后的模块脚本 + po 译文 | 每批：快照零差异（有意变更登记在案）、shellcheck 绿、模块级 status 输出对比一致 |
| **Stage 4 收口** | 删过渡门面 `lib/uxs_compat.sh`；文档站与 AGENTS.md 终稿；两仓发版 | 终态代码库 | 全量门禁绿；CLI v2 与快照一致；发版说明（MIGRATING） |

**Stage 1 的具体工作项**（首个实施计划的输入）：

1. shellkit：`i18n` 多域 + `messages.sh` 兜底 + 纯 bash 查表。
2. shellkit：`os` 扩展（发行版/桌面/提权包管理/sudo 就绪）。
3. shellkit：新模块 `svc`、`ver`、`status`、`registry`、`profile`。
4. shellkit：`http` 加 GitHub 查询、`run` 加超时与 sudo shim、`str` 加 `str_suggest`。
5. shellkit：`lib/modules.txt` 增行 + 每个新模块的 `tests/test_*.sh` + 门禁同步。
6. unix_script：vendor 接入 + `tools/check_vendor.sh`。
7. unix_script：`lib/common.sh` 拆解 → `lib/uxs_compat.sh` 转发门面 + `lib/uxs_i18n.sh`。
8. unix_script：`lib/registry.sh`/`deps.sh`/`status.sh`/`profile.sh` 改调 shellkit。
9. unix_script：Stage 0 的快照门禁建立并跑绿。

---

## 9. 测试与门禁策略

**unix_script 侧**

- **行为快照**（新增，最关键）：对 `--status-json`、`--list-modules`、每个模块的 `status` 输出、
  `doctor`、`export` 产出做 golden 快照；重构后逐字对比。
  有意变更必须走「登记」流程（快照目录下的 `.approved` 说明文件），防止「顺手改了」被放过。
- 既有 `tests/ci_run.sh --phase static|routing|install` 保持；routing 阶段随 CLI v2 改写。
- shellcheck（既有 `.shellcheckrc`）与 bash 3.2 兼容（禁用 `declare -A`/`${v^^}`/`mapfile`/`[[ -v ]]`）。
- CI 矩阵：macOS 3.2 / Ubuntu 5.x（与 shellkit 一致）。

**shellkit 侧**：沿用既有 `make check` 全套门禁；新增模块必须带测试与 `@exitcode` 文档；
`docs/REFERENCE.md` 与 `AGENTS.md` 同步重生成。

**跨仓**：unix_script 的 vendor 副本与 shellkit 上游的一致性门禁（`tools/check_vendor.sh`）。

---

## 10. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| i18n 转换漏网（硬编码中文残留） | 输出中英混杂 | 门禁扫「模块脚本里的中文字符」并报警（允许清单制） |
| 缺 gettext 的目标机回落英文 | 中文用户体验崩塌 | 纯 bash `messages.sh` 兜底表（6.1） |
| shellkit 升级引入行为变化 | unix_script 78 模块集体受影响 | shellkit 只加不改；unix_script 锁 vendor 版本；快照门禁 |
| Stage 3 批量迁移引入回归 | 单模块功能损坏 | 分批 + 每批快照零差异；模块级 status 输出对比 |
| 旧 CLI flag 一次性删除打断外部脚本 | 用户脚本/AI agent 报错 | CLI v2 同期更新 AGENTS.md/README/docs/bootstrap；发布说明列删除清单 |
| 两仓发布节奏耦合 | shellkit 未发布则 unix_script 不可用 | unix_script vendor 自带副本，不依赖 shellkit 仓库状态 |

**回滚**：每个阶段独立提交；unix_script 侧保留 `refactor/shellkit` 分支，Stage N 出问题即回退该阶段提交。

---

## 11. 已确认的决策

| 决策点 | 结论 |
|---|---|
| 集成方式 | vendor 进 unix_script 仓库（`vendor/shellkit/`），随仓库分发 |
| 重构范围 | lib 层全量换 shellkit + 78 个模块逐个迁移（分多轮） |
| CLI 兼容 | 允许重新设计；**直接切换到新子命令面，旧 flag 一次性删除**（无兼容期） |
| i18n | **全量转 gettext**：78 模块面向用户的文案全部 msgid 化 + `zh_CN` 译文 |
| 能力归属 | 两边都动：shellkit 抽出通用机制，unix_script 提供领域语义并使用 |
| 本轮范围 | Stage 1 = shellkit 补齐 10 处能力（i18n/os/svc/ver/status/registry/profile/http/run/str）+ unix_script lib 换壳（不碰 78 模块脚本、不改 CLI 形状） |

---

## 12. 待细化（进入对应阶段时展开）

- Stage 1 的 shellkit 新模块 API 细节（参数、返回码、测试用例矩阵）
- i18n msgid 抽取规则与 po 分段组织方式
- CLI v2 的完整命令矩阵与帮助文本
- Stage 3 的模块分批顺序与每批的验收清单
- 快照基线的具体采集范围与「有意变更」登记流程
