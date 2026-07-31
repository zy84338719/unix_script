# 设计：dev-mirror 统一开发换源模块

- 日期：2026-07-31
- 分支：main
- 状态：已确认，待实现
- 关联：取代并删除现有 `npm-mirror` 模块

## 1. 背景与目标

项目已有 `npm-mirror`（npm/yarn/pnpm 换源）和 `sys-setup`（apt/yum 系统软件源换源）。但开发场景下还有多个语言生态需要换源加速：**Go (GOPROXY)、Rust (cargo)、Python (pip)**，目前缺失。

**目标**：新建统一模块 `dev-mirror`，作为「开发语言生态换源」的单一入口，覆盖 **npm + Go + Rust + Python** 四大生态，一键为已安装的工具链配置国内镜像。同时**完全合并并删除**现有 `npm-mirror`（其逻辑迁入 dev-mirror 的 npm 分支）。

**非目标**：
- 不管理系统软件源（apt/yum/brew）——那是 `sys-setup` 的职责。
- 不安装语言运行时本身（Node 由 nvm、Go 由官方包、Rust 由 rustup、Python 由 pyenv/系统）。
- 不做发布（publish）相关配置。

## 2. 架构

独立模块 `dev-mirror/`，与 `sys-setup/`、`nvm/` 同级：

```
dev-mirror/
├── install.sh      # 子命令式入口：install | uninstall | status | help
└── README.md
```

- 复用 `lib/common.sh`（`info/success/warn/error/header/menu/yes_no/detect_os/command_exists/check_commands`）。
- **不使用关联数组**（兼容 macOS 自带 bash 3.2），源清单用 `case` 分发。
- 由主 `install.sh` 子菜单 `manage_dev_mirror` 路由（参照 `manage_docker`、原 `manage_npm_mirror`）。
- 平台：Linux + macOS（写用户级配置，无需 sudo）。

## 3. 子命令设计

入口：`dev-mirror/install.sh {install|uninstall|status|help} [ecosystem] [source]`

采用**两级参数**：先选生态，再选源（与 sys-setup 的 `all`/`mirror` 风格一致）。

```
install [ecosystem] [source]   # ecosystem: npm|go|rust|python|all（默认 all=交互选）
uninstall [ecosystem]          # 还原官方源（默认交互选生态）
status                         # 显示所有生态当前配置
help
```

### 3.1 `install [ecosystem] [source]`
- 交互式（无参）：先选生态（npm/go/rust/python/全部），再选该生态的源。
- 非交互：`install go goproxy-cn` 直接配置。
- `all` → 逐一处理每个已安装的生态（用其默认推荐源或交互）。

### 3.2 `uninstall [ecosystem]`
- 交互式选生态，将该生态还原为官方源。
- 用 `yes_no` 二次确认。

### 3.3 `status`
- 表格化显示所有生态当前镜像配置 + 是否非官方源标注。

### 3.4 `help`

## 4. 各生态实现

### 4.1 npm（迁移自 npm-mirror）
- **工具**：npm、yarn（v1 `.yarnrc` / v2+ `.yarnrc.yml`）、pnpm
- **配置**：`npm config set registry <url> --location=user`
- **默认源**：淘宝 `https://registry.npmmirror.com`
- **官方源**：`https://registry.npmjs.org/`
- **可选源**：淘宝 / 腾讯 / 华为 / 官方 / 自定义
- **冲突检测**：nrm/cnpm 提示（保留原有逻辑）

### 4.2 Go (GOPROXY)
- **工具**：go（检测 `command -v go`）
- **配置方式**：`go env -w GOPROXY=<url>,direct`（写 `~/Library/Application Support/go/env` on macOS / `~/.config/go/env` on Linux，go 1.13+ 原生支持，无需改 .bashrc）
- **默认源**：`https://goproxy.cn`（七牛，国内最常用）
- **官方源**：`https://proxy.golang.org,direct`
- **可选源**：
  | key | URL |
  |-----|-----|
  | `goproxy-cn` | `https://goproxy.cn` (七牛，默认) |
  | `aliyun` | `https://mirrors.aliyun.com/goproxy/` |
  | `goproxy.io` | `https://goproxy.io` |
  | `official` | `https://proxy.golang.org,direct` (还原) |
- **额外优化**：同时设 `GOSUMDB=sum.golang.org`（默认不变）；可选设 `GO111MODULE=on`（现代 go 默认已开，不强制）。
- **验证**：`go env GOPROXY`

### 4.3 Rust (cargo)
- **工具**：cargo（检测 `command -v cargo`）
- **配置文件**：`~/.cargo/config.toml`（新版）或 `~/.cargo/config`（旧版）；优先写 `config.toml`，若存在旧 `config` 则在其上追加。
- **配置内容**（TOML，replace-with 模式）：
  ```toml
  [source.crates-io]
  replace-with = "mirror"

  [source.mirror]
  registry = "sparse+<url>"
  ```
  注：现代 cargo（1.68+）推荐 `sparse+` 协议的稀疏索引，速度更快。
- **默认源**：清华 `https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/`（或中科大）
- **官方源**：删除 `replace-with` 配置块（还原为 crates.io 默认）
- **可选源**：
  | key | URL（sparse 索引）|
  |-----|-----|
  | `tuna` | `https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/` (清华，默认) |
  | `ustc` | `https://mirrors.ustc.edu.cn/crates.io-index/` (中科大) |
  | `sjtu` | `https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/` (上交) |
  | `rsproxy` | `https://rsproxy.cn/index/` (字节) |
- **还原**：从 config 中移除 `[source.crates-io]` 的 `replace-with` 与 `[source.mirror]` 段。
- **实现要点**：用 sed/awk 编辑 TOML 较脆弱，采用「读出非本模块管理的行 + 重写本模块管理的段」策略，段间用标记注释包裹便于幂等更新（如 `# >>> dev-mirror >>>` / `# <<< dev-mirror <<<`）。

### 4.4 Python (pip)
- **工具**：pip / pip3（检测 `command -v pip3` 优先，回退 `pip`）
- **配置文件**：
  - Linux：`~/.pip/pip.conf` 或 `~/.config/pip/pip.conf`
  - macOS：`~/Library/Application Support/pip/pip.conf` 或 `~/.pip/pip.conf`
  - 统一策略：优先 `~/.config/pip/pip.conf`（XDG，跨平台兼容），不存在则创建。
- **配置内容**（INI）：
  ```ini
  [global]
  index-url = <url>
  trusted-host = <host>   # 仅 http 源需要，https 源无需
  ```
- **默认源**：清华 `https://pypi.tuna.tsinghua.edu.cn/simple`
- **官方源**：`https://pypi.org/simple`
- **可选源**：
  | key | URL |
  |-----|-----|
  | `tuna` | `https://pypi.tuna.tsinghua.edu.cn/simple` (清华，默认) |
  | `aliyun` | `https://mirrors.aliyun.com/pypi/simple/` |
  | `ustc` | `https://pypi.mirrors.ustc.edu.cn/simple/` |
  | `tencent` | `https://mirrors.cloud.tencent.com/pypi/simple` |
  | `official` | `https://pypi.org/simple` (还原) |
- **验证**：`pip3 config get global.index-url`（pip 10+ 支持 `pip config`）

## 5. 代码组织（install.sh 内部）

为保持单文件可读，按生态拆分为独立函数组，共享 `preflight`/`prompt`/`apply` 调度：

```
# 通用
preflight_ecosystem()      # 检测某生态工具是否已装
prompt_ecosystem()         # 交互选生态
prompt_source()            # 交互选源（按生态动态生成选项）

# 每个生态
config_npm <url>
config_go <url>
config_rust <url>
config_python <url>
status_npm / status_go / status_rust / status_python
uninstall_npm / uninstall_go / uninstall_rust / uninstall_python

# 源清单（case 分发，每生态一组）
resolve_source_<eco> <key>   # key -> url
label_source_<eco> <key>     # key -> 友好名
```

## 6. 集成进主 install.sh

### 6.1 替换 npm-mirror 为 dev-mirror
- 主菜单项 15 文案改为：`dev-mirror - 开发换源加速（npm/Go/Rust/Python）`
- `manage_npm_mirror` → `manage_dev_mirror`（子菜单第一层选生态，第二层选源/还原）
- `status_npm_mirror_module` → `status_dev_mirror_module`
- 卸载菜单项 24 文案改为：`还原开发镜像源（npm/Go/Rust/Python）`
- `dispatch_module`：`npm-mirror` 别名保留（向后兼容）→ 路由到 dev-mirror；新增 `dev-mirror` 主名
- `--list`：`npm-mirror` → `dev-mirror`

### 6.2 状态页
`show_installed_services` 中 `npm-mirror:` 行改为 `dev-mirror:`，调用 `status_dev_mirror_module`。

### 6.3 删除 npm-mirror/
删除 `npm-mirror/install.sh`、`npm-mirror/README.md` 及空目录。

## 7. 错误处理
- 任一目标生态工具均未安装：`error` 退出 1（install 时）。
- 配置写入失败：`error` 提示具体生态，退出 1。
- TOML/INI 编辑采用标记段 + 原子重写，失败时回滚（先写临时文件再 mv）。
- go < 1.13（不支持 `go env -w`）：`warn` 提示并 fallback 到写 `.bashrc` 的 `export GOPROXY=...`。

## 8. 测试
参照 `tests/ci_run.sh`：
- `new_mods` 数组：`npm-mirror` → `dev-mirror`。
- 路由断言：主菜单含 `dev-mirror`、含 `manage_dev_mirror`/`status_dev_mirror_module`。
- 子命令：`dev-mirror/install.sh status`、`help` 退出 0；非法源标识退出 1。
- 不在 CI 真实写配置，仅路由/语法/帮助文本断言。

## 9. 文档
- 新增 `dev-mirror/README.md`（含四大生态源清单、用法示例）。
- 更新根 `README.md` 模块表：`npm-mirror` 行 → `dev-mirror`；可用模块名同步更新。
- CHANGELOG 记录此次扩展 + npm-mirror 合并。

## 10. 不做（YAGNI）
- 不支持 PHP/composer、Ruby/bundler、Java/maven（本次未提及，留待后续按需加）。
- 不做 `all` 一键换全部的「激进默认」（保留交互逐步确认，避免误改用户全部配置）；但提供 `install all <默认源>` 非交互批量入口。
- 不管理 conda（conda 换源机制不同，单独 `.condarc`，留待后续）。
