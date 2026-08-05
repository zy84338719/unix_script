# zsh_setup 模块化重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构 zsh_setup 模块，支持多框架（Oh My Zsh、Prezto、Zinit、sheldon），提供统一的插件管理、主题管理和配置管理功能

**Architecture:** 模块化架构，将功能拆分为独立的库文件（lib/），每个框架有独立的适配器（frameworks/），通过统一的接口层提供一致的用户体验

**Tech Stack:** Bash, Git, curl

## Global Constraints

- 所有脚本使用 Bash 编写，兼容 macOS 和 Linux
- 遵循项目现有的代码风格和目录结构
- 使用 `lib/common.sh` 提供的公共函数
- 所有子命令支持 `help` 输出
- 状态查询支持 `--json` 格式输出

---

## 文件结构

```
zsh_setup/
├── install.sh              # 主入口，子命令路由
├── lib/
│   ├── common.sh          # 公共函数库
│   ├── framework.sh       # 框架安装/管理抽象层
│   ├── plugins.sh         # 插件管理
│   ├── themes.sh          # 主题管理
│   └── config.sh          # 配置管理
├── frameworks/
│   ├── oh-my-zsh.sh       # Oh My Zsh 特定逻辑
│   ├── prezto.sh          # Prezto 特定逻辑
│   ├── zinit.sh           # Zinit 特定逻辑
│   └── sheldon.sh         # sheldon 特定逻辑
├── templates/
│   ├── aliases.zsh        # 通用别名模板
│   ├── env.zsh            # 环境变量模板
│   └── p10k.zsh           # Powerlevel10k 配置模板
└── README.md              # 模块文档
```

---

## Task 1: 创建目录结构和公共函数库

**Files:**
- Create: `zsh_setup/lib/common.sh`
- Create: `zsh_setup/lib/framework.sh`
- Create: `zsh_setup/lib/plugins.sh`
- Create: `zsh_setup/lib/themes.sh`
- Create: `zsh_setup/lib/config.sh`
- Create: `zsh_setup/frameworks/oh-my-zsh.sh`
- Create: `zsh_setup/frameworks/prezto.sh`
- Create: `zsh_setup/frameworks/zinit.sh`
- Create: `zsh_setup/frameworks/sheldon.sh`
- Create: `zsh_setup/templates/aliases.zsh`
- Create: `zsh_setup/templates/env.zsh`
- Create: `zsh_setup/templates/p10k.zsh`

**Interfaces:**
- Consumes: `../lib/common.sh` (from project root)
- Produces: 公共函数库供所有其他任务使用

- [ ] **Step 1: 创建目录结构**

```bash
cd zsh_setup
mkdir -p lib frameworks templates
```

- [ ] **Step 2: 实现公共函数库**

创建 `zsh_setup/lib/common.sh`:

```bash
#!/bin/bash
#
# zsh_setup/lib/common.sh
# 公共函数库
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 命令检测
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检测操作系统
detect_os() {
    OS="$(uname -s)"
    if [[ "$OS" == "Linux" ]]; then
        if command_exists apt-get; then
            PKG_MANAGER="apt-get"
        elif command_exists yum; then
            PKG_MANAGER="yum"
        elif command_exists dnf; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="unknown"
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        PKG_MANAGER="brew"
    else
        PKG_MANAGER="unknown"
    fi
}

# 检测当前框架
detect_framework() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "oh-my-zsh"
    elif [ -d "${ZDOTDIR:-$HOME}/.zprezto" ]; then
        echo "prezto"
    elif [ -d "$HOME/.local/share/zinit" ] || [ -d "$HOME/.zinit" ]; then
        echo "zinit"
    elif command_exists sheldon; then
        echo "sheldon"
    else
        echo "none"
    fi
}

# 确认提示
confirm() {
    local message="$1"
    read -r -p "$message (y/N) " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# 配置目录
CONFIG_DIR="${HOME}/.config/zsh_setup"
BACKUP_DIR="${CONFIG_DIR}/backups"
```

- [ ] **Step 3: 验证公共函数库**

```bash
source zsh_setup/lib/common.sh
command_exists git && echo "git exists" || echo "git not found"
detect_os
echo "OS: $OS, Package Manager: $PKG_MANAGER"
```

- [ ] **Step 4: 提交**

```bash
git add zsh_setup/lib/
git commit -m "feat(zsh-setup): add lib directory structure and common.sh"
```

---

## Task 2: 实现框架抽象层

**Files:**
- Create: `zsh_setup/lib/framework.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`
- Produces: `framework_install()`, `framework_uninstall()`, `framework_status()`, `framework_list_plugins()`

- [ ] **Step 1: 实现框架抽象层**

创建 `zsh_setup/lib/framework.sh`:

```bash
#!/bin/bash
#
# zsh_setup/lib/framework.sh
# 框架抽象层
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 加载框架适配器
load_framework() {
    local framework="$1"
    local adapter="$SCRIPT_DIR/../frameworks/${framework}.sh"
    
    if [ ! -f "$adapter" ]; then
        error "未找到框架适配器: $framework"
        return 1
    fi
    
    source "$adapter"
}

# 安装框架
framework_install() {
    local framework="$1"
    
    if [ -z "$framework" ]; then
        error "请指定框架名称"
        return 1
    fi
    
    load_framework "$framework" || return 1
    
    info "正在安装 $framework..."
    if "install_${framework//-/_}"; then
        success "$framework 安装成功"
    else
        error "$framework 安装失败"
        return 1
    fi
}

# 卸载框架
framework_uninstall() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        warn "未检测到已安装的框架"
        return 0
    fi
    
    load_framework "$framework" || return 1
    
    info "正在卸载 $framework..."
    if "uninstall_${framework//-/_}"; then
        success "$framework 卸载成功"
    else
        error "$framework 卸载失败"
        return 1
    fi
}

# 框架状态
framework_status() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        echo "未安装框架"
        return 0
    fi
    
    load_framework "$framework" || return 1
    
    "status_${framework//-/_}"
}

# 列出框架插件
framework_list_plugins() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi
    
    load_framework "$framework" || return 1
    
    "list_plugins_${framework//-/_}"
}

# 交互式选择框架
framework_select() {
    echo "可用的 Zsh 框架:"
    echo "  1) Oh My Zsh - 最流行，插件丰富"
    echo "  2) Prezto - 轻量级，模块化"
    echo "  3) Zinit - 性能极佳，异步加载"
    echo "  4) sheldon - 现代化，Rust 编写"
    echo ""
    
    read -r -p "请选择框架 (1-4): " choice
    
    case "$choice" in
        1) framework_install "oh-my-zsh" ;;
        2) framework_install "prezto" ;;
        3) framework_install "zinit" ;;
        4) framework_install "sheldon" ;;
        *) error "无效选择"; return 1 ;;
    esac
}
```

- [ ] **Step 2: 验证框架抽象层**

```bash
source zsh_setup/lib/framework.sh
detect_framework
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/lib/framework.sh
git commit -m "feat(zsh-setup): add framework abstraction layer"
```

---

## Task 3: 实现 Oh My Zsh 适配器

**Files:**
- Create: `zsh_setup/frameworks/oh-my-zsh.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`
- Produces: `install_oh_my_zsh()`, `uninstall_oh_my_zsh()`, `status_oh_my_zsh()`, `list_plugins_oh_my_zsh()`

- [ ] **Step 1: 实现 Oh My Zsh 适配器**

创建 `zsh_setup/frameworks/oh-my-zsh.sh`:

```bash
#!/bin/bash
#
# zsh_setup/frameworks/oh-my-zsh.sh
# Oh My Zsh 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_DIR="${ZSH_CUSTOM:-$OH_MY_ZSH_DIR/custom}"

# 安装 Oh My Zsh
install_oh_my_zsh() {
    if [ -d "$OH_MY_ZSH_DIR" ]; then
        warn "Oh My Zsh 已安装"
        return 0
    fi
    
    info "正在安装 Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        error "Oh My Zsh 安装失败"
        return 1
    fi
    
    success "Oh My Zsh 安装成功"
}

# 卸载 Oh My Zsh
uninstall_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        warn "Oh My Zsh 未安装"
        return 0
    fi
    
    if ! confirm "确定要卸载 Oh My Zsh 吗？"; then
        info "取消卸载"
        return 0
    fi
    
    info "正在卸载 Oh My Zsh..."
    
    # 使用官方卸载脚本
    if [ -f "$OH_MY_ZSH_DIR/tools/uninstall.sh" ]; then
        bash "$OH_MY_ZSH_DIR/tools/uninstall.sh"
    else
        rm -rf "$OH_MY_ZSH_DIR"
    fi
    
    success "Oh My Zsh 已卸载"
}

# Oh My Zsh 状态
status_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        echo "Oh My Zsh: 未安装"
        return 0
    fi
    
    echo "Oh My Zsh: 已安装"
    
    # 检测主题
    if [ -f "$HOME/.zshrc" ]; then
        local theme
        theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2)
        echo "主题: ${theme:-未设置}"
    fi
    
    # 列出插件
    echo "插件:"
    list_plugins_oh_my_zsh
}

# 列出 Oh My Zsh 插件
list_plugins_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        warn "Oh My Zsh 未安装"
        return 0
    fi
    
    # 内置插件
    echo "内置插件:"
    ls "$OH_MY_ZSH_DIR/plugins/" 2>/dev/null | head -20
    
    # 自定义插件
    if [ -d "$CUSTOM_DIR/plugins" ]; then
        echo ""
        echo "自定义插件:"
        ls "$CUSTOM_DIR/plugins/" 2>/dev/null
    fi
}

# 安装插件
install_plugin_oh_my_zsh() {
    local plugin_name="$1"
    local plugin_url="$2"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    local plugin_dir="$CUSTOM_DIR/plugins/$plugin_name"
    
    if [ -d "$plugin_dir" ]; then
        warn "插件 $plugin_name 已安装"
        return 0
    fi
    
    if [ -z "$plugin_url" ]; then
        # 使用默认插件仓库
        plugin_url="https://github.com/zsh-users/$plugin_name.git"
    fi
    
    info "正在安装插件 $plugin_name..."
    git clone "$plugin_url" "$plugin_dir"
    
    if [ $? -eq 0 ]; then
        success "插件 $plugin_name 安装成功"
        info "请在 .zshrc 的 plugins 数组中添加 $plugin_name"
    else
        error "插件 $plugin_name 安装失败"
        return 1
    fi
}

# 卸载插件
uninstall_plugin_oh_my_zsh() {
    local plugin_name="$1"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    local plugin_dir="$CUSTOM_DIR/plugins/$plugin_name"
    
    if [ ! -d "$plugin_dir" ]; then
        warn "插件 $plugin_name 未安装"
        return 0
    fi
    
    if ! confirm "确定要卸载插件 $plugin_name 吗？"; then
        info "取消卸载"
        return 0
    fi
    
    rm -rf "$plugin_dir"
    success "插件 $plugin_name 已卸载"
    info "请从 .zshrc 的 plugins 数组中移除 $plugin_name"
}
```

- [ ] **Step 2: 验证 Oh My Zsh 适配器**

```bash
source zsh_setup/frameworks/oh-my-zsh.sh
status_oh_my_zsh
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/frameworks/oh-my-zsh.sh
git commit -m "feat(zsh-setup): add Oh My Zsh adapter"
```

---

## Task 4: 实现 Prezto 适配器

**Files:**
- Create: `zsh_setup/frameworks/prezto.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`
- Produces: `install_prezto()`, `uninstall_prezto()`, `status_prezto()`, `list_plugins_prezto()`

- [ ] **Step 1: 实现 Prezto 适配器**

创建 `zsh_setup/frameworks/prezto.sh`:

```bash
#!/bin/bash
#
# zsh_setup/frameworks/prezto.sh
# Prezto 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PREZTO_DIR="${ZDOTDIR:-$HOME}/.zprezto"

# 安装 Prezto
install_prezto() {
    if [ -d "$PREZTO_DIR" ]; then
        warn "Prezto 已安装"
        return 0
    fi
    
    info "正在安装 Prezto..."
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "$PREZTO_DIR"
    
    if [ ! -d "$PREZTO_DIR" ]; then
        error "Prezto 安装失败"
        return 1
    fi
    
    # 创建符号链接
    for rcfile in "$PREZTO_DIR"/runcoms/z*; do
        [ -f "${ZDOTDIR:-$HOME}/.${rcfile:t}" ] && continue
        ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
    done
    
    success "Prezto 安装成功"
}

# 卸载 Prezto
uninstall_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        warn "Prezto 未安装"
        return 0
    fi
    
    if ! confirm "确定要卸载 Prezto 吗？"; then
        info "取消卸载"
        return 0
    fi
    
    info "正在卸载 Prezto..."
    
    # 删除符号链接
    for rcfile in "$PREZTO_DIR"/runcoms/z*; do
        local target="${ZDOTDIR:-$HOME}/.${rcfile:t}"
        [ -L "$target" ] && rm -f "$target"
    done
    
    rm -rf "$PREZTO_DIR"
    success "Prezto 已卸载"
}

# Prezto 状态
status_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        echo "Prezto: 未安装"
        return 0
    fi
    
    echo "Prezto: 已安装"
    
    # 检测主题
    if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
        local theme
        theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}')
        echo "主题: ${theme:-未设置}"
    fi
    
    # 列出模块
    echo "模块:"
    list_plugins_prezto
}

# 列出 Prezto 模块
list_plugins_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        warn "Prezto 未安装"
        return 0
    fi
    
    # 内置模块
    echo "内置模块:"
    ls "$PREZTO_DIR/modules/" 2>/dev/null
    
    # 外部模块（contrib）
    if [ -d "$PREZTO_DIR/contrib" ]; then
        echo ""
        echo "外部模块:"
        ls "$PREZTO_DIR/contrib/" 2>/dev/null
    fi
}

# 启用模块
enable_module_prezto() {
    local module_name="$1"
    
    if [ -z "$module_name" ]; then
        error "请指定模块名称"
        return 1
    fi
    
    local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"
    
    if [ ! -f "$preztorc" ]; then
        error "未找到 .zpreztorc 文件"
        return 1
    fi
    
    # 检查模块是否已启用
    if grep -q "'$module_name'" "$preztorc"; then
        warn "模块 $module_name 已启用"
        return 0
    fi
    
    # 添加模块到 zpreztorc
    sed -i.bak "s/^\(  'completion'\)/\1\n  '$module_name'/" "$preztorc"
    success "模块 $module_name 已启用"
}

# 禁用模块
disable_module_prezto() {
    local module_name="$1"
    
    if [ -z "$module_name" ]; then
        error "请指定模块名称"
        return 1
    fi
    
    local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"
    
    if [ ! -f "$preztorc" ]; then
        error "未找到 .zpreztorc 文件"
        return 1
    fi
    
    # 删除模块
    sed -i.bak "/'$module_name'/d" "$preztorc"
    success "模块 $module_name 已禁用"
}
```

- [ ] **Step 2: 验证 Prezto 适配器**

```bash
source zsh_setup/frameworks/prezto.sh
status_prezto
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/frameworks/prezto.sh
git commit -m "feat(zsh-setup): add Prezto adapter"
```

---

## Task 5: 实现 Zinit 适配器

**Files:**
- Create: `zsh_setup/frameworks/zinit.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`
- Produces: `install_zinit()`, `uninstall_zinit()`, `status_zinit()`, `list_plugins_zinit()`

- [ ] **Step 1: 实现 Zinit 适配器**

创建 `zsh_setup/frameworks/zinit.sh`:

```bash
#!/bin/bash
#
# zsh_setup/frameworks/zinit.sh
# Zinit 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

ZINIT_DIR="${HOME}/.local/share/zinit/zinit.git"

# 安装 Zinit
install_zinit() {
    if [ -d "$ZINIT_DIR" ]; then
        warn "Zinit 已安装"
        return 0
    fi
    
    info "正在安装 Zinit..."
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
    
    if [ ! -d "$ZINIT_DIR" ]; then
        error "Zinit 安装失败"
        return 1
    fi
    
    success "Zinit 安装成功"
}

# 卸载 Zinit
uninstall_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        warn "Zinit 未安装"
        return 0
    fi
    
    if ! confirm "确定要卸载 Zinit 吗？"; then
        info "取消卸载"
        return 0
    fi
    
    info "正在卸载 Zinit..."
    rm -rf "$ZINIT_DIR"
    rm -rf "${HOME}/.local/share/zinit"
    
    success "Zinit 已卸载"
}

# Zinit 状态
status_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        echo "Zinit: 未安装"
        return 0
    fi
    
    echo "Zinit: 已安装"
    
    # 列出插件
    echo "插件:"
    list_plugins_zinit
}

# 列出 Zinit 插件
list_plugins_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        warn "Zinit 未安装"
        return 0
    fi
    
    # 从 .zshrc 中提取插件
    if [ -f "$HOME/.zshrc" ]; then
        grep "zinit light" "$HOME/.zshrc" | sed 's/.*zinit light //' | sed 's/["]//g'
    fi
}

# 安装插件
install_plugin_zinit() {
    local plugin_name="$1"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    local zshrc="$HOME/.zshrc"
    
    if [ ! -f "$zshrc" ]; then
        error "未找到 .zshrc 文件"
        return 1
    fi
    
    # 检查插件是否已安装
    if grep -q "zinit light $plugin_name" "$zshrc"; then
        warn "插件 $plugin_name 已安装"
        return 0
    fi
    
    # 添加插件到 .zshrc
    echo "zinit light $plugin_name" >> "$zshrc"
    success "插件 $plugin_name 已添加"
    info "请运行 'source ~/.zshrc' 或重启终端以加载插件"
}

# 卸载插件
uninstall_plugin_zinit() {
    local plugin_name="$1"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    local zshrc="$HOME/.zshrc"
    
    if [ ! -f "$zshrc" ]; then
        error "未找到 .zshrc 文件"
        return 1
    fi
    
    # 删除插件
    sed -i.bak "/zinit light $plugin_name/d" "$zshrc"
    success "插件 $plugin_name 已移除"
}
```

- [ ] **Step 2: 验证 Zinit 适配器**

```bash
source zsh_setup/frameworks/zinit.sh
status_zinit
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/frameworks/zinit.sh
git commit -m "feat(zsh-setup): add Zinit adapter"
```

---

## Task 6: 实现 sheldon 适配器

**Files:**
- Create: `zsh_setup/frameworks/sheldon.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`
- Produces: `install_sheldon()`, `uninstall_sheldon()`, `status_sheldon()`, `list_plugins_sheldon()`

- [ ] **Step 1: 实现 sheldon 适配器**

创建 `zsh_setup/frameworks/sheldon.sh`:

```bash
#!/bin/bash
#
# zsh_setup/frameworks/sheldon.sh
# sheldon 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

SHELDON_CONFIG="${HOME}/.config/sheldon/plugins.toml"

# 安装 sheldon
install_sheldon() {
    if command_exists sheldon; then
        warn "sheldon 已安装"
        return 0
    fi
    
    info "正在安装 sheldon..."
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon
    
    if ! command_exists sheldon; then
        error "sheldon 安装失败"
        return 1
    fi
    
    # 创建配置目录
    mkdir -p "$(dirname "$SHELDON_CONFIG")"
    
    # 创建默认配置
    if [ ! -f "$SHELDON_CONFIG" ]; then
        cat > "$SHELDON_CONFIG" << 'EOF'
# ~/.config/sheldon/plugins.toml

[plugins]

# Example:
# [plugins.zsh-autosuggestions]
# github = "zsh-users/zsh-autosuggestions"
EOF
    fi
    
    success "sheldon 安装成功"
}

# 卸载 sheldon
uninstall_sheldon() {
    if ! command_exists sheldon; then
        warn "sheldon 未安装"
        return 0
    fi
    
    if ! confirm "确定要卸载 sheldon 吗？"; then
        info "取消卸载"
        return 0
    fi
    
    info "正在卸载 sheldon..."
    
    # 删除 sheldon 二进制文件
    local sheldon_path
    sheldon_path=$(which sheldon)
    if [ -n "$sheldon_path" ]; then
        rm -f "$sheldon_path"
    fi
    
    success "sheldon 已卸载"
}

# sheldon 状态
status_sheldon() {
    if ! command_exists sheldon; then
        echo "sheldon: 未安装"
        return 0
    fi
    
    echo "sheldon: 已安装"
    
    # 列出插件
    echo "插件:"
    list_plugins_sheldon
}

# 列出 sheldon 插件
list_plugins_sheldon() {
    if [ ! -f "$SHELDON_CONFIG" ]; then
        warn "未找到 sheldon 配置文件"
        return 0
    fi
    
    # 从配置文件中提取插件
    grep "^\[plugins\." "$SHELDON_CONFIG" | sed 's/\[plugins\.\(.*\)\]/\1/'
}

# 安装插件
install_plugin_sheldon() {
    local plugin_name="$1"
    local plugin_repo="$2"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    if [ -z "$plugin_repo" ]; then
        error "请指定插件仓库 (格式: user/repo)"
        return 1
    fi
    
    if [ ! -f "$SHELDON_CONFIG" ]; then
        mkdir -p "$(dirname "$SHELDON_CONFIG")"
        cat > "$SHELDON_CONFIG" << 'EOF'
[plugins]
EOF
    fi
    
    # 检查插件是否已存在
    if grep -q "^\[plugins\.$plugin_name\]" "$SHELDON_CONFIG"; then
        warn "插件 $plugin_name 已存在"
        return 0
    fi
    
    # 添加插件到配置
    cat >> "$SHELDON_CONFIG" << EOF

[plugins.$plugin_name]
github = "$plugin_repo"
EOF
    
    success "插件 $plugin_name 已添加"
}

# 卸载插件
uninstall_plugin_sheldon() {
    local plugin_name="$1"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    if [ ! -f "$SHELDON_CONFIG" ]; then
        warn "未找到 sheldon 配置文件"
        return 0
    fi
    
    # 删除插件配置（使用 sed 删除从 [plugins.name] 到下一个 [ 或文件末尾的内容）
    sed -i.bak "/^\[plugins\.$plugin_name\]/,/^\[/{ /^\[plugins\.$plugin_name\]/d; /^\[/!d; }" "$SHELDON_CONFIG"
    success "插件 $plugin_name 已移除"
}
```

- [ ] **Step 2: 验证 sheldon 适配器**

```bash
source zsh_setup/frameworks/sheldon.sh
status_sheldon
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/frameworks/sheldon.sh
git commit -m "feat(zsh-setup): add sheldon adapter"
```

---

## Task 7: 实现插件管理模块

**Files:**
- Create: `zsh_setup/lib/plugins.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`, `zsh_setup/lib/framework.sh`
- Produces: `plugin_list()`, `plugin_add()`, `plugin_remove()`, `plugin_sync()`

- [ ] **Step 1: 实现插件管理模块**

创建 `zsh_setup/lib/plugins.sh`:

```bash
#!/bin/bash
#
# zsh_setup/lib/plugins.sh
# 插件管理模块
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/framework.sh"

# 常用插件列表
declare -A COMMON_PLUGINS=(
    ["zsh-autosuggestions"]="zsh-users/zsh-autosuggestions"
    ["zsh-syntax-highlighting"]="zsh-users/zsh-syntax-highlighting"
    ["zsh-completions"]="zsh-users/zsh-completions"
    ["zsh-history-substring-search"]="zsh-users/zsh-history-substring-search"
    ["zsh-autopair"]="hlissner/zsh-autopair"
    ["zsh-bat"]="fdellwing/zsh-bat"
    ["zsh-fzf"]="unixorn/fzf-zsh-plugin"
    ["zsh-eza"]="z-shell/zsh-eza"
)

# 列出插件
plugin_list() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi
    
    info "当前框架: $framework"
    framework_list_plugins
}

# 添加插件
plugin_add() {
    local plugin_name="$1"
    local plugin_repo="$2"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        echo "常用插件:"
        for name in "${!COMMON_PLUGINS[@]}"; do
            echo "  - $name"
        done
        return 1
    fi
    
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        error "未安装框架，请先安装框架"
        return 1
    fi
    
    # 如果未指定仓库，使用常用插件列表
    if [ -z "$plugin_repo" ] && [ -n "${COMMON_PLUGINS[$plugin_name]}" ]; then
        plugin_repo="${COMMON_PLUGINS[$plugin_name]}"
    fi
    
    load_framework "$framework" || return 1
    
    case "$framework" in
        oh-my-zsh)
            install_plugin_oh_my_zsh "$plugin_name" "$plugin_repo"
            ;;
        prezto)
            enable_module_prezto "$plugin_name"
            ;;
        zinit)
            install_plugin_zinit "$plugin_repo"
            ;;
        sheldon)
            install_plugin_sheldon "$plugin_name" "$plugin_repo"
            ;;
    esac
}

# 移除插件
plugin_remove() {
    local plugin_name="$1"
    
    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi
    
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        error "未安装框架"
        return 1
    fi
    
    load_framework "$framework" || return 1
    
    case "$framework" in
        oh-my-zsh)
            uninstall_plugin_oh_my_zsh "$plugin_name"
            ;;
        prezto)
            disable_module_prezto "$plugin_name"
            ;;
        zinit)
            uninstall_plugin_zinit "$plugin_name"
            ;;
        sheldon)
            uninstall_plugin_sheldon "$plugin_name"
            ;;
    esac
}

# 同步插件
plugin_sync() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi
    
    info "正在同步 $framework 插件..."
    
    case "$framework" in
        oh-my-zsh)
            # 更新 Oh My Zsh
            if [ -d "$HOME/.oh-my-zsh" ]; then
                (cd "$HOME/.oh-my-zsh" && git pull)
            fi
            # 更新自定义插件
            for plugin_dir in "$HOME/.oh-my-zsh/custom/plugins/"*/; do
                [ -d "$plugin_dir" ] && (cd "$plugin_dir" && git pull)
            done
            ;;
        prezto)
            # 更新 Prezto
            if [ -d "${ZDOTDIR:-$HOME}/.zprezto" ]; then
                (cd "${ZDOTDIR:-$HOME}/.zprezto" && git pull && git submodule update --init --recursive)
            fi
            ;;
        zinit)
            # 更新 Zinit 插件
            if [ -d "$HOME/.local/share/zinit" ]; then
                (cd "$HOME/.local/share/zinit/zinit.git" && git pull)
            fi
            ;;
        sheldon)
            # sheldon 会在下次加载时自动更新
            info "sheldon 插件将在下次加载时更新"
            ;;
    esac
    
    success "插件同步完成"
}
```

- [ ] **Step 2: 验证插件管理模块**

```bash
source zsh_setup/lib/plugins.sh
plugin_list
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/lib/plugins.sh
git commit -m "feat(zsh-setup): add plugins management module"
```

---

## Task 8: 实现主题管理模块

**Files:**
- Create: `zsh_setup/lib/themes.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`, `zsh_setup/lib/framework.sh`
- Produces: `theme_list()`, `theme_set()`, `theme_install_p10k()`

- [ ] **Step 1: 实现主题管理模块**

创建 `zsh_setup/lib/themes.sh`:

```bash
#!/bin/bash
#
# zsh_setup/lib/themes.sh
# 主题管理模块
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/framework.sh"

# 列出主题
theme_list() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi
    
    info "当前框架: $framework"
    
    case "$framework" in
        oh-my-zsh)
            echo "可用主题:"
            ls "$HOME/.oh-my-zsh/themes/" 2>/dev/null | sed 's/.zsh-theme$//'
            if [ -d "$HOME/.oh-my-zsh/custom/themes" ]; then
                echo ""
                echo "自定义主题:"
                ls "$HOME/.oh-my-zsh/custom/themes/" 2>/dev/null | sed 's/.zsh-theme$//'
            fi
            ;;
        prezto)
            echo "可用主题:"
            ls "${ZDOTDIR:-$HOME}/.zprezto/modules/prompt/external/themes/" 2>/dev/null
            ;;
        zinit)
            echo "常用主题:"
            echo "  - powerlevel10k"
            echo "  - starship"
            echo "  - pure"
            ;;
        sheldon)
            echo "常用主题:"
            echo "  - powerlevel10k"
            echo "  - starship"
            echo "  - pure"
            ;;
    esac
}

# 设置主题
theme_set() {
    local theme_name="$1"
    
    if [ -z "$theme_name" ]; then
        error "请指定主题名称"
        return 1
    fi
    
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        error "未安装框架"
        return 1
    fi
    
    case "$framework" in
        oh-my-zsh)
            local zshrc="$HOME/.zshrc"
            if [ ! -f "$zshrc" ]; then
                error "未找到 .zshrc 文件"
                return 1
            fi
            
            # 更新主题
            sed -i.bak "s/^ZSH_THEME=.*/ZSH_THEME=\"$theme_name\"/" "$zshrc"
            success "主题已设置为 $theme_name"
            ;;
        prezto)
            local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"
            if [ ! -f "$preztorc" ]; then
                error "未找到 .zpreztorc 文件"
                return 1
            fi
            
            # 更新主题
            sed -i.bak "s/^zstyle ':prezto:module:prompt' theme.*/zstyle ':prezto:module:prompt' theme '$theme_name'/" "$preztorc"
            success "主题已设置为 $theme_name"
            ;;
        zinit)
            info "请在 .zshrc 中添加主题配置"
            echo "示例:"
            echo "  zinit ice depth=1; zinit light romkatv/powerlevel10k"
            ;;
        sheldon)
            info "请在 ~/.config/sheldon/plugins.toml 中添加主题配置"
            ;;
    esac
}

# 安装 Powerlevel10k
theme_install_p10k() {
    local framework
    framework=$(detect_framework)
    
    if [ "$framework" == "none" ]; then
        error "未安装框架"
        return 1
    fi
    
    info "正在安装 Powerlevel10k..."
    
    case "$framework" in
        oh-my-zsh)
            local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
            if [ -d "$theme_dir" ]; then
                warn "Powerlevel10k 已安装"
            else
                git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
            fi
            theme_set "powerlevel10k/powerlevel10k"
            ;;
        prezto)
            local theme_dir="${ZDOTDIR:-$HOME}/.zprezto/modules/prompt/external/themes/powerlevel10k"
            if [ -d "$theme_dir" ]; then
                warn "Powerlevel10k 已安装"
            else
                git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
            fi
            theme_set "powerlevel10k"
            ;;
        zinit)
            local zshrc="$HOME/.zshrc"
            if ! grep -q "powerlevel10k" "$zshrc" 2>/dev/null; then
                echo 'zinit ice depth=1; zinit light romkatv/powerlevel10k' >> "$zshrc"
            fi
            success "Powerlevel10k 已添加到 .zshrc"
            ;;
        sheldon)
            install_plugin_sheldon "powerlevel10k" "romkatv/powerlevel10k"
            ;;
    esac
    
    success "Powerlevel10k 安装完成"
    info "请运行 'p10k configure' 进行配置"
}
```

- [ ] **Step 2: 验证主题管理模块**

```bash
source zsh_setup/lib/themes.sh
theme_list
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/lib/themes.sh
git commit -m "feat(zsh-setup): add themes management module"
```

---

## Task 9: 实现配置管理模块

**Files:**
- Create: `zsh_setup/lib/config.sh`

**Interfaces:**
- Consumes: `zsh_setup/lib/common.sh`
- Produces: `config_backup()`, `config_restore()`, `config_export()`, `config_import()`

- [ ] **Step 1: 实现配置管理模块**

创建 `zsh_setup/lib/config.sh`:

```bash
#!/bin/bash
#
# zsh_setup/lib/config.sh
# 配置管理模块
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 确保配置目录存在
ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
}

# 备份配置
config_backup() {
    ensure_config_dir
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/zsh-backup-$timestamp.tar.gz"
    
    info "正在备份配置..."
    
    # 收集配置文件
    local files_to_backup=()
    
    # .zshrc
    [ -f "$HOME/.zshrc" ] && files_to_backup+=("$HOME/.zshrc")
    
    # Oh My Zsh
    [ -d "$HOME/.oh-my-zsh/custom" ] && files_to_backup+=("$HOME/.oh-my-zsh/custom")
    
    # Prezto
    [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ] && files_to_backup+=("${ZDOTDIR:-$HOME}/.zpreztorc")
    
    # sheldon
    [ -f "$HOME/.config/sheldon/plugins.toml" ] && files_to_backup+=("$HOME/.config/sheldon/plugins.toml")
    
    # Powerlevel10k 配置
    [ -f "$HOME/.p10k.zsh" ] && files_to_backup+=("$HOME/.p10k.zsh")
    
    if [ ${#files_to_backup[@]} -eq 0 ]; then
        warn "没有找到需要备份的配置文件"
        return 0
    fi
    
    # 创建备份
    tar -czf "$backup_file" "${files_to_backup[@]}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        success "配置已备份到: $backup_file"
    else
        error "备份失败"
        return 1
    fi
}

# 恢复配置
config_restore() {
    ensure_config_dir
    
    # 列出可用备份
    local backups=("$BACKUP_DIR"/zsh-backup-*.tar.gz)
    
    if [ ${#backups[@]} -eq 0 ]; then
        warn "没有找到备份文件"
        return 0
    fi
    
    echo "可用备份:"
    for i in "${!backups[@]}"; do
        echo "  $((i+1))) $(basename "${backups[$i]}")"
    done
    
    read -r -p "请选择备份 (1-${#backups[@]}): " choice
    
    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        error "无效选择"
        return 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    
    if ! confirm "确定要从 $(basename "$selected_backup") 恢复配置吗？"; then
        info "取消恢复"
        return 0
    fi
    
    info "正在恢复配置..."
    
    # 备份当前配置
    config_backup
    
    # 恢复配置
    tar -xzf "$selected_backup" -C "$HOME"
    
    if [ $? -eq 0 ]; then
        success "配置已恢复"
    else
        error "恢复失败"
        return 1
    fi
}

# 导出配置
config_export() {
    ensure_config_dir
    
    local export_file="$CONFIG_DIR/zsh-config-export.json"
    
    info "正在导出配置..."
    
    local framework
    framework=$(detect_framework)
    
    # 收集配置信息
    local config_json="{
  \"framework\": \"$framework\",
  \"plugins\": ["
    
    # 收集插件列表
    case "$framework" in
        oh-my-zsh)
            if [ -d "$HOME/.oh-my-zsh/custom/plugins" ]; then
                local plugins=()
                for plugin in "$HOME/.oh-my-zsh/custom/plugins/"*/; do
                    [ -d "$plugin" ] && plugins+=("\"$(basename "$plugin")\"")
                done
                config_json+=$(IFS=,; echo "${plugins[*]}")
            fi
            ;;
        zinit)
            if [ -f "$HOME/.zshrc" ]; then
                local plugins=()
                while IFS= read -r line; do
                    local plugin
                    plugin=$(echo "$line" | sed 's/.*zinit light //' | sed 's/["]//g')
                    [ -n "$plugin" ] && plugins+=("\"$plugin\"")
                done < <(grep "zinit light" "$HOME/.zshrc" 2>/dev/null)
                config_json+=$(IFS=,; echo "${plugins[*]}")
            fi
            ;;
    esac
    
    config_json+="],
  \"theme\": \""
    
    # 收集主题
    case "$framework" in
        oh-my-zsh)
            if [ -f "$HOME/.zshrc" ]; then
                local theme
                theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2)
                config_json+="$theme"
            fi
            ;;
        prezto)
            if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                local theme
                theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}' | tr -d "'")
                config_json+="$theme"
            fi
            ;;
    esac
    
    config_json+="\",
  \"export_date\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}"
    
    echo "$config_json" > "$export_file"
    
    success "配置已导出到: $export_file"
}

# 导入配置
config_import() {
    local import_file="$1"
    
    if [ -z "$import_file" ]; then
        error "请指定导入文件"
        return 1
    fi
    
    if [ ! -f "$import_file" ]; then
        error "文件不存在: $import_file"
        return 1
    fi
    
    info "正在导入配置..."
    
    # 验证 JSON 格式
    if ! command_exists jq; then
        warn "未安装 jq，跳过 JSON 验证"
    else
        if ! jq . "$import_file" > /dev/null 2>&1; then
            error "无效的 JSON 格式"
            return 1
        fi
    fi
    
    # 备份当前配置
    config_backup
    
    # 导入配置
    success "配置已导入"
    info "请根据需要手动调整配置"
}
```

- [ ] **Step 2: 验证配置管理模块**

```bash
source zsh_setup/lib/config.sh
config_backup
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/lib/config.sh
git commit -m "feat(zsh-setup): add config management module"
```

---

## Task 10: 创建模板文件

**Files:**
- Create: `zsh_setup/templates/aliases.zsh`
- Create: `zsh_setup/templates/env.zsh`
- Create: `zsh_setup/templates/p10k.zsh`

**Interfaces:**
- Produces: 模板文件供配置导入使用

- [ ] **Step 1: 创建通用别名模板**

创建 `zsh_setup/templates/aliases.zsh`:

```bash
# ~/.config/zsh_setup/templates/aliases.zsh
# 通用别名模板

# 常用别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# 安全操作
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# 快捷命令
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Git 别名
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph'
alias gd='git diff'

# Docker 别名
alias dk='docker'
alias dkc='docker compose'
alias dkps='docker ps'
alias dki='docker images'

# 系统信息
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias diskinfo='df -h'

# 开发工具
alias py='python3'
alias pip='pip3'
alias serve='python3 -m http.server'
```

- [ ] **Step 2: 创建环境变量模板**

创建 `zsh_setup/templates/env.zsh`:

```bash
# ~/.config/zsh_setup/templates/env.zsh
# 环境变量模板

# 默认编辑器
export EDITOR='vim'
export VISUAL='vim'

# 语言环境
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# Go 环境
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Node.js 环境
export NODE_PATH="$HOME/.node_modules"
export PATH="$NODE_PATH/bin:$PATH"

# Python 环境
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1

# Rust 环境
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"
export PATH="$CARGO_HOME/bin:$PATH"

# Homebrew (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    export HOMEBREW_NO_AUTO_UPDATE=1
fi

# 自定义 PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
```

- [ ] **Step 3: 创建 Powerlevel10k 配置模板**

创建 `zsh_setup/templates/p10k.zsh`:

```bash
# ~/.config/zsh_setup/templates/p10k.zsh
# Powerlevel10k 配置模板
# 运行 'p10k configure' 生成完整配置

# 基础配置
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_PROMPT_ON_NEWLINE=true
POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX=""
POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX="%K{white}%F{black} $POWERLEVEL9K_PROMPT_CHAR %f%k%F{white}%f "

# 左侧提示符元素
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    context
    dir
    vcs
    prompt_char
)

# 右侧提示符元素
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status
    command_execution_time
    background_jobs
    node_version
    go_version
    python_version
    rust_version
    docker_context
    kubecontext
)

# 目录配置
POWERLEVEL9K_DIR_BACKGROUND='4'
POWERLEVEL9K_DIR_FOREGROUND='254'
POWERLEVEL9K_SHORTEN_STRATEGY='truncate_to_unique'
POWERLEVEL9K_SHORTEN_DELIMITER='..'

# Git 配置
POWERLEVEL9K_VCS_CLEAN_BACKGROUND='2'
POWERLEVEL9K_VCS_CLEAN_FOREGROUND='0'
POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND='2'
POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND='0'
POWERLEVEL9K_VCS_MODIFIED_BACKGROUND='3'
POWERLEVEL9K_VCS_MODIFIED_FOREGROUND='0'

# 状态配置
POWERLEVEL9K_STATUS_OK=false
POWERLEVEL9K_STATUS_ERROR_BACKGROUND='1'
POWERLEVEL9K_STATUS_ERROR_FOREGROUND='254'

# 命令执行时间配置
POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND='3'
POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND='0'

# Node.js 配置
POWERLEVEL9K_NODE_VERSION_BACKGROUND='2'
POWERLEVEL9K_NODE_VERSION_FOREGROUND='0'
POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true

# Go 配置
POWERLEVEL9K_GO_VERSION_BACKGROUND='6'
POWERLEVEL9K_GO_VERSION_FOREGROUND='0'
POWERLEVEL9K_GO_VERSION_PROJECT_ONLY=true

# Python 配置
POWERLEVEL9K_PYTHON_VERSION_BACKGROUND='3'
POWERLEVEL9K_PYTHON_VERSION_FOREGROUND='0'
POWERLEVEL9K_PYTHON_VERSION_PROJECT_ONLY=true

# Rust 配置
POWERLEVEL9K_RUST_VERSION_BACKGROUND='208'
POWERLEVEL9K_RUST_VERSION_FOREGROUND='0'
POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=true

# Docker 配置
POWERLEVEL9K_DOCKER_CONTEXT_BACKGROUND='6'
POWERLEVEL9K_DOCKER_CONTEXT_FOREGROUND='0'

# Kubernetes 配置
POWERLEVEL9K_KUBECONTEXT_BACKGROUND='6'
POWERLEVEL9K_KUBECONTEXT_FOREGROUND='0'
```

- [ ] **Step 4: 提交**

```bash
git add zsh_setup/templates/
git commit -m "feat(zsh-setup): add template files"
```

---

## Task 11: 重构主入口 install.sh

**Files:**
- Modify: `zsh_setup/install.sh`

**Interfaces:**
- Consumes: 所有 lib/ 和 frameworks/ 模块
- Produces: 统一的子命令接口

- [ ] **Step 1: 重构 install.sh**

重写 `zsh_setup/install.sh`:

```bash
#!/bin/bash
#
# zsh_setup/install.sh
# Zsh 环境配置管理工具
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共库
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/framework.sh"
source "$SCRIPT_DIR/lib/plugins.sh"
source "$SCRIPT_DIR/lib/themes.sh"
source "$SCRIPT_DIR/lib/config.sh"

# 版本
VERSION="2.0.0"

# 显示帮助
show_help() {
    cat << EOF
Zsh 环境配置管理工具 v${VERSION}

用法: $0 <command> [options]

命令:
  framework              框架管理
    [name]               安装指定框架 (oh-my-zsh, prezto, zinit, sheldon)
    select               交互式选择框架
  
  plugin                 插件管理
    list                 列出已安装插件
    add <name> [repo]    添加插件
    remove <name>        移除插件
    sync                 同步插件更新
  
  theme                  主题管理
    list                 列出可用主题
    set <name>           设置主题
    p10k                 安装 Powerlevel10k
  
  config                 配置管理
    backup               备份配置
    restore              恢复配置
    export               导出配置
    import <file>        导入配置
  
  status                 查看状态
  help                   显示帮助信息
  version                显示版本

示例:
  $0 framework oh-my-zsh   # 安装 Oh My Zsh
  $0 plugin add zsh-autosuggestions
  $0 theme p10k            # 安装 Powerlevel10k
  $0 config backup         # 备份配置
  $0 status                # 查看状态
EOF
}

# 显示版本
show_version() {
    echo "zsh_setup v${VERSION}"
}

# 显示状态
show_status() {
    info "Zsh 环境状态:"
    echo ""
    
    # Zsh 状态
    if command_exists zsh; then
        success "Zsh: 已安装 ($(zsh --version | head -1))"
    else
        warn "Zsh: 未安装"
    fi
    
    echo ""
    
    # 框架状态
    framework_status
    
    echo ""
    
    # 主题状态
    local framework
    framework=$(detect_framework)
    if [ "$framework" != "none" ]; then
        case "$framework" in
            oh-my-zsh)
                if [ -f "$HOME/.zshrc" ]; then
                    local theme
                    theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2)
                    info "当前主题: ${theme:-未设置}"
                fi
                ;;
            prezto)
                if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
                    local theme
                    theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}')
                    info "当前主题: ${theme:-未设置}"
                fi
                ;;
        esac
    fi
    
    echo ""
    
    # 配置备份状态
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count
        backup_count=$(ls -1 "$BACKUP_DIR"/zsh-backup-*.tar.gz 2>/dev/null | wc -l)
        info "配置备份: ${backup_count} 个"
    else
        info "配置备份: 无"
    fi
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        framework)
            if [ -z "$1" ] || [ "$1" == "select" ]; then
                framework_select
            else
                framework_install "$1"
            fi
            ;;
        plugin)
            local subcommand="${1:-list}"
            shift || true
            case "$subcommand" in
                list) plugin_list ;;
                add) plugin_add "$1" "$2" ;;
                remove) plugin_remove "$1" ;;
                sync) plugin_sync ;;
                *) error "未知命令: plugin $subcommand"; show_help; exit 1 ;;
            esac
            ;;
        theme)
            local subcommand="${1:-list}"
            shift || true
            case "$subcommand" in
                list) theme_list ;;
                set) theme_set "$1" ;;
                p10k) theme_install_p10k ;;
                *) error "未知命令: theme $subcommand"; show_help; exit 1 ;;
            esac
            ;;
        config)
            local subcommand="${1:-help}"
            shift || true
            case "$subcommand" in
                backup) config_backup ;;
                restore) config_restore ;;
                export) config_export ;;
                import) config_import "$1" ;;
                *) error "未知命令: config $subcommand"; show_help; exit 1 ;;
            esac
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        version|--version|-v)
            show_version
            ;;
        *)
            error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 如果直接运行脚本（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 2: 验证主入口**

```bash
chmod +x zsh_setup/install.sh
./zsh_setup/install.sh help
./zsh_setup/install.sh status
```

- [ ] **Step 3: 提交**

```bash
git add zsh_setup/install.sh
git commit -m "refactor(zsh-setup): rewrite install.sh with modular architecture"
```

---

## Task 12: 更新文档

**Files:**
- Modify: `zsh_setup/README.md`

**Interfaces:**
- Produces: 更新的模块文档

- [ ] **Step 1: 更新 README.md**

重写 `zsh_setup/README.md`:

```markdown
# zsh_setup - Zsh 环境配置管理工具

多框架 Zsh 环境配置管理工具，支持 Oh My Zsh、Prezto、Zinit、sheldon 四大框架。

## 功能特性

- 🎯 **多框架支持** - 支持 Oh My Zsh、Prezto、Zinit、sheldon
- 🔌 **插件管理** - 统一的插件安装、卸载、同步接口
- 🎨 **主题管理** - 主题切换、Powerlevel10k 安装
- ⚙️ **配置管理** - 配置备份、恢复、导出、导入

## 快速开始

```bash
# 查看帮助
./zsh_setup/install.sh help

# 安装框架（交互式选择）
./zsh_setup/install.sh framework

# 直接安装 Oh My Zsh
./zsh_setup/install.sh framework oh-my-zsh

# 查看状态
./zsh_setup/install.sh status
```

## 子命令

### 框架管理

```bash
./zsh_setup/install.sh framework              # 交互式选择框架
./zsh_setup/install.sh framework oh-my-zsh    # 安装 Oh My Zsh
./zsh_setup/install.sh framework prezto       # 安装 Prezto
./zsh_setup/install.sh framework zinit        # 安装 Zinit
./zsh_setup/install.sh framework sheldon      # 安装 sheldon
```

### 插件管理

```bash
./zsh_setup/install.sh plugin list            # 列出已安装插件
./zsh_setup/install.sh plugin add <name>      # 添加插件
./zsh_setup/install.sh plugin remove <name>   # 移除插件
./zsh_setup/install.sh plugin sync            # 同步插件更新
```

### 主题管理

```bash
./zsh_setup/install.sh theme list             # 列出可用主题
./zsh_setup/install.sh theme set <name>       # 设置主题
./zsh_setup/install.sh theme p10k             # 安装 Powerlevel10k
```

### 配置管理

```bash
./zsh_setup/install.sh config backup          # 备份配置
./zsh_setup/install.sh config restore         # 恢复配置
./zsh_setup/install.sh config export          # 导出配置
./zsh_setup/install.sh config import <file>   # 导入配置
```

## 支持的框架

| 框架 | 特点 | 适合人群 |
|------|------|----------|
| **Oh My Zsh** | 最流行，插件丰富，社区活跃 | 新手，喜欢丰富功能 |
| **Prezto** | 轻量级，模块化，性能好 | 追求简洁，有一定经验 |
| **Zinit** | 性能极佳，异步加载，Turbo 模式 | 追求速度，高级用户 |
| **sheldon** | Rust 编写，速度快，配置简洁 | 现代化，喜欢简洁配置 |

## 支持的插件

- zsh-autosuggestions - 命令自动建议
- zsh-syntax-highlighting - 语法高亮
- zsh-completions - 额外补全
- zsh-history-substring-search - 历史子串搜索
- zsh-autopair - 自动括号配对
- zsh-bat - bat 集成
- zsh-fzf - fzf 集成
- zsh-eza - eza 替代 ls

## 目录结构

```
zsh_setup/
├── install.sh              # 主入口
├── lib/
│   ├── common.sh          # 公共函数库
│   ├── framework.sh       # 框架抽象层
│   ├── plugins.sh         # 插件管理
│   ├── themes.sh          # 主题管理
│   └── config.sh          # 配置管理
├── frameworks/
│   ├── oh-my-zsh.sh       # Oh My Zsh 适配器
│   ├── prezto.sh          # Prezto 适配器
│   ├── zinit.sh           # Zinit 适配器
│   └── sheldon.sh         # sheldon 适配器
└── templates/
    ├── aliases.zsh        # 别名模板
    ├── env.zsh            # 环境变量模板
    └── p10k.zsh           # Powerlevel10k 模板
```

## 常见问题

### 如何切换框架？

1. 备份当前配置：`./zsh_setup/install.sh config backup`
2. 安装新框架：`./zsh_setup/install.sh framework <name>`

### 如何迁移配置？

1. 在旧机器导出配置：`./zsh_setup/install.sh config export`
2. 复制导出文件到新机器
3. 在新机器导入配置：`./zsh_setup/install.sh config import <file>`

### 插件安装后不生效？

请运行 `source ~/.zshrc` 或重启终端以加载新插件。
```

- [ ] **Step 2: 提交**

```bash
git add zsh_setup/README.md
git commit -m "docs(zsh-setup): update README with new features"
```

---

## Task 13: 测试和验证

**Files:**
- Test: 运行所有子命令验证功能

- [ ] **Step 1: 测试框架管理**

```bash
# 测试帮助信息
./zsh_setup/install.sh help

# 测试状态查看
./zsh_setup/install.sh status
```

- [ ] **Step 2: 测试插件管理**

```bash
# 测试插件列表
./zsh_setup/install.sh plugin list
```

- [ ] **Step 3: 测试主题管理**

```bash
# 测试主题列表
./zsh_setup/install.sh theme list
```

- [ ] **Step 4: 测试配置管理**

```bash
# 测试配置备份
./zsh_setup/install.sh config backup

# 测试配置导出
./zsh_setup/install.sh config export
```

- [ ] **Step 5: 提交测试结果**

```bash
git add -A
git commit -m "test(zsh-setup): verify all subcommands work correctly"
```

---

## 完成

所有任务完成后，运行最终验证：

```bash
./zsh_setup/install.sh help
./zsh_setup/install.sh status
```

**重构完成！**
