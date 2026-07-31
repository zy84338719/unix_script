# 远端版本监测与更新提示 — 设计文档

- 日期：2026-07-31
- 状态：已批准，待实现
- 关联仓库：`zy84338719/unix_script`

## 1. 背景与目标

`unix_script` 是一个跨平台（macOS / Linux）的 shell 安装脚本库，通过 `install.sh` 交互式菜单或非交互子命令使用。当前用户无法感知远端是否发布了新版本，可能长期使用过时脚本。

**目标**：增加远端版本监测能力，让用户在三种场景下感知并（可选地）应用更新：

1. **启动时自动检查** — 运行 `install.sh` 时静默比对本地 `VERSION` 与 GitHub 最新 release tag，有新版本则打印一行醒目提示。仅提示，**不做任何写操作**。
2. **`check-update` 子命令** — `./install.sh check-update` 主动检查并打印详细结果。
3. **`update` 子命令** — `./install.sh update` 安全检查 + `yes_no` 确认后执行 `git pull`。

## 2. 范围

**包含**：
- 上述三个入口（启动自动检查 / `check-update` / `update`）。
- 版本比较、网络容错、git 安全检查。

**不包含（YAGNI）**：
- 后台定时监测（cron / launchd 守护进程）。
- 强制更新 / 静默自动 pull。
- Webhook 或外部通知。
- 多仓库监测。

## 3. 架构与代码组织

采用项目既有分层约定：**公共能力放 `lib/common.sh`，入口路由 / 调用时机在 `install.sh`**。

### 3.1 `lib/common.sh` 新增（紧邻现有 `github_latest_tag()`）

| 函数 | 职责 | 输出 / 返回 |
|------|------|-------------|
| `get_local_version()` | 读 `$SCRIPT_DIR/VERSION`，去空白 | stdout：版本号；失败返回 `unknown` |
| `version_gt() <a> <b>` | 语义化版本比较，`a > b` 返回 0 | 退出码 0=是，1=否（基于 `sort -V`，兼容 macOS BSD sort） |
| `check_for_update()` | 取本地版本 → 取远端 tag → 比对 | 设全局 `REMOTE_LATEST` / `UPDATE_AVAILABLE`；返回 0=有更新，1=无 / 出错；全程容错 |
| `print_update_hint()` | 依据 `UPDATE_AVAILABLE` 打印一行醒目提示 | 无 |
| `do_self_update()` | 安全检查 + `yes_no` 确认 + `git pull` | 退出码 0=成功，1=用户拒绝 / 不安全 |

**常量**（common.sh 顶部）：`UPDATE_REPO="zy84338719/unix_script"`。

### 3.2 `install.sh` 改动（最小化，只加调用时机）

- `main()` 在 `detect_os` / `detect_arch` 之后、参数分支之前插入自动检查钩子。
- `main()` 的 `case` 增加 `check-update)` 与 `update)` 两个分支。
- `dispatch_module` 兜底 `*)` 的「已知命令」提示纳入新子命令。
- `show_usage` 文本新增这两条。

## 4. 关键行为细节

### 4.1 自动检查的开关与超时

- 默认开启。环境变量 `UNIX_SCRIPT_NO_UPDATE_CHECK=1` 关闭。
- 自动检查仅在「人类交互」场景默认开启；检测到 `CI=true` 或非 TTY 且未显式开启时跳过自动检查（`check-update` 仍可手动调用）。
- `curl` 加 `--max-time 5`，5 秒拿不到静默跳过，**绝不阻塞主流程、绝不报错**。

### 4.2 版本比较

`sort -V` 风格，去掉前导 `v`。

- 本地 `1.2.0` 对远端 `1.2.1` → 有更新。
- 远端为空 / 取失败 → 视为无更新（保守，不误报）。
- 相等 → 无更新。

### 4.3 `update` 子命令安全检查

任一失败即拒绝并提示，**不执行 pull**：

1. `git rev-parse --is-inside-work-tree` — 非 git 仓库（如 zip 下载）→ 提示重新 clone。
2. `git remote get-url origin` — 无 origin → 提示手动指定。
3. `git status --porcelain` 非空 — 有未提交改动 → 拒绝 pull，提示 commit / stash。
4. `git symbolic-ref -q HEAD` 失败 — detached HEAD → 警告并要求确认。
5. 通过后 `yes_no "确认执行 git pull 更新到 $REMOTE_LATEST？"` → 同意才 pull。
6. pull 后比对 `VERSION` 确认更新生效，打印结果。

### 4.4 提示文案示例（启动自动检查）

```
⚠️  [更新提示] 检测到新版本：当前 1.2.0 → 远端 1.2.1
    运行 ./install.sh update 一键更新（会先确认，不会静默改动）
```

## 5. 测试策略

遵循项目现有 CI 模式（`tests/ci_run.sh` 的 routing 阶段）。

**routing 测试新增**：
- `install.sh check-update` 退出码 0（即使无网络 / 无 release 也不应崩）。
- `install.sh update` 在不安全环境（detached HEAD / 构造脏工作区）打印提示且不破坏。
- `UNIX_SCRIPT_NO_UPDATE_CHECK=1 install.sh --help` 不触发网络请求 / 不阻塞。
- 既有 `--version` / `--list` / 未知模块测试保持不变（向后兼容）。

**静态检查**：所有新代码过 `bash -n` + `shellcheck`（项目 CI 强制）。

**单元覆盖**：`version_gt` 边界（相等、major / minor / patch 各级、空值、带 `v` 前缀）。

**不测**：真实 GitHub API 在线行为（受速率限制 / 外网波动，属 CI 已有的「尽力而为」范畴）。

## 6. 文档同步

- `README.md`：「快速开始」附近加一节说明自动更新检查 + `check-update` / `update` 子命令；非交互命令列表补这两条。
- `CHANGELOG.md`：新增条目记录该功能。
- `VERSION`：本次属功能新增，建议发布时 bump（如 → `1.3.0`）。属发布动作，spec 只标注建议，**不在本次实现里改版本号**。

## 7. 向后兼容

- 不改变任何现有子命令行为（`--help` / `--version` / `--status` / `--list` / 模块名）。
- 自动检查默认不影响退出码（失败静默）。
- 可通过环境变量完全关闭。
