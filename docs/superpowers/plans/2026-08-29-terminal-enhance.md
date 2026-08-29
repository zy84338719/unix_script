# 终端配置增强（terminal-enhance）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 spec `docs/superpowers/specs/2026-08-29-terminal-enhance-design.md`——修复 zsh_setup 非交互入口、modern-cli 扩展 tldr/direnv、新增 atuin/nerd-font/terminal 三模块，让 `./install.sh terminal` 一条命令配好整套终端。

**Architecture:** 沿用库既有模式：每模块一个目录（`.manifest` + `install.sh` + `README.md`），`lib/common.sh` 提供 `emit_status/emit_extra/pkg_install/command_exists/github_latest_tag` 等 helper；terminal 为编排模块（相对路径调用同级子模块脚本，`UXS_CONFIG_*` 经进程继承透传）。spec 明确：EXPORTABLE 由各子模块自治声明，terminal 不声明。

**Tech Stack:** Bash（`set -euo pipefail`）、`lib/common.sh` helper、bash 单测（`tests/unit_*.sh` 的 `t_eq/t_true` + 桩 PATH 注入假二进制）。

## Global Constraints

- 模块入口模式：`main() { local action="${1:-install}" ... }`，子命令 `install|uninstall|status|help`
- status 机器模式：`UXS_STATUS_MODE=machine` 时经 `emit_status`/`emit_extra` 输出 `STATE=`/`EXTRA=`，status 始终退出 0
- rc 写入必须带标记块 `# >>> unix_script <模块名> >>>` / `# <<< ... <<<`，幂等跳过，uninstall 按标记清理
- 网络安装回退链：包管理器 → 官方脚本/预编译二进制；失败 warn 不中断其他工具
- 新模块 `.manifest` 必含 `LABEL/CATEGORY/DESC/DEFAULT_ACTION=install`；EXPORTABLE：zsh_setup=`framework,theme`、nerd-font=`fonts`、atuin=`sync`，terminal **无**
- UXS_CONFIG 键名全文一致：`FRAMEWORK`/`THEME`（zsh_setup）、`FONTS`（nerd-font）、`SYNC`（atuin）、`EXCLUDE`（terminal）
- 基础插件 4 件套：zsh-autosuggestions、zsh-syntax-highlighting、zsh-completions、zsh-history-substring-search
- 验证命令：`./tests/ci_run.sh --phase static`（bash -n + shellcheck）每任务必跑
- 工作分支：`feat/panel-modules`（spec f8b2739 已在此分支）；平台：macOS + Linux 双端

---

### Task 1: zsh_setup 补 `install` 子命令 + EXPORTABLE（批次 T1）

**Files:**
- Modify: `dev-tools/zsh_setup/install.sh`（main() 加 `install` 分支；新增 `install_zsh_setup_default()` 函数）
- Modify: `dev-tools/zsh_setup/.manifest`（追加 `EXPORTABLE=framework,theme`）
- Modify: `dev-tools/zsh_setup/README.md`（install 子命令文档）
- Test: `tests/unit_terminal_enhance.sh`（本任务创建，骨架 + 本任务用例）

**Interfaces:**
- Consumes: 既有 `framework_install <name>`（lib/framework.sh:25）、`plugin_add <name>`（lib/plugins.sh:53）、`theme_install_p10k`（lib/themes.sh:104）、`emit_status/emit_extra`（lib/common.sh）
- Produces: `bash dev-tools/zsh_setup/install.sh install` 非交互默认安装入口——Task 5（terminal 编排）以此调用。机器模式 status 输出 `EXTRA=framework=...`/`EXTRA=theme=...` 已存在，无需改动。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit_terminal_enhance.sh`（沿用 unit_usability.sh 的 t_eq/t_true 骨架）：

```bash
#!/usr/bin/env bash
#
# tests/unit_terminal_enhance.sh — 终端配置增强批次 单测
# 覆盖：zsh_setup install 子命令 / modern-cli 扩展 / atuin / nerd-font / terminal 编排
# 独立运行：bash tests/unit_terminal_enhance.sh（退出码 0=全过）
# 也被 tests/ci_run.sh 调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

t_true() {
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1"
    fi
}

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
set +e +o pipefail

# ---------- ① zsh_setup install 子命令 ----------
ZSH_SETUP_SH="$REPO_DIR/dev-tools/zsh_setup/install.sh"

# 桩 PATH：假 zsh 让 status 走到框架检测；install 分支不报"未知命令"
FAKE=$(mktemp -d)
printf '#!/bin/sh\necho "zsh 5.9 (x86_64)"\n' > "$FAKE/zsh"
chmod +x "$FAKE/zsh"

out=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" UXS_STATUS_MODE=machine bash "$ZSH_SETUP_SH" status </dev/null 2>/dev/null)
t_eq "zsh_setup: status 机器模式输出 STATE=" "1" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1 | wc -l | tr -d ' ')"

# install 子命令存在：桩 curl 失败的场景下，错误不应是"未知命令: install"
mkdir -p "$FAKE/home"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/curl"; chmod +x "$FAKE/curl"
err=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" bash "$ZSH_SETUP_SH" install </dev/null 2>&1 || true)
t_true "zsh_setup: install 不再报未知命令" "! printf '%s' \"\$err\" | grep -q '未知命令'"

# manifest 契约
grep -q '^EXPORTABLE=framework,theme$' "$REPO_DIR/dev-tools/zsh_setup/.manifest"
t_true "zsh_setup: manifest 声明 EXPORTABLE=framework,theme" "$?"

echo
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_terminal_enhance.sh`
Expected: FAIL（install 分支不存在 → "未知命令: install"；EXPORTABLE 缺失）

- [ ] **Step 3: 实现**

`dev-tools/zsh_setup/install.sh`：

a) main() 的 case 中、`framework)` 分支前加：

```bash
        install)
            install_zsh_setup_default
            ;;
```

b) main() 函数定义之前新增：

```bash
# 非交互默认安装（DEFAULT_ACTION=install 的实现）：
# zsh 本体 → 框架(UXS_CONFIG_FRAMEWORK, 默认 oh-my-zsh) → 基础插件 4 件套(仅 oh-my-zsh)
# → 主题(UXS_CONFIG_THEME, 默认随框架; p10k 走 theme_install_p10k)
install_zsh_setup_default() {
    local framework="${UXS_CONFIG_FRAMEWORK:-oh-my-zsh}"
    local theme="${UXS_CONFIG_THEME:-}"

    if ! command_exists zsh; then
        info "安装 zsh 本体..."
        if ! pkg_install zsh; then
            error "zsh 本体安装失败（请手动安装 zsh 后重试）"
            return 1
        fi
    fi

    framework_install "$framework"

    # 基础插件：默认框架 oh-my-zsh 提供幂等的目录判断；
    # 其他框架（prezto/zinit/sheldon）插件目录约定各异，提示用户用 plugin add 自行管理
    if [[ "$framework" == "oh-my-zsh" ]]; then
        local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        local p
        for p in zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search; do
            if [[ -d "$custom_dir/plugins/$p" ]]; then
                info "插件已存在: $p"
            else
                plugin_add "$p" || warn "插件安装失败: $p（可稍后 plugin add $p 重试）"
            fi
        done
    else
        info "框架 $framework 的基础插件请用: $0 plugin add <name> 自行添加"
    fi

    case "$theme" in
        ""|robbyrussell) : ;;                 # 框架默认主题，不动作
        p10k|powerlevel10k) theme_install_p10k ;;
        *) theme_set "$theme" ;;
    esac

    success "🎉 zsh_setup 默认安装完成（框架: $framework）"
    info "新开终端或执行 exec zsh 生效"
}
```

`dev-tools/zsh_setup/.manifest` 追加一行：

```
EXPORTABLE=framework,theme
```

README.md 的「子命令」表格加一行 `install`（非交互默认安装，`UXS_CONFIG_FRAMEWORK/THEME` 可调）。

- [ ] **Step 4: 跑测试确认通过 + 静态检查**

Run: `bash tests/unit_terminal_enhance.sh && ./tests/ci_run.sh --phase static`
Expected: 全 PASS；static 无新增告警

- [ ] **Step 5: Commit**

```bash
git add dev-tools/zsh_setup tests/unit_terminal_enhance.sh
git commit -m "feat(zsh_setup): 补 install 非交互默认入口（修 DEFAULT_ACTION 不一致）+ EXPORTABLE"
```

---

### Task 2: modern-cli 扩展 +tealdeer/+direnv（批次 T2）

**Files:**
- Modify: `dev-tools/modern-cli/install.sh`（TOOLS 数组、pkg_name_for、回退函数、shell 集成 extras 块、status、usage、头部注释）
- Modify: `dev-tools/modern-cli/.manifest`（DESC 更新）
- Modify: `dev-tools/modern-cli/README.md`（工具映射表 +2 行）
- Test: `tests/unit_terminal_enhance.sh`（追加用例）

**Interfaces:**
- Consumes: `github_latest_tag <owner/repo>`（lib/common.sh，供 tealdeer 回退取版本）
- Produces: 状态机 `EXTRA=missing=` 里含 tldr/direnv；extras 标记块 `# >>> unix_script modern-cli extras >>>`——uninstall 说明引用它

- [ ] **Step 1: 写失败测试**

追加到 `tests/unit_terminal_enhance.sh`（在 zsh_setup 段之后）：

```bash
# ---------- ② modern-cli 扩展 ----------
MODERN_SH="$REPO_DIR/dev-tools/modern-cli/install.sh"
grep -q 'tealdeer' "$MODERN_SH" && grep -q 'direnv' "$MODERN_SH"
t_true "modern-cli: 安装脚本含 tealdeer/direnv" "$?"
grep -q 'tldr direnv' "$MODERN_SH"
t_true "modern-cli: status 检查含 tldr/direnv" "$?"
grep -q 'modern-cli extras' "$MODERN_SH"
t_true "modern-cli: 存在 extras 标记块（向后兼容老 rc）" "$?"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_terminal_enhance.sh`
Expected: 本段 3 条 FAIL

- [ ] **Step 3: 实现** `dev-tools/modern-cli/install.sh`

a) 头部工具映射注释与 `TOOLS` 数组：

```bash
TOOLS=(bat eza ripgrep fd-find fzf zoxide starship tealdeer direnv)
```

b) `pkg_name_for()` 加分支（apt 系老发行版 tealdeer 缺包，交由回退函数）：

```bash
        tealdeer)
            echo "tealdeer"
            ;;
```

c) install_modern_cli() 的 macOS 分支：

```bash
        brew install bat eza ripgrep fd fzf zoxide starship tealdeer direnv
```

d) Linux 分支的回退 else 链中新增（放 eza 分支之后）：

```bash
                elif [[ "$tool" == "tealdeer" ]] && ! command_exists tldr; then
                    if install_tealdeer_from_release; then
                        success "  ✅ tealdeer (官方二进制)"
                    else
                        warn "  ⚠️ tealdeer 安装失败（可 cargo install tealdeer）"
                    fi
```

e) 新增函数（放 pkg_name_for 之后；信任模型说明同 starship 分支——HTTPS 官方 release，展示版本可审计）：

```bash
# tealdeer 官方预编译二进制回退（musl 静态链接，glibc/musl 通用）。
# 资产名以 GitHub release 实际清单为准：tealdeer-linux-<arch>-musl.tar.gz
install_tealdeer_from_release() {
    local ver arch url tmp
    ver=$(github_latest_tag "tealdeer-rs/tealdeer" 2>/dev/null) || return 1
    case "$(uname -m)" in
        x86_64)          arch="x86_64" ;;
        aarch64|arm64)   arch="aarch64" ;;
        *) warn "tealdeer: 架构 $(uname -m) 无预编译包"; return 1 ;;
    esac
    url="https://github.com/tealdeer-rs/tealdeer/releases/download/${ver}/tealdeer-linux-${arch}-musl.tar.gz"
    tmp=$(mktemp -d)
    if curl -fsSL "$url" | tar -xz -C "$tmp" 2>/dev/null && [[ -f "$tmp/tealdeer" ]]; then
        local sudo_prefix=""
        [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
        $sudo_prefix install -m 755 "$tmp/tealdeer" /usr/local/bin/tldr
    else
        return 1
    fi
}
```

f) install_modern_cli() 末尾（configure_shell_integration 调用前后）加缓存更新：

```bash
    # tealdeer 缓存（首次使用前必须更新）
    if command_exists tldr; then
        tldr --update >/dev/null 2>&1 && info "tealdeer 缓存已更新" || warn "tealdeer 缓存更新失败（可稍后 tldr --update）"
    fi
```

g) `configure_shell_integration()` 中新增独立的 extras 块（放在现有块追加逻辑之后；老用户 rc 已有原标记块，原块幂等跳过不会包含新行，故拆新块）：

```bash
    # extras 块：tldr/direnv（新增于 v1.15.0，独立标记块保证老 rc 也能补上）
    local emark="# >>> unix_script modern-cli extras >>>"
    local eendmark="# <<< unix_script modern-cli extras <<<"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -q "$emark" "$rc" 2>/dev/null; then
            continue
        fi
        {
            echo ""
            echo "$emark"
            echo "# direnv（进目录自动加载 .envrc）"
            echo "command -v direnv >/dev/null 2>&1 && eval \"\$(direnv hook \$(basename \$SHELL))\""
            echo "$eendmark"
        } >> "$rc"
        info "已为 $(basename "$rc") 添加 direnv 集成"
    done
```

h) `status_modern_cli()` 检查列表改为含新命令：

```bash
    for t in bat eza rg fd fzf zoxide starship tldr direnv; do
```

i) uninstall 提示、usage 文本加 tealdeer/direnv；头部注释映射表加 `tealdeer → tldr（命令例子速查）`、`direnv → 目录级环境变量`。

`.manifest` DESC 改为：`DESC=bat/eza/ripgrep/fd/fzf/zoxide/starship/tldr/direnv`。README 工具映射表加两行。

- [ ] **Step 4: 测试 + 静态检查通过**

Run: `bash tests/unit_terminal_enhance.sh && ./tests/ci_run.sh --phase static`
Expected: 全 PASS

- [ ] **Step 5: Commit**

```bash
git add dev-tools/modern-cli tests/unit_terminal_enhance.sh
git commit -m "feat(modern-cli): +tealdeer(tldr)/+direnv，extras 独立标记块兼容老 rc"
```

---

### Task 3: 新模块 dev-tools/nerd-font（批次 T2）

**Files:**
- Create: `dev-tools/nerd-font/.manifest`、`dev-tools/nerd-font/install.sh`、`dev-tools/nerd-font/README.md`
- Test: `tests/unit_terminal_enhance.sh`（追加用例）

**Interfaces:**
- Consumes: `github_latest_tag`、`detect_desktop`（IS_DESKTOP）、`brew`（macOS）
- Produces: `bash dev-tools/nerd-font/install.sh install`；status 机器模式 `STATE=` + `EXTRA=fonts=<csv>`；`UXS_CONFIG_FONTS` 逗号分隔字体名（JetBrainsMono/FiraCode/Hack/CascadiaCode）——Task 5 编排调用

- [ ] **Step 1: 写失败测试**（追加）

```bash
# ---------- ④ nerd-font ----------
NF_MANIFEST="$REPO_DIR/dev-tools/nerd-font/.manifest"
NF_SH="$REPO_DIR/dev-tools/nerd-font/install.sh"
[[ -f "$NF_MANIFEST" && -x "$NF_SH" ]]
t_true "nerd-font: 模块文件存在且可执行" "$?"
grep -q '^EXPORTABLE=fonts$' "$NF_MANIFEST"
t_true "nerd-font: manifest EXPORTABLE=fonts" "$?"
bash -n "$NF_SH"
t_true "nerd-font: 语法通过" "$?"
```

- [ ] **Step 2: 跑测试确认失败**（模块不存在）

- [ ] **Step 3: 实现**

`.manifest`：

```
LABEL=Nerd Font
CATEGORY=开发环境
DEFAULT_ACTION=install
EXPORTABLE=fonts
DESC=终端图标字体（p10k/starship/eza 图标依赖）
NEXT_STEPS=SSH 场景字体装在本地终端机:./install.sh nerd-font
```

`install.sh` 完整内容：

```bash
#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/nerd-font/install.sh
# Nerd Font 图标字体安装器。字体由终端模拟器（客户端）渲染：
#   macOS  → brew cask 装本机（SSH 服务端装了也没用，但本机 mac 可用）
#   Linux  → ~/.local/share/fonts（仅本机桌面会话有意义）
#   SSH 远程/无头机 → install 直接提示并退出 0
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 字体名 → macOS cask 名 映射表（新增字体在此登记）
FONT_CASKS=(JetBrainsMono:font-jetbrains-mono-nerd-font FiraCode:font-fira-code-nerd-font Hack:font-hack-nerd-font CascadiaCode:font-cascadia-code-nerd-font)

cask_for() {
    local f
    for f in "${FONT_CASKS[@]}"; do
        [[ "${f%%:*}" == "$1" ]] && { echo "${f#*:}"; return 0; }
    done
    return 1
}

normalize_fonts() {
    local raw="${UXS_CONFIG_FONTS:-JetBrainsMono}"
    echo "$raw" | tr ',' '\n' | sed 's/ //g' | grep -v '^$'
}

install_nerd_font() {
    detect_os
    local fonts missing=() f
    fonts=$(normalize_fonts)
    for f in $fonts; do
        cask_for "$f" >/dev/null || missing+=("$f")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "未登记的字体: ${missing[*]}（可用: $(list_names)）"
        return 1
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        command_exists brew || { error "macOS 需要 Homebrew"; return 1; }
        for f in $fonts; do
            local cask; cask=$(cask_for "$f")
            if brew list --cask "$cask" >/dev/null 2>&1; then
                info "已安装: $f"
            else
                brew install --cask "$cask" && success "✅ $f" || warn "⚠️ $f 安装失败"
            fi
        done
    else
        # Linux：仅本机桌面会话有意义
        if ! command_exists fc-cache || [[ "${IS_DESKTOP:-0}" != "1" ]]; then
            detect_desktop
        fi
        if [[ "${IS_DESKTOP:-0}" != "1" ]] || ! command_exists fc-cache; then
            info "当前机器是远程/无头环境——字体由你本地终端机渲染，此处无需安装。"
            info "请在本地终端机执行: ./install.sh nerd-font"
            return 0
        fi
        local ver
        ver=$(github_latest_tag "ryanoasis/nerd-fonts" 2>/dev/null) || { error "无法获取 nerd-fonts 版本"; return 1; }
        for f in $fonts; do
            local dest="$HOME/.local/share/fonts/NerdFonts/$f"
            if [[ -d "$dest" ]] && ls "$dest"/*.ttf >/dev/null 2>&1; then
                info "已安装: $f"; continue
            fi
            local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${ver}/${f}.tar.xz"
            mkdir -p "$dest"
            if curl -fsSL "$url" | tar -xJ -C "$dest" 2>/dev/null; then
                success "✅ $f ($ver)"
            else
                warn "⚠️ $f 下载失败"; rm -rf "$dest"
            fi
        done
        fc-cache -f >/dev/null 2>&1 || true
    fi
    success "🎉 Nerd Font 安装完成（记得在终端模拟器设置里选择 Nerd Font 字体）"
}

list_names() {
    local f out=""
    for f in "${FONT_CASKS[@]}"; do out+="${f%%:*} "; done
    echo "${out% }"
}

uninstall_nerd_font() {
    detect_os
    local f
    for f in $(normalize_fonts); do
        if [[ "$OS_TYPE" == "darwin" ]]; then
            local cask; cask=$(cask_for "$f") && brew uninstall --cask "$cask" || true
        else
            rm -rf "$HOME/.local/share/fonts/NerdFonts/$f"
        fi
        info "已卸载: $f"
    done
    command_exists fc-cache && fc-cache -f >/dev/null 2>&1 || true
}

status_nerd_font() {
    detect_os
    local f found=() total=0
    for f in $(normalize_fonts); do
        total=$((total + 1))
        if [[ "$OS_TYPE" == "darwin" ]]; then
            ls "$HOME/Library/Fonts/${f}Nerd"* >/dev/null 2>&1 && found+=("$f")
        else
            [[ -d "$HOME/.local/share/fonts/NerdFonts/$f" ]] && found+=("$f")
        fi
    done
    local csv
    csv=$(IFS=,; echo "${found[*]:-}")
    if [[ ${#found[@]} -eq $total ]]; then
        emit_status "installed" "${GREEN}✅ 已安装: ${csv}${NC}"
    elif [[ ${#found[@]} -gt 0 ]]; then
        emit_status "installed" "${YELLOW}⚠️ 部分已安装: ${csv}${NC}"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
    [[ -n "$csv" ]] && emit_extra "fonts=$csv"
    return 0
}

usage() {
    cat <<EOF
用法: $0 {install|list|uninstall|status|help}

  install     安装 Nerd Font（默认 JetBrainsMono；UXS_CONFIG_FONTS="JetBrainsMono,FiraCode" 可指定）
  list        列出可安装字体
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_nerd_font ;;
        list)      list_names ;;
        uninstall) uninstall_nerd_font ;;
        status)    status_nerd_font ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

注意：实现时用 `brew search nerd-font` 核对 4 个 cask 名、用 nerd-fonts release 页核对 tar.xz 资产名与 `github_latest_tag` 返回的 tag 格式（v3.x 资产名含 `NerdFont` 后缀约定，如 `JetBrainsMono.tar.xz` 仍存在则维持；若改名，同步更新 url 拼接与 FONT_CASKS 表）。

README.md 按 scaffold 风格写（支持平台、子命令表、字体渲染在客户端的说明）。

- [ ] **Step 4: 测试 + 静态检查通过**

- [ ] **Step 5: Commit**

```bash
git add dev-tools/nerd-font tests/unit_terminal_enhance.sh
git commit -m "feat(nerd-font): 新模块——终端图标字体安装器（macOS cask / Linux ~/.local/share/fonts）"
```

---

### Task 4: 新模块 dev-tools/atuin（批次 T3）

**Files:**
- Create: `dev-tools/atuin/.manifest`、`dev-tools/atuin/install.sh`、`dev-tools/atuin/README.md`
- Test: `tests/unit_terminal_enhance.sh`（追加用例）

**Interfaces:**
- Consumes: `github_latest_tag`（仅回退路径取版本用于提示）、`command_exists`
- Produces: `bash dev-tools/atuin/install.sh install`（读 `UXS_CONFIG_SYNC`，默认 `0`）、`sync` 子命令；status `EXTRA=sync=on|off`——Task 5 编排调用

- [ ] **Step 1: 写失败测试**（追加，桩 PATH 假 atuin + 假 HOME 验证 status 机器模式）

```bash
# ---------- ③ atuin ----------
ATUIN_SH="$REPO_DIR/dev-tools/atuin/install.sh"
[[ -x "$ATUIN_SH" ]]
t_true "atuin: 模块文件存在且可执行" "$?"

printf '#!/bin/sh\necho "atuin 18.0.0"\n' > "$FAKE/atuin"; chmod +x "$FAKE/atuin"
mkdir -p "$FAKE/home/.config/atuin"
out=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" UXS_STATUS_MODE=machine bash "$ATUIN_SH" status </dev/null 2>/dev/null)
t_eq "atuin: 已装无 rc 集成 → EXTRA sync=off" "sync=off" "$(printf '%s' "$out" | sed -n 's/^EXTRA=sync=//p')"
t_eq "atuin: 已装 → STATE=installed" "installed" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

grep -q '^EXPORTABLE=sync$' "$REPO_DIR/dev-tools/atuin/.manifest"
t_true "atuin: manifest EXPORTABLE=sync" "$?"
```

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现**

`.manifest`：

```
LABEL=Atuin Shell 历史
CATEGORY=开发环境
ALIASES=atuin
DEFAULT_ACTION=install
EXPORTABLE=sync
DESC=SQLite 化 shell 历史（全量搜索/跨机加密同步）
NEXT_STEPS=开同步:atuin register;新开终端生效:exec zsh
```

`install.sh` 核心实现：

```bash
#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/atuin/install.sh
# Atuin：SQLite 化 shell 历史。默认纯本地（UXS_CONFIG_SYNC=0），
# UXS_CONFIG_SYNC=1 时提示用户自行 atuin register（不代注册）。
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

MARK="# >>> unix_script atuin >>>"
ENDMARK="# <<< unix_script atuin <<<"
RC_MARKER="$HOME/.config/atuin/.uxs_integrated"

install_atuin() {
    detect_os
    if ! command_exists atuin; then
        if [[ "$OS_TYPE" == "darwin" ]]; then
            command_exists brew || { error "macOS 需要 Homebrew"; return 1; }
            brew install atuin
        else
            if ! pkg_install atuin >/dev/null 2>&1; then
                # 信任模型：setup.atuin.sh 为官方安装器（HTTPS），装到 $HOME/.atuin/bin
                local ver; ver=$(github_latest_tag "atuinsh/atuin" 2>/dev/null || echo "latest")
                info "仓库无 atuin 包，走官方脚本（目标版本：${ver}）..."
                curl -fsSL https://setup.atuin.sh | sh || { error "atuin 安装失败"; return 1; }
            fi
        fi
    fi
    command_exists atuin || [[ -x "$HOME/.atuin/bin/atuin" ]] || { error "atuin 仍未可用"; return 1; }

    configure_rc
    import_history

    if [[ "${UXS_CONFIG_SYNC:-0}" == "1" ]]; then
        info "同步已开启配置：请运行  atuin register  注册账号（交互式，需自行操作）"
        info "之后任意机器  atuin login <用户名> + atuin sync  即可同步历史"
    fi
    success "🎉 Atuin 安装完成（sync=${UXS_CONFIG_SYNC:-0}）"
    info "新开终端或 exec zsh 生效；Ctrl+R 改为 atuin 全量模糊搜索"
}

configure_rc() {
    local bin_path=""
    [[ -x "$HOME/.atuin/bin/atuin" ]] && bin_path='export PATH="$HOME/.atuin/bin:$PATH"'
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [[ -f "$rc" ]] || continue
        grep -q "$MARK" "$rc" 2>/dev/null && continue
        {
            echo ""
            echo "$MARK"
            [[ -n "$bin_path" ]] && echo "$bin_path"
            echo "command -v atuin >/dev/null 2>&1 && eval \"\$(atuin init \$(basename \$SHELL))\""
            echo "$ENDMARK"
        } >> "$rc"
        info "已为 $(basename "$rc") 添加 atuin 集成"
    done
    mkdir -p "$(dirname "$RC_MARKER")"; touch "$RC_MARKER"
}

import_history() {
    # 首次安装时迁移旧历史；标记文件保证幂等
    local imported_flag="$HOME/.config/atuin/.uxs_imported"
    [[ -f "$imported_flag" ]] && return 0
    local atuin_bin="atuin"
    command_exists atuin || atuin_bin="$HOME/.atuin/bin/atuin"
    if "$atuin_bin" import-auto >/dev/null 2>&1; then
        info "旧 shell 历史已导入 atuin"
    else
        warn "旧历史导入失败（可稍后手动执行: atuin import-auto）"
    fi
    mkdir -p "$(dirname "$imported_flag")"; touch "$imported_flag"
}

cmd_sync() {
    if [[ "${UXS_CONFIG_SYNC:-0}" != "1" ]]; then
        warn "当前为纯本地模式（UXS_CONFIG_SYNC 未开启），无需同步"
        return 0
    fi
    command_exists atuin && atuin sync
}

uninstall_atuin() {
    detect_os
    warn "atuin 卸载说明："
    echo "  程序:   brew uninstall atuin 或 sudo <pkgmgr> remove atuin"
    echo "  shell:  删除 rc 中 '$MARK' 之间的行"
    echo "  数据:   rm -rf ~/.local/share/atuin ~/.config/atuin"
    info "（按需手动清理）"
}

status_atuin() {
    detect_os
    if command_exists atuin || [[ -x "$HOME/.atuin/bin/atuin" ]]; then
        local sync="off"
        grep -qs "$MARK" "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null && sync="on"
        emit_status "installed" "${GREEN}✅ atuin 已安装（shell 集成: $sync）${NC}"
        emit_extra "sync=$sync"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
    return 0
}

usage() {
    cat <<EOF
用法: $0 {install|sync|uninstall|status|help}

  install     安装 atuin + rc 集成 + 旧历史导入（UXS_CONFIG_SYNC=1 开启同步提示）
  sync        手动同步（需已开启同步并注册）
  uninstall   显示卸载说明
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_atuin ;;
        sync)      cmd_sync ;;
        uninstall) uninstall_atuin ;;
        status)    status_atuin ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

注意两点实现时核实：① setup.atuin.sh 在 2026 年的安装路径仍是 `~/.atuin/bin`（若已变，同步调整 PATH 行与 status 的探测路径）；② `import-auto` 子命令名（老版本为 `atuin import` / `atuin import zsh`）。

README 按 scaffold 风格。

- [ ] **Step 4: 测试 + 静态检查通过**

- [ ] **Step 5: Commit**

```bash
git add dev-tools/atuin tests/unit_terminal_enhance.sh
git commit -m "feat(atuin): 新模块——SQLite shell 历史（默认本地，UXS_CONFIG_SYNC 开同步）"
```

---

### Task 5: 新模块 dev-tools/terminal（编排，批次 T3）

**Files:**
- Create: `dev-tools/terminal/.manifest`、`dev-tools/terminal/install.sh`、`dev-tools/terminal/README.md`
- Test: `tests/unit_terminal_enhance.sh`（追加用例）

**Interfaces:**
- Consumes: Task 1 的 `zsh_setup install`；Task 2 扩展后的 modern-cli；Task 3/4 的 nerd-font、atuin（均以 `bash ../<模块>/install.sh <子命令>` 子进程调用，`UXS_CONFIG_*` 环境变量自然继承）
- Produces: `./install.sh terminal` 全家桶入口；status 机器模式：全就绪 `STATE=installed`，缺环节 `STATE=not_installed` + `EXTRA=missing=<csv>`

- [ ] **Step 1: 写失败测试**（追加）

```bash
# ---------- ⑤ terminal 编排 ----------
TERM_MANIFEST="$REPO_DIR/dev-tools/terminal/.manifest"
TERM_SH="$REPO_DIR/dev-tools/terminal/install.sh"
[[ -x "$TERM_SH" ]]
t_true "terminal: 模块文件存在且可执行" "$?"
grep -q '^DESC=' "$TERM_MANIFEST" && ! grep -q '^EXPORTABLE=' "$TERM_MANIFEST"
t_true "terminal: manifest 无 EXPORTABLE（子模块自治声明）" "$?"

# EXCLUDE=all → install 穭等完成 rc=0，不触发任何子模块安装
HOME="$FAKE/home" UXS_CONFIG_EXCLUDE="zsh,zsh_setup,modern-cli,nerd-font,atuin" \
    bash "$TERM_SH" install </dev/null >/dev/null 2>&1
t_eq "terminal: EXCLUDE 全排除 install rc=0" "0" "$?"

out=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" UXS_STATUS_MODE=machine bash "$TERM_SH" status </dev/null 2>/dev/null)
t_eq "terminal: 全缺 → STATE=not_installed" "not_installed" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"
t_true "terminal: EXTRA=missing 含 zsh" "printf '%s' \"\$out\" | grep -q 'missing=.*zsh'"
```

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现**

`.manifest`：

```
LABEL=终端全家桶
CATEGORY=开发环境
ALIASES=terminal
DEFAULT_ACTION=install
DESC=一键终端配置：zsh+zsh_setup+modern-cli+nerd-font+atuin
NEXT_STEPS=新开终端或 exec zsh 生效;微调框架/主题:./install.sh zsh_setup
```

`install.sh` 核心实现：

```bash
#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/terminal/install.sh
# 终端全家桶编排：按序调用同级子模块，逐步幂等跳过已就绪环节。
# 不走阶段 E REQUIRES——REQUIRES 自动装依赖无法传递框架/字体偏好，必须自编排带参调用。
# UXS_CONFIG_EXCLUDE=zsh_setup,atuin 可裁剪环节。
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 编排顺序即依赖顺序
STEPS=(zsh zsh_setup modern-cli nerd-font atuin)
STEP_DESC=(zsh 本体 "Zsh + Oh My Zsh" "现代 CLI 工具集" "Nerd Font 字体" "Atuin 历史")

module_dir() { echo "$SCRIPT_DIR/../$1"; }

excluded() {
    local e
    local IFS=,
    for e in ${UXS_CONFIG_EXCLUDE:-}; do
        [[ "$e" == "$1" ]] && return 0
    done
    return 1
}

step_ready() {
    case "$1" in
        zsh)       command_exists zsh ;;
        zsh_setup) [[ "$(machine_state zsh_setup)" == "installed" ]] ;;
        modern-cli)[[ "$(machine_state modern-cli)" == "installed" ]] ;;
        nerd-font) [[ "$(machine_state nerd-font)" == "installed" ]] ;;
        atuin)     [[ "$(machine_state atuin)" == "installed" ]] ;;
        *) return 1 ;;
    esac
}

# 调子模块机器模式 status，取首个 STATE=
machine_state() {
    local mod="$1"
    ( cd "$(module_dir "$mod")" && UXS_STATUS_MODE=machine bash ./install.sh status </dev/null 2>/dev/null ) \
        | sed -n 's/^STATE=//p' | head -1
}

install_terminal() {
    detect_os
    local i mod
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        if excluded "$mod"; then
            info "⏭ 跳过（UXS_CONFIG_EXCLUDE）: ${STEP_DESC[$i]}"
            continue
        fi
        if step_ready "$mod"; then
            success "✅ 已就绪: ${STEP_DESC[$i]}"
            continue
        fi
        info "🔧 安装: ${STEP_DESC[$i]} ..."
        if [[ "$mod" == "zsh" ]]; then
            command_exists zsh || pkg_install zsh || { error "zsh 本体安装失败"; return 1; }
        else
            bash "$(module_dir "$mod")/install.sh" install || warn "⚠️ ${STEP_DESC[$i]} 安装失败（继续后续环节）"
        fi
    done
    status_terminal_human
    success "🎉 终端全家桶完成！新开终端或 exec zsh 生效"
}

status_terminal_human() {
    local i mod mark
    echo
    info "环节状态："
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        if excluded "$mod"; then mark="⏭ 跳过"
        elif step_ready "$mod"; then mark="✅"
        else mark="❌"; fi
        echo "  $mark ${STEP_DESC[$i]}"
    done
}

status_terminal() {
    detect_os
    local i mod missing=() ready=0 total=0
    for i in "${!STEPS[@]}"; do
        mod="${STEPS[$i]}"
        excluded "$mod" && continue
        total=$((total + 1))
        if step_ready "$mod"; then
            ready=$((ready + 1))
        else
            missing+=("$mod")
        fi
    done
    if [[ $ready -eq $total ]]; then
        emit_status "installed" "${GREEN}✅ 终端全家桶全部就绪（$ready/$total）${NC}"
    else
        local csv; csv=$(IFS=,; echo "${missing[*]}")
        if [[ $ready -gt 0 ]]; then
            emit_status "not_installed" "${YELLOW}⚠️ 部分就绪（$ready/$total）${NC}"
        else
            emit_status "not_installed" "${RED}❌ 未配置${NC}"
        fi
        emit_extra "missing=$csv"
    fi
    return 0
}

uninstall_terminal() {
    warn "terminal 为编排模块，无独立卸载；请逐个子模块 uninstall："
    echo "  ./install.sh atuin uninstall && ./install.sh zsh_setup uninstall"
    echo "  rc 清理: 删除各 '# >>> unix_script <模块> >>>' 标记块"
}

usage() {
    cat <<EOF
用法: $0 {install|status|help}

  install     一键终端全家桶（zsh → zsh_setup → modern-cli → nerd-font → atuin）
              UXS_CONFIG_FRAMEWORK=oh-my-zsh  框架选择（透传 zsh_setup）
              UXS_CONFIG_THEME=p10k           主题（透传 zsh_setup）
              UXS_CONFIG_FONTS=JetBrainsMono  字体清单（透传 nerd-font）
              UXS_CONFIG_SYNC=0               atuin 同步开关（透传 atuin）
              UXS_CONFIG_EXCLUDE=atuin,nerd-font  裁剪环节
  status      查看各环节就绪状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_terminal ;;
        status)    status_terminal ;;
        uninstall) uninstall_terminal ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

注意：`zsh_setup` 的机器模式 status 在 `--text` 分支输出 `STATE=installed|not_installed`（Task 1 前已实现，见其 show_status 注释）；`modern-cli` 部分安装输出 `STATE=installed`，编排视为就绪（与库既有 status-json 语义一致）。测试里 `EXCLUDE` 全排除后 install 不触发网络调用即 rc=0。

- [ ] **Step 4: 测试 + 静态检查通过**

- [ ] **Step 5: Commit**

```bash
git add dev-tools/terminal tests/unit_terminal_enhance.sh
git commit -m "feat(terminal): 一键终端全家桶编排模块（自编排带参，UXS_CONFIG_EXCLUDE 裁剪）"
```

---

### Task 6: 挂接 CI + 全量回归

**Files:**
- Modify: `tests/ci_run.sh`（routing 段的 assert 列表追加一行，参照 :515 usability 行的位置）
- Test: 全部既有 + 新单测

**Interfaces:**
- Consumes: `tests/unit_terminal_enhance.sh`（Task 1 创建，Tasks 2–5 逐步充实）
- Produces: CI routing/static 阶段自动跑新单测

- [ ] **Step 1:** ci_run.sh 的 unit 断言区（`assert "usability: 批次① 单测全过"` 行之后）加：

```bash
    assert "terminal-enhance: 终端增强单测全过" bash "$REPO_DIR/tests/unit_terminal_enhance.sh"
```

- [ ] **Step 2:** 检查新模块被框架注册：`./install.sh --list-modules | tr ' ' '\n' | grep -E '^(atuin|nerd-font|terminal)$'` 三行齐出（.manifest 自动注册，无需改 registry 代码；若缺，排查 .manifest 格式）

- [ ] **Step 3:** 全量回归：`./tests/ci_run.sh --phase static && ./tests/ci_run.sh --phase routing`
Expected: 全绿。若本机无法跑 routing 完整矩阵，至少跑 static + 单测并在交付说明中注明。

- [ ] **Step 4: Commit**

```bash
git add tests/ci_run.sh
git commit -m "test(ci): 挂接 unit_terminal_enhance 单测"
```

---

### Task 7: 文档收尾

**Files:**
- Modify: `AGENTS.md`（模块总数 58→61，dev-tools 12→15；AI 工作流第 2 步提及 `search terminal`）
- Modify: `README.md`（若模块总数/清单为手写则同步；支持矩阵表格由 CI 自动刷新，不动）
- Modify: `dev-tools/terminal/README.md` 交叉链接 zsh_setup/modern-cli/nerd-font/atuin

**Interfaces:** 无代码接口，纯文档一致性。

- [ ] **Step 1:** 全库 grep 旧总数：`grep -rn "58 个模块\|58 个\|12 个模块" AGENTS.md README.md docs/ --include="*.md"`，逐一更新为 61/15（实际出现处为准，只改确实指模块总数处）
- [ ] **Step 2:** AGENTS.md「这是什么」表格 dev-tools 行 12→15
- [ ] **Step 3:** Commit

```bash
git add AGENTS.md README.md
git commit -m "docs: 终端增强批次模块清单更新（58→61）"
```

---

## 自审记录（Self-Review）

1. **Spec 覆盖**：spec ①→Task 1、②→Task 2、③→Task 4、④→Task 3、⑤→Task 5；测试章节→Task 1/6；批次 T1/T2/T3 顺序已按依赖排布（Task 4 依赖 Task 1 的结论在 Task 5 编排中体现，atuin 本身不依赖 T1，可与 T2 并行）。EXPORTABLE 分工（子模块自治、terminal 无）在 Global Constraints 与 Task 5 测试断言双重锁定。✅
2. **占位符扫描**：无 TBD/TODO；两处「实现时核实」（nerd-font cask 名、atuin 安装路径/子命令名）均为外部事实核对指引而非缺口，附了默认值与调整方向。✅
3. **接口一致性**：`UXS_CONFIG_{FRAMEWORK,THEME,FONTS,SYNC,EXCLUDE}` 键名在各任务 usage/透传/测试中一致；`machine_state` 只在 Task 5 内定义并使用；测试文件 `t_eq/t_true` 骨架 Task 1 定义、后续任务复用 `$FAKE` 变量（Task 1 创建，后续追加用例位于同一文件同一作用域）。✅
