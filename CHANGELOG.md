# 更新日志

本文件记录 unix_script 项目的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)。

## [Unreleased]

### 新增
- **10 个新模块**（38 → 48）：nginx、caddy、certbot、redis、postgres、prometheus、grafana、gitea、ufw、restic
- **模块脚手架命令**：`./install.sh scaffold <name>` 一键生成新模块模板（含 .manifest、install.sh、README.md）
- **环境诊断命令**：`./install.sh doctor` 检查 Bash 版本、必要工具、包管理器、磁盘空间、网络连通性、sudo 权限
- **`--list-categories` 命令**：按分类列出所有模块
- **`--dry-run` 预览模式**：仅打印将执行的操作，不实际执行（`./install.sh --dry-run docker`）
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
