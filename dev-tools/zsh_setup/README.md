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

# 非交互默认安装（zsh + oh-my-zsh + 基础插件；UXS_CONFIG_FRAMEWORK/UXS_CONFIG_THEME 可调）
./zsh_setup/install.sh install

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
