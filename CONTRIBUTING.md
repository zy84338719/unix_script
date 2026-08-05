# 贡献指南

感谢你考虑为 unix_script 贡献代码！请遵循以下约定，以保持脚本库的一致性与可维护性。

## 仓库结构

```
.
├── install.sh                  # 统一安装菜单（交互 + 非交互）
├── uninstall.sh                # 一键卸载入口
├── bootstrap.sh                # 一行安装引导
├── lib/
│   ├── common.sh               # 公共函数库（颜色/打印/检测/服务管理）
│   ├── core.sh                 # 框架核心（run_in_dir / run_submenu）
│   ├── registry.sh             # 模块注册表（.manifest 扫描/查询）
│   └── ...
├── services/                   # 服务类模块（17 个）
├── essentials/                 # 装机必备模块（6 个）
├── dev-tools/                  # 开发环境模块（12 个）
├── ai-tools/                   # AI 工具模块（3 个）
├── sys-tools/                  # 系统工具模块（14 个）
│   └── <模块名>/
│       ├── install.sh          # 模块入口
│       ├── .manifest           # 元数据
│       └── README.md           # 模块文档
├── scripts/                    # 辅助脚本（check_issues.sh 等）
├── tests/                      # CI 测试
├── completions/                # Shell 自动补全
└── .github/workflows/ci.yml
```

## 新增一个模块

**推荐方式**：使用脚手架命令自动生成模板：

```bash
./install.sh scaffold myservice --category 服务 --label "我的服务"
```

生成后编辑 `services/myservice/install.sh` 实现具体逻辑即可。

**手动方式**：

1. 在对应分类目录下创建模块目录，例如 `services/myservice/`。
   - `services/` — 服务类
   - `essentials/` — 装机必备
   - `dev-tools/` — 开发环境
   - `ai-tools/` — AI 工具
   - `sys-tools/` — 系统工具
2. 编写 `services/myservice/install.sh`：
   - 顶部 `set -e`，并 `source` 公共库：
     ```bash
     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
     # shellcheck source=../../lib/common.sh
     source "$SCRIPT_DIR/../../lib/common.sh"
     ```
   - 使用统一的打印函数：`info` / `success` / `warn` / `error`（**不要**自定义颜色或重复定义）。
   - 实现 `install`、`uninstall`、`status`、`help` 子命令，并通过 `main "$@"` 分发。
   - 做平台检测（`detect_os`）、依赖检查（`check_commands`）、权限检查（`require_sudo`）。
   - Linux 用 systemd、macOS 用 launchd 管理服务（可复用 `service_start`/`service_stop`）。
3. 创建 `services/myservice/.manifest`：
   ```
   LABEL=我的服务
   CATEGORY=服务
   DEFAULT_ACTION=install
   ```
4. 编写 `services/myservice/README.md`，说明支持平台、安装/卸载/常用命令。
5. 更新 `README.md` 的模块表格和 CHANGELOG。

> 注：框架通过 `.manifest` 自动发现模块，无需手动修改 `install.sh` 的菜单或分发逻辑。

## 代码规范

- 使用 `#!/usr/bin/env bash` 或 `#!/bin/bash`。
- 所有脚本须通过 `bash -n` 语法检查；CI 使用 shellcheck（排除 SC2164）。
- 本地提交前请运行：
  ```bash
  ./scripts/check_issues.sh
  ./tests/ci_run.sh --phase static
  ```
- 优先复用 `lib/common.sh` 中的函数，避免重复造轮子。
- 用户可见提示使用中文，与现有脚本风格一致。

## 提交规范

- 使用清晰的提交信息，建议前缀：`feat:` / `fix:` / `refactor:` / `docs:` / `chore:`。
- 一个 PR 聚焦一件事；大改动请先开 Issue 讨论。

## 测试建议

- 至少在 Ubuntu 和 macOS 上验证新模块（CI 会跑 shellcheck 双平台）。
- 涉及系统服务（systemd/launchd）的安装/卸载，请在目标机器上人工验证。
- 修改公共库 `lib/common.sh` 时，须确认所有 source 它的脚本仍正常。

## 报告问题

Issue 请包含：操作系统与版本、CPU 架构、错误信息、重现步骤。
