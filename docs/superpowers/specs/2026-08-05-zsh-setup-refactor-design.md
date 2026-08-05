# zsh_setup 模块化重构设计文档

## 概述

将现有的 `zsh_setup` 模块重构为模块化架构，支持多个 Zsh 框架（Oh My Zsh、Prezto、Zinit、sheldon），提供统一的插件管理、主题管理和配置管理功能。

## 设计目标

1. **模块化架构** - 代码按功能拆分，职责清晰
2. **多框架支持** - 支持 Oh My Zsh、Prezto、Zinit、sheldon
3. **统一接口** - 所有框架使用相同的子命令接口
4. **配置管理** - 支持备份、恢复、导出、导入配置
5. **可扩展性** - 易于添加新框架或插件

## 目录结构

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

## 子命令设计

### 框架管理

```bash
./zsh_setup/install.sh framework              # 交互式选择框架
./zsh_setup/install.sh framework omz          # 安装 Oh My Zsh
./zsh_setup/install.sh framework prezto       # 安装 Prezto
./zsh_setup/install.sh framework zinit        # 安装 Zinit
./zsh_setup/install.sh framework sheldon      # 安装 sheldon
```

### 插件管理

```bash
./zsh_setup/install.sh plugin list            # 列出已安装插件
./zsh_setup/install.sh plugin add <name>      # 添加插件
./zsh_setup/install.sh plugin remove <name>   # 移除插件
./zsh_setup/install.sh plugin sync            # 同步插件配置
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

### 状态查看

```bash
./zsh_setup/install.sh status                 # 查看整体状态
./zsh_setup/install.sh status --json          # JSON 格式输出
```

## 框架支持

### 各框架特点

| 框架 | 特点 | 适合人群 |
|------|------|----------|
| **Oh My Zsh** | 最流行，插件丰富，社区活跃 | 新手，喜欢丰富功能 |
| **Prezto** | 轻量级，模块化，性能好 | 追求简洁，有一定经验 |
| **Zinit** | 性能极佳，异步加载，Turbo 模式 | 追求速度，高级用户 |
| **sheldon** | Rust 编写，速度快，配置简洁 | 现代化，喜欢简洁配置 |

### 各框架安装方式

- **Oh My Zsh**: `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`
- **Prezto**: `git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"`
- **Zinit**: `bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"`
- **sheldon**: `curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon`

## 插件管理

### 支持的插件列表

| 插件名称 | 描述 | Oh My Zsh | Prezto | Zinit | sheldon |
|----------|------|:----------:|:------:|:-----:|:-------:|
| zsh-autosuggestions | 命令自动建议 | ✅ | ✅ | ✅ | ✅ |
| zsh-syntax-highlighting | 语法高亮 | ✅ | ✅ | ✅ | ✅ |
| zsh-completions | 额外补全 | ✅ | ✅ | ✅ | ✅ |
| zsh-history-substring-search | 历史子串搜索 | ✅ | ✅ | ✅ | ✅ |
| zsh-autopair | 自动括号配对 | ✅ | ✅ | ✅ | ✅ |
| zsh-bat | bat 集成 | ✅ | ✅ | ✅ | ✅ |
| zsh-fzf | fzf 集成 | ✅ | ✅ | ✅ | ✅ |
| zsh-eza | eza 替代 ls | ✅ | ✅ | ✅ | ✅ |

### 插件安装方式

- **Oh My Zsh**: `git clone` 到 `$ZSH_CUSTOM/plugins/`
- **Prezto**: `git clone` 到 `${ZDOTDIR:-$HOME}/.zprezto/contrib/`
- **Zinit**: `zinit light <plugin>` 或 `zinit ice wait lucid; zinit light <plugin>`
- **sheldon**: 在 `~/.config/sheldon/plugins.toml` 中添加配置

## 主题管理

### 支持的主题

- **Powerlevel10k** - 功能强大，配置丰富
- **Agnoster** - 经典主题，美观
- **robbyrussell** - Oh My Zsh 默认主题
- **Pure** - 简洁，适合 Prezto
- **Starship** - 跨 shell 主题

### 主题安装方式

- **Oh My Zsh**: `git clone` 到 `$ZSH_CUSTOM/themes/`
- **Prezto**: 使用内置主题或修改 `${ZDOTDIR:-$HOME}/.zpreztorc`
- **Zinit**: `zinit ice depth=1; zinit light romkatv/powerlevel10k`
- **sheldon**: 在配置文件中添加主题插件

## 配置管理

### 备份配置

- 备份位置：`~/.config/zsh_setup/backups/`
- 备份文件命名：`zsh-backup-YYYYMMDD-HHMMSS.tar.gz`
- 备份内容：
  - `.zshrc` 配置文件
  - 框架配置文件
  - 插件列表
  - 主题配置

### 恢复配置

- 从备份恢复完整配置
- 选择性恢复（主题/插件/别名等）
- 自动检测框架兼容性

### 导出/导入配置

- 导出格式：JSON
- 导出内容：
  - 框架类型
  - 插件列表
  - 主题配置
  - 自定义别名
  - 环境变量

- 导入功能：
  - 验证配置文件格式
  - 自动安装缺失的框架/插件
  - 合并或覆盖现有配置

## 实现步骤

### 第一阶段：基础架构

1. **重构目录结构**
   - 创建 `lib/`、`frameworks/`、`templates/` 目录
   - 移动和重构现有代码

2. **实现公共函数库** (`lib/common.sh`)
   - 颜色输出函数
   - 日志函数
   - 命令检测函数
   - 系统检测函数

3. **实现框架抽象层** (`lib/framework.sh`)
   - 统一的框架接口
   - 框架检测和切换
   - 框架状态查询

### 第二阶段：框架适配器

4. **实现 Oh My Zsh 适配器** (`frameworks/oh-my-zsh.sh`)
   - 安装/卸载
   - 插件管理
   - 主题管理
   - 配置管理

5. **实现 Prezto 适配器** (`frameworks/prezto.sh`)
   - 安装/卸载
   - 模块管理
   - 主题管理
   - 配置管理

6. **实现 Zinit 适配器** (`frameworks/zinit.sh`)
   - 安装/卸载
   - 插件管理
   - 主题管理
   - 配置管理

7. **实现 sheldon 适配器** (`frameworks/sheldon.sh`)
   - 安装/卸载
   - 插件管理
   - 主题管理
   - 配置管理

### 第三阶段：管理功能

8. **实现插件管理** (`lib/plugins.sh`)
   - 插件列表查询
   - 插件安装/卸载
   - 插件同步
   - 插件兼容性检查

9. **实现主题管理** (`lib/themes.sh`)
   - 主题列表查询
   - 主题安装/切换
   - 主题配置
   - Powerlevel10k 安装

10. **实现配置管理** (`lib/config.sh`)
    - 配置备份
    - 配置恢复
    - 配置导出
    - 配置导入

### 第四阶段：集成和测试

11. **更新主入口** (`install.sh`)
    - 子命令路由
    - 参数解析
    - 帮助信息

12. **添加模板文件** (`templates/`)
    - 通用别名模板
    - 环境变量模板
    - Powerlevel10k 配置模板

13. **测试**
    - 单元测试
    - 集成测试
    - 跨平台测试

14. **文档更新**
    - 更新 README.md
    - 添加使用示例
    - 添加故障排除指南

## 状态查询

### 状态输出格式

```bash
# 默认格式
./zsh_setup/install.sh status

# 输出示例
✅ Zsh 已安装
✅ Oh My Zsh 已安装
✅ 插件: zsh-autosuggestions, zsh-syntax-highlighting
✅ 主题: powerlevel10k
⚠️  配置未备份

# JSON 格式
./zsh_setup/install.sh status --json

# 输出示例
{
  "zsh": {
    "installed": true,
    "version": "5.9"
  },
  "framework": {
    "type": "oh-my-zsh",
    "installed": true,
    "version": "5.9"
  },
  "plugins": [
    {"name": "zsh-autosuggestions", "installed": true},
    {"name": "zsh-syntax-highlighting", "installed": true}
  ],
  "theme": {
    "name": "powerlevel10k",
    "installed": true
  },
  "config": {
    "last_backup": "2026-08-05T10:30:00Z"
  }
}
```

## 错误处理

### 错误类型

1. **框架安装失败**
   - 网络连接问题
   - 依赖缺失
   - 权限不足

2. **插件安装失败**
   - 插件不存在
   - 仓库克隆失败
   - 兼容性问题

3. **配置管理失败**
   - 备份目录不可写
   - 配置文件损坏
   - 导入格式错误

### 错误处理策略

- 提供清晰的错误信息
- 提供解决方案建议
- 支持重试机制
- 记录错误日志

## 向后兼容性

**不保持向后兼容性**。这是一个完全重构，现有用户需要：
1. 重新安装 zsh_setup 模块
2. 迁移现有配置（提供迁移脚本）

## 未来扩展

1. **插件市场** - 在线浏览和安装插件
2. **配置分享** - 社区配置模板
3. **性能优化** - 插件懒加载
4. **自动更新** - 插件和框架自动更新
