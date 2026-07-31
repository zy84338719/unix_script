# 设计：npm/yarn/pnpm 换源加速模块（npm-mirror）

- 日期：2026-07-31
- 分支：feat/bootstrap-one-line-install
- 状态：已确认，待实现

## 1. 背景与目标

项目（unix_script）是一个 Linux + macOS 装机/环境配置脚本集合，已通过 `nvm` 模块支持安装 Node.js，但缺少对 **npm / yarn / pnpm** 这三类包管理器的 registry 换源加速配置。在国内网络环境下，默认官方源 `https://registry.npmjs.org/` 速度慢、易超时，需要一键切换到国内镜像。

**目标**：新建独立模块 `npm-mirror`，一键为已安装的 npm/yarn/pnpm 配置国内 registry，默认淘宝（npmmirror），并可随时切换或还原官方源。

**非目标**：不安装 Node.js 本身（由 `nvm` 负责）；不管理全局包；不做发布（`npm publish`）相关配置。

## 2. 架构

作为项目根目录下的独立模块，与 `nvm/`、`docker/`、`sys-setup/` 同级，遵循统一的模块规范：

```
npm-mirror/
├── install.sh      # 子命令式入口：install | uninstall | status | help
└── README.md       # 模块说明
```

- 复用 `lib/common.sh` 的工具函数：`info/success/warn/error/header/menu/yes_no/detect_os/command_exists/check_commands`。
- 由主 `install.sh` 通过子菜单 `manage_npm_mirror` 路由（参照 `manage_docker`），底层调用 `run_in_dir npm-mirror install.sh <subcommand> [args]`。
- 平台：Linux + macOS（由 `detect_os` 保证，配置写入用户家目录，无需 sudo）。

## 3. 内置源清单

| 名称 | registry URL | 说明 |
|------|--------------|------|
| `taobao` | `https://registry.npmmirror.com` | **默认**，淘宝/阿里云，国内最常用 |
| `tencent` | `https://mirrors.cloud.tencent.com/npm/` | 腾讯云 |
| `huawei` | `https://mirrors.huaweicloud.com/repository/npm/` | 华为云 |
| `npm` | `https://registry.npmjs.org/` | 官方源（用于还原） |

源清单以关联数组形式定义在 `install.sh` 顶部，便于扩展。用户亦可在菜单/参数中自定义输入完整 URL。

## 4. 子命令

入口：`npm-mirror/install.sh {install|uninstall|status|help} [source-key|url]`

### 4.1 `install [source]`
- 不带参数 → 进入交互式源选择菜单（列出 4 个内置源 + 自定义输入）。
- 带参数 → `source` 为内置 key（taobao/tencent/huawei/npm）或合法 URL（以 `http://`/`https://` 开头）。
- 流程：
  1. `detect_os` + 检测至少一个目标包管理器（npm/yarn/pnpm）已安装，否则报错退出。
  2. 调用 `check_nrm_conflict`：若发现 `nrm`/`cnpm`/`nvs` 等源管理工具，给出 warn 提示（不阻断，因为最终都会写 PM 配置，但提醒用户可能存在覆盖）。
  3. 对每个已安装的 PM 调用对应配置函数（见 §5），写入 **用户级** 配置。
  4. 汇总打印：每个 PM 配置后的 registry。
- 幂等：重复执行视为「切换源」，直接覆盖。

### 4.2 `uninstall`
- 将 npm/yarn/pnpm 的 registry 还原为官方 `https://registry.npmjs.org/`。
- 用 `yes_no` 二次确认。
- 对未安装的 PM 跳过。

### 4.3 `status`
- 逐一显示已安装的 npm/yarn/pnpm 的当前 registry（未安装的 PM 显示「未安装」）。
- 额外提示：若当前源非官方源，标注「已换源」。

### 4.4 `help`
- 打印用法。

## 5. 各包管理器配置实现

统一原则：写入 **用户级** 配置（`--location=user` 或家目录配置文件），不污染系统全局，无需 sudo。

### 5.1 npm
```sh
npm config set registry "<url>" --location=user
```
- 验证：`npm config get registry`

### 5.2 yarn
需区分大版本：
- **v1**（`.yarnrc`）：`yarn config set registry "<url>"`
- **v2+ / Berry**（`.yarnrc.yml`）：`yarn config set npmRegistryServer "<url>"`（yarn 2+ 会自动写 `.yarnrc.yml`）
- 通过 `yarn --version` 判断主版本号选择分支。

### 5.3 pnpm
```sh
pnpm config set registry "<url>"
```
- 验证：`pnpm config get registry`

## 6. nrm 等冲突检测（`check_nrm_conflict`）

扫描 PATH 中是否存在 `nrm`、`cnpm`、`nvs`：
- 若存在 `nrm`：`warn` 提示「检测到 nrm，它可能覆盖本模块写入的 registry；如需统一管理建议卸载 nrm 或仅用其中之一」。
- 若存在 `cnpm`：`info` 提示「cnpm 自带淘宝源，通常无需换源」。
- **不阻断流程**，仅提示。

## 7. 集成进主 `install.sh`

### 7.1 主菜单
在 `show_main_menu` 的「开发环境配置」分区，nvm 项之后新增：
```
  XX) npm-mirror         - npm/yarn/pnpm 换源加速（默认淘宝源）
```
菜单序号随插入位置顺延（预计为新增项，需同步调整后续项编号或新增为 26）。

### 7.2 状态函数
```sh
status_npm_mirror_module() { run_in_dir npm-mirror install.sh status; }
```
并在 `show_installed_services` 中新增一行展示。

### 7.3 子菜单 `manage_npm_mirror`
参照 `manage_docker` 结构：
```
npm-mirror 管理（换源加速）
当前状态: <status>
  1) 换源（默认淘宝 npmmirror）
  2) 选择其他源（腾讯/华为/官方/自定义）
  3) 还原官方源
  0) 返回主菜单
```

### 7.4 路由
`interactive_main` 的 case 中对应分支调用 `manage_npm_mirror`。

## 8. 错误处理

- 任一目标 PM 均未安装：`error` 后退出码 1（`install` 子命令）。
- 配置写入失败（`npm config set` 非零返回）：`error` 提示具体 PM，退出码 1。
- yarn 版本探测失败：fallback 按 v1 处理并 `warn` 提示。
- 不支持的平台（非 linux/darwin）：`detect_os` 已有保护。

## 9. 测试

参照 `tests/ci_run.sh` 现有「routing」断言风格：
- 断言主菜单包含 `npm-mirror` 项。
- 断言 `manage_npm_mirror` 函数存在并能被路由到。
- 断言 `npm-mirror/install.sh` 的 `status`/`help` 子命令可执行且退出码为 0。
- 不在 CI 中真实写配置（避免污染 runner 环境），仅做路由/语法/帮助文本断言。

## 10. 文档

- 新增 `npm-mirror/README.md`：用途、子命令、源清单、示例。
- 更新根 `README.md` 的模块服务表，新增 npm-mirror 一行。

## 11. 不做（YAGNI）

- 不支持 bun（本次需求未提及，留待后续）。
- 不做 `--registry` 全局环境变量注入（PM 配置已足够）。
- 不管理 scope 级 registry（`@scope:registry`）。
