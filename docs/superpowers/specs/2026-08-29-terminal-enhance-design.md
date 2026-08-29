# 设计：终端配置增强批次——zsh_setup 修复 + modern-cli 扩展 + atuin/nerd-font/terminal 新模块

**日期**: 2026-08-29
**状态**: 待实现
**前置**: v1.14.0 已发布；无未合入依赖
**范围**: 1 个现存 bug 修复（zsh_setup 非交互入口）、1 个模块扩展（modern-cli +tldr/direnv）、3 个新模块（atuin、nerd-font、terminal 编排）、阶段 D 接入

---

## 背景

用户诉求："增加 oh-my-zsh 类似的终端配置增强"。摸底发现该领域仓库已覆盖大半：

- `dev-tools/zsh_setup`：Zsh + 4 框架（oh-my-zsh/prezto/zinit/sheldon）+ 插件/主题/配置管理
- `dev-tools/modern-cli`：bat/eza/ripgrep/fd/fzf/zoxide/starship 一键装 + shell 集成

真正缺口与现存问题（本次动机）：

1. **现存 bug**：`zsh_setup/.manifest` 声明 `DEFAULT_ACTION=install`，但模块 main() 无 `install` 分支（`${1:-help}`）。框架把 `install` 透传给模块后命中 `*` 报"未知命令: install"退出 1——`./install.sh zsh_setup` 非交互必失败。
2. **阶段 D 空白**：两模块均不读 `UXS_CONFIG_*`、不声明 `EXPORTABLE`，profile 复现无法覆盖终端配置。
3. **工具缺口**：atuin（SQLite shell 历史）、tealdeer/tldr（命令例子速查）、direnv（目录级环境变量）。
4. **配套缺口**：p10k/starship/eza --icons 需要 Nerd Font，无任何模块管理字体，图标乱码无人管。

用户已确认方向 A（补缺口小模块 + 一键编排）；归属采用推荐拆分：atuin 独立（有 sync 子命令与状态语义），tldr/direnv 并入 modern-cli（纯二进制 + shell 集成，性质同 bat/eza）。

## 目标

- `./install.sh zsh_setup` 非交互可用；框架/主题可用 `UXS_CONFIG_FRAMEWORK`/`UXS_CONFIG_THEME` 调整
- `zsh_setup` 声明 `EXPORTABLE`，profile 可复现终端配置
- modern-cli 增至 9 工具（+tealdeer、+direnv），沿用一键全装模式
- 新增 `dev-tools/atuin`、`dev-tools/nerd-font`、`dev-tools/terminal`，全部过机器模式 status 契约
- `./install.sh terminal` 一条命令在新机器配好整套终端

## 非目标

- oh-my-posh（与 starship 重叠）、thefuck（Python 慢、口碑下滑）、zellij/tmux（偏离配置增强主题）
- modern-cli 的 `--with/--only` 选择安装机制（保持一键全装，YAGNI）
- atuin 账号自动注册（同步开启时仅提示用户自行 `atuin register`）
- 不动 `detect_distro`/`detect_desktop`，CI routing 无感

## 方案

### ① zsh_setup 补 `install` 子命令（前置修复，批次 T1）

main() 新增 `install` 分支，非交互默认安装：

1. 确保 zsh 本体：`pkg_installed zsh || pkg_install zsh`（macOS brew；已装幂等跳过。若 `framework.sh` 已有等价逻辑则复用）
2. `framework_install "${UXS_CONFIG_FRAMEWORK:-oh-my-zsh}"`
3. 基础插件 4 件套：zsh-autosuggestions、zsh-syntax-highlighting、zsh-completions、zsh-history-substring-search（走既有 `plugin_add`，按框架适配器分发；已装跳过）
4. 主题：`UXS_CONFIG_THEME` 为空或 robbyrussell → 不动作（框架默认）；`p10k` → 调既有 `theme_install_p10k`

`.manifest` 增加 `EXPORTABLE=framework,theme`。machine 模式 status 已输出 `EXTRA=framework=...`/`EXTRA=theme=...`，key 天然对齐，export 抓取即生效。

### ② modern-cli 扩展：+tealdeer、+direnv（批次 T2）

- 工具清单与映射表各加两行：tealdeer（`tldr`，替代啃 man）、direnv（进目录自动加载 .envrc）
- 安装：brew/发行版包管理器；tealdeer 缺包时回退 GitHub 预编译二进制（沿用 starship/eza 回退模式）
- shell 集成：direnv 写 `eval "$(direnv hook zsh)"`（bash 同理）入 rc，沿用现有带标记块；tealdeer 无 rc 集成，装后执行 `tldr --update` 建缓存
- `.manifest` DESC 更新为含 tldr/direnv 的清单

### ③ 新模块 `dev-tools/atuin`（批次 T3）

SQLite 化 shell 历史：全量模糊搜索、多机端到端加密同步。

- install：brew/包管理器 → 回退官方脚本 `curl -fsSL https://setup.atuin.sh | sh`；读 `UXS_CONFIG_SYNC`（默认 `0` 纯本地）；rc 写入 `eval "$(atuin init zsh)"`（按目标 rc 对应 shell 生成 zsh/bash 两版），带标记；首次安装执行 `atuin import-auto` 迁移旧历史；`SYNC=1` 时输出 `atuin register` 提示（不代注册）
- 子命令：`install` / `status` / `sync`（显式 `atuin sync`，SYNC=0 时提示未开启）/ `uninstall` / `help`
- status：`STATE=installed|not_installed`，`EXTRA=sync=on|off`；`.manifest` 声明 `EXPORTABLE=sync`

### ④ 新模块 `dev-tools/nerd-font`（批次 T2）

**核心约束：字体由终端模拟器（客户端）渲染**，远程机上安装对 SSH 会话无效。

- 默认装 JetBrainsMono Nerd Font；`UXS_CONFIG_FONTS`（逗号分隔，如 `JetBrainsMono,FiraCode`）覆盖
- macOS：`brew install --cask font-jetbrains-mono-nerd-font`（内部维护 字体名→cask名 映射表：JetBrainsMono/FiraCode/Hack/CascadiaCode）
- Linux：GitHub releases 下载对应 tar.xz → `~/.local/share/fonts/NerdFonts/<Name>/` → `fc-cache -f`；无 fontconfig 或 `IS_DESKTOP=0` 时 install 直接提示"远程/无头机无需安装，请在本地终端机执行"并退出 0
- 子命令：`install` / `list`（映射表内可用字体）/ `uninstall` / `status` / `help`
- status：`STATE` + `EXTRA=fonts=<已装清单>`；`.manifest` 声明 `EXPORTABLE=fonts`

### ⑤ 新模块 `dev-tools/terminal`（批次 T3，编排）

一键全家桶：`./install.sh terminal`。

- 编排顺序（每步先查子模块 status，已就绪幂等跳过）：
  1. zsh 本体 → 2. `zsh_setup install` → 3. `modern-cli install` → 4. `nerd-font install` → 5. `atuin install`
- `UXS_CONFIG_EXCLUDE`（逗号分隔环节名，如 `atuin,nerd-font`）裁剪环节
- 子模块脚本相对路径 `../<模块>/install.sh` 调用；`UXS_CONFIG_*` 环境变量经进程继承天然透传，无需显式转发
- **不用阶段 E REQUIRES**：REQUIRES 自动装依赖不传偏好（框架选择/字体清单），编排必须带参调用，故自编排
- status：人类模式逐环节一行表；机器模式全就绪 `STATE=installed`，缺环节 `STATE=not_installed` + `EXTRA=missing=<环节名,...>`
- **terminal 不声明 EXPORTABLE**：各子模块（zsh_setup/nerd-font/atuin）各自声明并输出自己的键，profile 按行逐模块注入 `UXS_CONFIG_*`，无同键多行冲突，且单独使用某子模块（不装 terminal）时同样可复现。`UXS_CONFIG_EXCLUDE` 属一次性编排偏好，不入 profile

## 错误处理

- 所有 rc 写入沿用带标记块约定，uninstall 按标记清理
- 网络安装均走 回退链（包管理器 → 官方脚本/预编译二进制），失败报错退出非 0
- 全部安装步骤幂等：已装跳过，`terminal` 重跑安全
- `status` 子命令始终退出 0（探测契约）

## 测试（tests/unit_terminal_enhance.sh）

- ① `./install.sh zsh_setup`（桩 HOME/PATH）不再报"未知命令: install"，机器模式 status 输出 `STATE=` 首行
- ② modern-cli 工具清单含 tldr/direnv（manifest DESC 与安装函数一致性）
- ③④⑤ 三模块：`.manifest` 注册后 `--list-modules` 可见；桩环境机器模式 status 输出 `STATE=`；`terminal` 的 `UXS_CONFIG_EXCLUDE` 裁剪逻辑（dry-run 桩）；全部过 shellcheck
- 新模块 install 逻辑遵循现有模块的 dry-run 约定（原生兼容 `--dry-run`）

## 实现批次

| 批次 | 内容 | 依赖 |
|------|------|------|
| T1 | ① zsh_setup install 子命令 + EXPORTABLE | 无 |
| T2 | ② modern-cli +tldr/direnv；④ nerd-font 模块 | 无 |
| T3 | ③ atuin 模块；⑤ terminal 编排 | T1（依赖 zsh_setup install 子命令） |

T1/T2 可并行，T3 最后。发版建议单版本（v1.15.0）统一带出，README 支持矩阵由 CI 自动刷新。
