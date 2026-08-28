# 更新日志

本文件记录 unix_script 项目的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)。

## [Unreleased]

### 新增
- **磁盘健康诊断升级（sys-tools/disk）**：`disk smart` 从原样输出 smartctl 升级为逐项判读——无参数全盘概览与单盘详情均给出分级结论（✅健康/🟡注意/🔴危险/未知），ATA 判读重映射/待定/不可纠正扇区、NVMe 判读介质错误/备用空间/寿命耗用，机器模式输出 `STATE`/`EXTRA`，SMART 自动探测失败（SAT 层提示）时自动以 `-d ata` 重试；新增 `disk scan` 盘面坏块只读扫描（badblocks 不写盘，实时进度、耗时预估、坏块 LBA 清单与备份/换盘建议）

### 修复
- disk 模块两处 shellcheck 0.9 存量报错：`cmd_status` 局部变量与 lib/common.sh 数组同名触发 SC2178/SC2128（改名 miss_tools）；`_disk_format_device` 的 `A&&B||true` 写法触发 SC2015（改 if 形式，行为不变）

## [1.11.0] - 2026-08-28

### 新增
- **disk-usage top 深度下钻 + 交互模式**：`--depth` 一条命令看多层大目录，终端下智能进入交互（序号下钻/`u` 上层/`c` 改数量/`q` 退出），管道与 CI 自动退化为纯输出；`--min-size` 过滤出 M/G 级大条目。顺带修复：含空格路径显示截断、隐藏目录（`~/.cache` 等）漏统计、`sort -h` 跨平台兼容问题；大文件榜改为跟随 `top <路径>` 参数

## [1.10.0] - 2026-08-28

### 新增
- **磁盘管理工具箱（sys-tools/disk）**：列盘 / GPT 分区 / 格式化（ext4·xfs·vfat·exfat·ntfs）/ 挂载·卸载 / fstab 持久化（UUID + 写前备份 + `mount -a` 验证回滚）/ SMART 健康 / 擦除签名（wipefs）；「新盘一键上线」向导（分区→格式化→挂载→fstab 一步到位）；主菜单新增子菜单入口（系统工具 → 磁盘管理）。严格护栏：根盘/启动盘/EFI/swap 及其所在整盘、使用中设备硬拒绝；破坏性操作仅限交互终端且需手动输入完整设备名确认，无 `--yes` 绕过

### 修复
- **换源不彻底（Ubuntu 24.04+/Debian 13 deb822）**：`sys-setup mirror` 只重写 `/etc/apt/sources.list`，而新世代的发行版源实际在 `/etc/apt/sources.list.d/ubuntu.sources`（deb822），导致新旧源并存——同一批索引重复下载、`security.ubuntu.com` 官方源残留、`apt modernize-sources` 提示；现优先重写 deb822 主文件（含 `Signed-By`，security 套件走清华），并停用其余仍指向发行版归档的源文件（重命名为 `.bak.<时间戳>`，apt 自动忽略、可随时改回）；`status` 的镜像检测同步覆盖 `sources.list.d`（此前即使已换源也误报「默认源」）
- **--dry-run 假预览**：`UNIX_SCRIPT_DRY_RUN` 此前无任何模块消费（`dry_run_exec/dry_run_sudo` 零调用），预览模式会真实执行安装，且 `require_sudo` 在无 TTY 时直接报错退出；现 `require_sudo` 在 dry-run 下短路跳过授权，并以同名函数遮蔽 `sudo`（各模块 source common.sh 时自动生效），apt/systemd/写 /etc 等全部 root 操作降级为 `[dry-run]` 打印——无 TTY 环境也可安全预览。注意：少数非 sudo 的用户级操作（如克隆到家目录的工具安装）仍会实际执行，`--help` 已注明

## [1.9.0] - 2026-08-28

### 新增
- 交互菜单双轨重构：fzf 模糊搜索/TAB 多选/README 预览（`UXS_MENU=fzf|bash` 强制切换，无 fzf 自动降级）
- bash 分类两级菜单：状态图标、模块描述、`1,3,5-8` 多选、`/关键字` 过滤
- did-you-mean：未知模块名给出编辑距离建议，不再倾倒模块清单
- `.manifest` 新增 `DESC` 字段（描述单一数据源），`--list-modules` 追加描述列
- 安装状态并行批查 + TTL 跨进程缓存（`UXS_STATUS_CACHE_TTL` / `UXS_STATUS_JOBS`），全量查询 5.4s → ~2s、二次进入秒开
- bash/zsh 补全改为注册表驱动动态生成（新增模块自动进补全）

### 修复
- **子菜单入口分发崩溃**：菜单按 `manage_<HAS_SUBMENU>` 动态分发入口函数，但 sys-setup / dev-mirror / multi-net / process_manager_tool 四个模块的入口函数名与模块名不一致（下划线/缩写），菜单选中即在 `set -e` 下 `command not found` 整体退出；现入口函数名与模块名严格对齐，`menu_exec_actions` 增加 `declare -F` 兜底（缺失时明确提示而非崩溃），CI 增加全量 HAS_SUBMENU ↔ `manage_*` 一致性断言
- 敲错模块名静默失败：`set -e` 下别名未命中导致命令替换失败直接退出，「未知模块」错误从未输出；现输出错误 + did-you-mean 建议
- 弱网环境启动菜单长时间卡顿（GitHub API 请求无超时；现默认 connect 5s / max 10s，`UXS_CURL_TIMEOUT` 可覆盖）
- 补全文件硬编码清单落后注册表 4 个模块（certbot / code-lint / disk-usage / nat）

## [1.8.0] - 2026-08-15

### 新增
- **模块依赖图（阶段 E）**：manifest 新增 `REQUIRES` 字段；`lib/deps.sh` 提供 `resolve_deps`/`topo_sort_all` + 循环依赖检测；安装时自动先装缺失依赖（拓扑序）；`--no-deps`/`UNIX_SCRIPT_NO_DEPS=1` 跳过；`--list-modules` 对有依赖的模块追加 `requires:` 列。minikube 声明 `REQUIRES=docker`
- **配置复现 / profile（阶段 D）**：`lib/profile.sh` 提供 `export_profile`/`apply_profile`；`./install.sh export|apply [--force|--dry-run]` 导出/应用可 git 的纯文本 profile；manifest 新增 `EXPORTABLE` 字段；apply 透传 `UXS_CONFIG_<KEY>` 给模块 install。bun 为 pilot（`EXPORTABLE=registry` + `UXS_CONFIG_REGISTRY`）
- **健壮性地基**：全仓库启用 `set -euo pipefail`；`UXS_DEBUG=1` 透出库内静默 stderr；`lib/common.sh` 新增 `github_latest_tag`（jq 优先 + grep 回退）、`github_release_asset_url`、`verify_sha256`、`uxs_stderr`
- **CI 强制 nounset 门禁**：routing 阶段对每个模块的 status/help 在 `bash -u` 下重跑，防止未定义变量引用静默回退

### 变更
- **去特判化**：shutdown_timer / process_manager_tool 改为符合统一接口（install/uninstall/status/help），删除 install.sh、lib/status.sh、lib/menu.sh、lib/submenus.sh 中 7 处硬编码特判；`dispatch_module`/`dispatch_module_or_passthrough` 改用 `registry_entry_script`（修复原先硬编码 `install.sh` 的潜在 bug）
- **5 个模块补齐 uninstall**：multi-net（≈clear）、sys-cmd（只读 no-op）、docker-image（导出器 no-op）、sys-setup（删 drop-in + 列备份）、zsh_setup（框架卸载 + 清配置）
- **bootstrap 强制同步安全**：`reset --hard` 前对有本地改动的工作区创建 `git stash create` 备份并给出恢复命令，与 `do_self_update` 的 clean-tree 纪律对齐
- **架构检测**：新增 `ARCH_TYPE_LOWER`（统一小写）供新代码使用，`ARCH_TYPE` 保留兼容

### 修复
- **bash 3.2 多字节变量名 bug**：`$var` 紧邻全角字符（如 `）`）时 bash 3.2（macOS 默认）会把多字节吞进变量名导致值丢失；全仓库 121 处改用 `${var}` 花括号
- **wireguard status**：status 路径原先未定义 `$OS`（Linux 上误报 stopped）；修复中曾补调 `detect_os`，但该函数对 apk/pacman/zypper（Alpine/Arch/openSUSE）会 `exit 1` 反致 status 中止——最终改为直接取 `uname -s`，status 绝不因平台不支持而 exit 非零
- **disk-usage status**：裸调 `free`（极简容器无 procps）与 GNU `df --output/-x`（Alpine BusyBox df 不支持）均会中止；改为 `command_exists` 守卫降级 + GNU df 失败回退 plain `df -h`
- **zsh_setup 框架脚本路径**：frameworks/*.sh 的 `source .../lib/common.sh` 路径错误（多了一层 `../`），set -e 下会中止

## [1.7.2] - 2026-08-07

### 新增
- **status 输出契约（双轨）**：所有 52 个模块的 `status` 子命令支持环境变量 `UXS_STATUS_MODE=machine`，输出规范字段 `STATE=`/`VERSION=`/`EXTRA=`（无颜色无 emoji），人类模式默认输出与之前逐字一致
- **状态码有限集**：`not_installed` / `installed:running` / `installed:stopped` / `installed` / `configured` / `not_configured` / `n/a`
- **status 辅助函数**：`lib/common.sh` 新增 `emit_status`/`emit_version`/`emit_extra`/`uxs_is_machine_mode`，供模块作者统一输出
- **机器模式查询 API**：`lib/status.sh` 新增 `module_status_machine()`/`module_status_raw()`，供 status-json / 后续 health / export / apply 复用
- **CI status 契约校验**：`tests/ci_run.sh` routing 阶段新增 `check_status_contract`，校验每个模块 machine 模式首行是合法 `STATE=`（含 P5 特殊模块覆盖）
- **deskflow macOS 支持**：`sys-tools/deskflow` 增加 Homebrew cask 安装路径（`brew tap deskflow/tap` + `brew install --cask deskflow`），平台支持 Linux + macOS

### 变更
- **重写 `show_status_json`**：删除 7 层中文关键词 if-grep 猜测，改为读规范 `STATE=` 字段；输出格式向后兼容（`module:state[:version]`）
- **52 模块 status 迁移**：services/17 + essentials/6 + dev-tools/12 + ai-tools/3 + sys-tools/12 + P5/2 全部改用 `emit_status`，人类模式抽样字节比对一致

### 修复
- **`module_status_machine` P5 分支**：补齐 `UXS_STATUS_MODE=machine` 前缀（与 `module_status_raw` 对称），避免 P5 模块（shutdown_timer/process_manager_tool）返回空状态
- **deskflow SC2015**：`uninstall_deskflow_macos` 里 `A && B || C` 改为 `if` 结构，修复 almalinux-9（shellcheck 0.10.0）CI 静态检查

### 文档
- **AGENTS.md**：新增状态码表和 `UXS_STATUS_MODE` 机器可读 status 协议说明
- **README.md**：全面升级（核心特性、命令选项表格、52 模块按分类列表含别名/平台、AI agent 工作流指引）

## [1.7.1] - 2026-08-05

### 变更
- **目录结构重构**：52 个模块从根目录平铺迁移到分类子目录（`services/`、`essentials/`、`dev-tools/`、`ai-tools/`、`sys-tools/`），根目录从 ~70 项精简到 ~15 项
- **框架路径解析**：`registry.sh` 新增 `PHYSICAL_PATH` 字段和 `registry_path()` API，支持嵌套目录的模块发现与调度
- **杂项脚本归拢**：`check_issues.sh`、`setup_project_shortcuts.sh` 等移入 `scripts/`
- **删除 `npm-mirror` 兼容别名**：不再路由到 `dev-mirror`，直接使用 `./install.sh dev-mirror`
- **删除 `FEATURE_ENHANCEMENT_SUMMARY.md`**（历史文件，信息已在 CHANGELOG 中）
- **模块数更新**：51 → 52（code-lint 纳入 git 跟踪）

## [历史遗留] 曾误编号为 1.8.0（未发布）- 2026-08-05

> 注：该节原标为 `[1.8.0]`，但该版本号从未打 tag 发布（tag 序列为 …v1.6.2 → v1.6.3 → v1.6.4 → v1.7.0…），
> 且 v1.6.3/v1.6.4 在本文件中无独立条目。按内容（38→48 模块、scaffold、doctor 等）推断对应
> v1.6.3/v1.6.4 时期的变更，现重命名以免与真实发布的 [1.8.0]（2026-08-15）冲突。

### 新增
- **10 个新模块**（38 → 48）：nginx、caddy、certbot、redis、postgres、prometheus、grafana、gitea、ufw、restic
- **模块脚手架命令**：`./install.sh scaffold <name>` 一键生成新模块模板（含 .manifest、install.sh、README.md）
- **环境诊断命令**：`./install.sh doctor` 检查 Bash 版本、必要工具、包管理器、磁盘空间、网络连通性、sudo 权限
- **`--list-categories` 命令**：按分类列出所有模块
- **`--dry-run` 预览模式**：仅打印将执行的操作，不实际执行（`./install.sh --dry-run docker`）
- **`completions` 子命令**：`./install.sh completions` 一键安装 Tab 自动补全到 shell 配置
- **Bash / Zsh 自动补全**：`completions/uxs.bash` 和 `completions/uxs.zsh`，支持模块名和子命令补全
- **GitHub Issue 模板**：Bug 报告 + 功能建议模板
- **GitHub PR 模板**：含变更类型、测试矩阵、关联 Issue
- **`.shellcheckrc`**：项目级 shellcheck 配置（统一排除 SC2034/SC2317/SC2329）

### 变更
- **重构 `uninstall.sh` 为注册表驱动**：去掉硬编码模块列表，自动发现所有 .manifest 模块，新增模块无需手动修改卸载脚本

### 文档
- 补全 5 个模块的 README：ddns-go、k7s、node_exporter、wireguard、zsh_setup

## [1.6.2] - 2026-08-01

### 修复
- **bootstrap 无参数不再进交互菜单**：`curl|bash` 无参数时改为更新仓库 → 确保 uxs → 打印 `--status-json` 状态摘要 → 显示使用提示 → 退出。不再触发"检测到非交互环境"警告。

## [1.6.1] - 2026-08-01

### 新增
- **sys-cmd 模块**：系统诊断命令集（cpu/mem/port/ports/disk/du/net/top/logs/all），纯函数封装，自动适配 Linux（ss/netstat/ps/free）与 macOS（lsof/ps/vm_stat/sysctl）。
- **交互菜单版本信息**：菜单头部显示当前版本 + 后台检查远端版本，有更新时醒目提示。
- **菜单管理段 `c) 检查更新`**：显示版本对比，有更新时可一键 `do_self_update`。
- **bootstrap 自动安装 uxs**：`curl|bash` 无参数时自动安装全局命令 uxs 到 `~/.tools/bin`。

### 修复
- **bootstrap `set -u`**：去掉 `set -u`，修复 `curl|bash` 管道模式下偶发 `unbound variable` 报错。

## [1.6.0] - 2026-08-01

### 新增
- **deno 模块**：Deno 运行时（包装 deno.land/install.sh，macOS 优先 brew）
- **pnpm 模块**：Node.js 包管理器（包装 get.pnpm.io/install.sh，macOS 优先 brew）
- **go 模块**：Go 语言环境（官方二进制 tarball，macOS 优先 brew）
- **rust 模块**：Rust 语言环境（rustup 安装器，macOS 优先 brew install rustup）
- **pi 模块**：Pi AI 编程代理框架（pi.dev，多模型/可扩展）
- **dev-enhance 模块**：开发工具增强（Neovim+LazyVim / git 增强 delta diff 高亮 / tmux 配置+tpm）
- **modern-cli 模块**：现代 CLI 工具集（bat/eza/ripgrep/fd/fzf/zoxide/starship + shell 集成）
- **AI agent 友好**：`AGENTS.md`（AI agent 使用说明）+ `--list-modules`（TSV 机器可读模块清单）+ `--status-json`（key:value 状态）+ `NO_COLOR` 环境变量支持
- **模块子命令透传**：`install.sh bun mirror`、`install.sh clash start` 等
- **新服务器一键配置教程**：`docs/NEW_SERVER_GUIDE.md`
- **bun 国内镜像加速**：`bun mirror` / `bun unmirror` 子命令

### 变更
- **macOS brew 优先**：rust/go/node_exporter/dev-tui 在 macOS 上优先用 brew 安装（统一版本/服务/卸载管理）
- **清理 docs/superpowers**：移除无引用的设计笔记遗留
- **CI 排除 SC2317/SC2329**：status 函数间接调用导致的 shellcheck 误报

### 修复
- bootstrap.sh `old_ver` 初始化防御（curl|bash 管道模式偶发 unbound variable）
- bun status registry 解析改用 Parameter Expansion（跨平台兼容 macOS BSD sed）

## [1.5.1] - 2026-08-01

### 新增
- **`bun` 模块**：安装 Bun（JavaScript/TypeScript 运行时与工具链），包装官方脚本 `bun.sh/install`（macOS 优先 brew），用户态安装无需 sudo；接入主菜单开发环境段（选项 19）。
- **Bun 国内镜像加速**：`bun mirror` 一键配置淘宝 npmmirror（写入 `~/.bunfig.toml` + 清缓存），`unmirror` 还原官方源，`status` 显示当前 registry。跨平台实现（awk 重建 `[install]` 段，兼容 macOS BSD 与 Linux GNU sed）。

### 变更
- **4 个遗留模块统一为标准子命令接口**（`install/uninstall/status/help`）：node_exporter、ddns-go、zsh_setup、wireguard。卸载/状态逻辑从 `install.sh` 搬入各模块，删除 `install.sh` 中 178 行内联代码（8 个搬走的函数 + manage_wireguard 子菜单）；`ci_run.sh` 将这 4 个模块从 legacy_mods 移入 new_mods，至此全部 24 个模块统一走标准测试。
- **审计修复**：README 与 show_usage 模块名列表补齐 `docker-image`；CHANGELOG 按 Keep a Changelog 规范重组（版本严格降序）；ci_run.sh "9 模块"过时标签改为动态断言；minikube `print_*` 别名迁移为 common 的 `info/success/warn/error`（全库命名统一）。

### 修复
- **修复 `curl|bash` 无参数时菜单卡死/刷屏的 bug**：stdin 来自管道（非 TTY）时，`interactive_main` 的 `read` 收到 EOF 导致无限循环。现改为检测非 TTY 无参场景，优雅打印帮助+使用提示后退出 0，并引导用户「带参数运行」或「先 clone 再交互运行」。
- **`bootstrap.sh` 完善幂等与日常使用提示**：更新分支增加版本号对比（显示「已是最新 / 已更新 X→Y」）；重写「日常使用」提示，明确「首次与更新同一条 `curl|bash` 命令」+ 常用非交互参数速查。
- README 新增「日常使用（幂等）」小节。
- `install.sh` show_usage 模块名列表补齐 `dev-mirror`。

## [1.5.0] - 2026-07-31

### 新增
- **`docker-image` 模块**：从公网拉取 Docker 镜像并导出为 gzip 压缩 `.tar.gz`（离线分发/备份）；交互式逐步引导（镜像名→目录→文件名），支持批量循环、本地已有时询问、导出摘要（digest/大小/耗时）；接入主菜单（选项 27）。
- **`uxs` 全局命令**：`install.sh cli` 将脚本库安装为全局命令 `uxs`（位于 `~/.tools/bin`，自动配置 bash/zsh/fish 的 PATH），之后可在任意目录 `uxs docker-image` / `uxs --status` 等；`install.sh uninstall-cli` 卸载。

## [1.4.0] - 2026-07-31

### 新增
- **`dev-mirror` 模块**：开发换源加速统一入口，覆盖 npm（+ yarn/pnpm）、Go（GOPROXY）、Rust（cargo）、Python（pip）四大生态；每生态内置多个国内镜像（默认推荐：淘宝/goproxy.cn/清华/清华），支持交互选择、`install all default` 一键批量、自定义 URL；写用户级配置无需 sudo；接入主菜单（选项 15）、状态页、卸载菜单、非交互 CLI。

### 变更
- **合并并删除 `npm-mirror` 模块**：其能力已并入 `dev-mirror` 的 npm 分支。`install.sh npm-mirror` 别名保留以向后兼容（路由到 dev-mirror）。

### 修复
- 修复 CI ubuntu 静态检查（shellcheck 0.8.0）报错：`lib/common.sh` SC2002（useless cat）、`check_dependencies.sh` SC2086（未引用变量）。本地 0.11.0 不报，CI ubuntu 0.8.0 报，已用 docker 复现并验证修复。

## [1.3.1] - 2026-07-31

### 新增
- **一键安装引导脚本 `bootstrap.sh`**：无需手动 clone，`curl -fsSL .../bootstrap.sh | bash` 一行命令即可下载并启动安装菜单；自动克隆到 `~/.local/share/unix_script`，再次运行自动 `git pull` 更新；支持透传参数（`bash -s -- docker`）。
- **`npm-mirror` 模块**：npm/yarn/pnpm 换源加速（默认淘宝 npmmirror），支持腾讯/华为/官方/自定义源，一键切换或还原；接入主菜单（选项 15）、状态页、卸载菜单。

### 变更
- README 与代码中的仓库克隆地址统一改为 HTTPS（原 SSH 地址外部用户无法 clone）。
- `do_self_update` 的重新克隆提示改为 HTTPS 地址。

### 修复
- routing 测试 `install.sh update` 断言不再依赖工作区是否 clean（改用 `</dev/null` 取消 + 对比 HEAD 前后），根治间歇性误报。

## [1.3.0] - 2026-07-31

### 新增
- **远端版本监测与更新提示**：
  - `install.sh` 启动时自动检查 GitHub 最新 release，有新版本在顶部提示（仅提示，不自动改动）。
  - 新增 `check-update` 子命令：主动检查远端版本。
  - 新增 `update` 子命令：安全检查（git 仓库 / origin / 干净工作区 / 非 detached）+ 确认后 `git pull`。
  - 新增 `lib/common.sh` 公共函数：`get_local_version` / `version_gt` / `check_for_update` / `print_update_hint` / `do_self_update`。
  - 环境变量 `UNIX_SCRIPT_NO_UPDATE_CHECK=1` 可关闭启动自动检查。

## [1.2.0] - 2026-07-31

### 新增（吸纳自 origin/main 的独立模块）
- **`minikube/`**：本地 Kubernetes 开发环境（kubectl + minikube）。
  - 纳入 install / check / smoke_test / README 全部文件。
  - 统一为 `source lib/common.sh`（适配别名保留内部 `print_*` 调用），新增 install/uninstall/status/help 子命令分发。
  - 支持 `--yes` 非交互与 `--driver` 驱动选择。
- **`deskflow/`**：键鼠共享（Flatpak，仅 Linux 图形环境）。重写为 common 风格 + 子命令分发 + README。

### 集成
- 主菜单接入 minikube（开发环境，选项 8）与 deskflow（系统工具，选项 11），菜单编号重排。
- 状态页、卸载菜单、`dispatch_module`、`--list`、CI routing 测试同步更新（覆盖 11 个模块）。

### 合并 origin/main（冲突解决）
- 与 origin/main 的扁平化重构（根脚本、`linux/`+`macos/` 双目录、`common/`、迁移文档）整合。
- **以本分支为基底**：保留子目录结构与 `lib/common.sh`，全部冲突（install.sh 内容冲突、7 个 modify/delete、5 个 add/add）按本分支版本解决。
- 远端扁平化文件（`main.sh`/`pm.sh`/`linux/*`/`macos/*`/`common/*`/`MIGRATION_*` 等 42 个）不纳入本分支。
- Docker 镜像换源采用本分支的 `registry`/`mirror` 子命令（不采用远端的 `docker/change_registry.sh`）。

## [1.1.0] - 2026-07-30

### 新增
- **公共函数库** `lib/common.sh`：统一颜色、打印函数（`info/success/warn/error/header/menu`）、平台/架构检测、包管理器检测、权限检查、依赖检查、IP/版本号获取、服务管理封装（systemd/launchd）。
- **新服务模块**：
  - `tailscale/`：基于官方安装脚本封装，支持 Linux（apt/yum/dnf）与 macOS（Homebrew）。
  - `docker/`：Linux 用 get.docker.com 一键安装，可选加入 docker 组；macOS 引导安装 Docker Desktop。
  - `fail2ban/`：仅 Linux，安装并写入保护 sshd 的默认 `jail.local`。
- **一键卸载入口** `uninstall.sh`：支持逐项交互、`--all` 全量卸载、单模块卸载。
- **文档**：`VERSION`、`CHANGELOG.md`、`CONTRIBUTING.md`。
- **`.gitignore`**：忽略 `.DS_Store`、备份文件、`.tools/`、临时下载产物等。

### 变更
- 重写 `check_issues.sh`：优先使用系统 shellcheck 做真实静态检查（与 CI 一致），并对所有脚本做 `bash -n` 语法检查；shellcheck 缺失时回退到 grep 启发式并给出安装指引。
- 重构 `install.sh`（主菜单）：
  - 接入 3 个新模块，菜单编号改为连续（1-9）。
  - 新增非交互命令行：`--help`、`--version`、`--status`、`--list`、`<模块名>` 直接安装。
  - 修复 `manage_process_tool` 用递归改为 `while` 循环，并在每轮重新检测安装状态。
  - 子目录脚本调用改用子 shell `( cd ... && bash ... )`，避免 `set -e` 下工作目录被污染。
  - 卸载菜单新增 Tailscale/Docker/Fail2ban 项，并修复 Zsh 卸载项实际调用 `uninstall_zsh_omz`（此前为死代码）。
- 现有模块（`node_exporter`、`ddns-go`、`wireguard`、`zsh_setup`、`shutdown_timer`）改为 `source lib/common.sh`，统一打印函数命名与颜色码（修复 zsh_setup 中颜色码缺失 ESC 转义的缺陷）。

### 修复
- `install.sh` 主菜单从选项 6 跳到 8 的编号空缺（无选项 7）。
- `install.sh` 中 `uninstall_zsh_omz()` 函数从未被调用的死代码。
- `zsh_setup/install.sh` 颜色码 `[0;31m` 缺少 `\033` 转义前缀。

## [1.0.0] - 2025
- 初始版本：Node Exporter、DDNS-GO、WireGuard、Zsh & Oh My Zsh、自动关机、进程管理工具。
- 统一安装菜单 `install.sh`、ShellCheck CI、快捷访问脚本。
