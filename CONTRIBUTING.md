# 贡献指南

感谢你考虑为 unix_script 贡献代码！请遵循以下约定，以保持脚本库的一致性与可维护性。

## 仓库结构

```
.
├── install.sh              # 统一安装菜单（交互 + 非交互）
├── uninstall.sh            # 一键卸载入口
├── check_issues.sh         # 本地质量检查（shellcheck + bash -n）
├── lib/common.sh           # 公共函数库（颜色/打印/检测/服务管理）
├── <service>/install.sh    # 各服务模块安装脚本
├── <service>/README.md     # 各服务模块文档
├── process_manager_tool/   # 进程管理工具（独立子项目）
└── .github/workflows/ci.yml
```

## 新增一个服务模块

**推荐方式**：使用脚手架命令自动生成模板：

```bash
./install.sh scaffold myservice --category 服务 --label "我的服务"
```

生成后编辑 `myservice/install.sh` 实现具体逻辑即可。

**手动方式**：

1. 在仓库根创建模块目录，例如 `myservice/`。
2. 编写 `myservice/install.sh`：
   - 顶部 `set -e`，并 `source` 公共库：
     ```bash
     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
     # shellcheck source=../lib/common.sh
     source "$SCRIPT_DIR/../lib/common.sh"
     ```
   - 使用统一的打印函数：`info` / `success` / `warn` / `error`（**不要**自定义颜色或重复定义）。
   - 实现 `install`、`uninstall`、`status`、`help` 子命令，并通过 `main "$@"` 分发。
   - 做平台检测（`detect_os`）、依赖检查（`check_commands`）、权限检查（`require_sudo`）。
   - Linux 用 systemd、macOS 用 launchd 管理服务（可复用 `service_start`/`service_stop`）。
3. 编写 `myservice/README.md`，说明支持平台、安装/卸载/常用命令。
4. 在 `install.sh` 中接入：
   - 主菜单新增一项（保持编号连续）。
   - 卸载菜单新增对应项。
   - 状态页新增 `status_<name>_module` 并在 `show_installed_services` 调用。
   - `dispatch_module` 新增模块名映射。
5. 在 `uninstall.sh` 的 `dispatch` 中新增映射（如有独立卸载逻辑）。
6. 更新 `README.md` 的服务表格、平台矩阵、CHANGELOG。

## 代码规范

- 使用 `#!/usr/bin/env bash` 或 `#!/bin/bash`。
- 所有脚本须通过 `bash -n` 语法检查；CI 使用 shellcheck（排除 SC2164）。
- 本地提交前请运行：
  ```bash
  ./check_issues.sh
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
