# 平台可见性过滤——在特定系统隐藏不被支持的安装能力

日期：2026-08-29
状态：待评审

## 背景与问题

unix_script 的 58 个模块在所有出口（交互菜单、`--list*`、`search`、`--status-json` 等）全量可见，
平台不支持只在安装时才暴露：模块内部运行时检查 `OS_TYPE` 后报错退出（install）或输出 `n/a`
（status）。以 macOS 为例，实测有 15 个模块永远装不上（ufw、swap、bbr、sys-setup、nat、
multi-net、disk、clash、ops-kit、fail2ban、cockpit、1panel、btpanel、casaos、webmin），
用户和 AI agent 会在列表里看到它们、尝试安装、然后收到报错——多绕一圈。

反向同样存在：`brew` 模块仅支持 macOS，在 Linux 上可见但不可用。

## 目标

- 模块用静态声明表达平台适用性，框架在**所有模块枚举出口**过滤掉当前系统不适用的模块
- 提供 escape hatch，一条命令看到全量（排查/跨平台脚本场景）
- AI 契约（`--status-json`）同步更新并保持机器可读语义清晰

## 非目标

- 架构（arm64/x86_64）与发行版（ubuntu/kylin…）粒度的声明——现阶段无模块需要，
  语法上留扩展余地即可
- README 支持矩阵增加模块级平台列（`scripts/support_matrix.sh` 只读 ci.yml 与 GitHub API，
  与本特性无交互）
- Tab 补全与 `suggest` 拼写候选的过滤——补全选中隐藏模块会命中框架拦截并得到解释性报错，
  报错即文档
- 移除模块内部的 OS 运行时检查（纵深防御：直接调模块路径 `./sys-tools/ufw/install.sh`
  仍被模块自身拦截）

## 方案对比

| 方案 | 思路 | 结论 |
|------|------|------|
| **A. manifest 静态声明 + registry 过滤** | `.manifest` 新增 `PLATFORMS` 键，框架按声明过滤 | **采用**：声明式、零运行时开销、与现有 registry 架构一致 |
| B. 动态探测 | 启动时逐个执行模块 `status` 取 `n/a` 判定 | 否决：54 个子进程的启动开销不可接受（项目刚为 5.4s 批查做过优化）；鸡生蛋 |
| C. 源码推断 | grep 模块 install.sh 的 OS_TYPE 用法推断 | 否决：脆弱（docker 双平台但内部有 linux 分支，必误判）；推断逻辑本身是维护负担 |

## 设计

### 1. 声明格式（`.manifest` 新增可选键）

```
PLATFORMS=linux          # 仅 Linux
PLATFORMS=darwin         # 仅 macOS
PLATFORMS=linux,darwin   # 双平台（等价于不写）
（缺省）                  # 全平台适用（现状行为，向后兼容）
```

- 取值与 `detect_os` 的 `OS_TYPE`（linux|darwin）对齐；逗号分隔
- 存量模块补声明 16 个（依据 2026-08-29 macOS 实测 status 全量扫描 + brew 源码门檻确认）：
  - `PLATFORMS=linux`（15 个）：1panel、btpanel、casaos、cockpit、fail2ban、webmin、
    bbr、swap、sys-setup、clash、disk、multi-net、nat、ops-kit、ufw
  - `PLATFORMS=darwin`（1 个）：brew
  - Linux 侧清单在实现时用同法（CI 容器内跑 status 扫 `n/a`）复核，预期仅 brew

### 2. registry API（lib/registry.sh）

```bash
registry_platforms <mod>        # 输出空格分隔平台列表（无声明则空）
uxs_module_supported <mod>      # 声明含 $OS_TYPE（或缺省声明）→ 0，否则 1；OS_TYPE 未初始化时先 detect_os
registry_visible_modules        # 按注册序输出可见模块；UNIX_SCRIPT_SHOW_ALL=1 时输出全量
```

- `uxs_module_supported` 保持纯语义（只看声明 vs 当前 OS）；SHOW_ALL 只影响
  `registry_visible_modules`，两层分离便于测试
- 过滤函数不改变 `_REGISTRY_MODULES` 本体——dispatch/别名解析/依赖解析仍基于全量注册表

### 3. 过滤出口（改用可见列表）

| 出口 | 行为 |
|------|------|
| `--list` / `--list-modules` / `--list-categories` / `show_usage` 模块段 | 只列可见模块 |
| `search`（`show_search_results`） | 展示层过滤，不可见命中不计入"共 N 个匹配" |
| bash 菜单 | 主页面分类计数、分类页条目均过滤；某分类可见模块为 0 时整类隐藏 |
| fzf 菜单 | 行构建时过滤 |
| `--status` / `--status-json` | 只输出可见模块；`--status-json` 头 3 行框架元数据不变 |
| 卸载菜单 | 两级页面均过滤（不适用的模块在本机必然未安装，无卸载可言） |
| `export`（profile） | 只导出本机适用模块 |
| `apply`（profile） | **跳过**本机不适用的行并 warn（不报错、不中断）——profile 跨机器携带是核心场景：macOS 导出的 profile 在 Linux 上 apply 时，Linux 专属行必须能装 |

### 4. 拦截与报错（枚举出口之外的路径）

- **dispatch 拦截**（`dispatch_module` / `dispatch_module_or_passthrough`，别名解析后）：
  模块不适用时报错退出 1，消息形如
  `模块 ufw 不支持当前系统（darwin，仅支持：linux）。查看适用模块：./install.sh --list-categories；强制显示全量：UNIX_SCRIPT_SHOW_ALL=1 ./install.sh ...`
  ；`UNIX_SCRIPT_SHOW_ALL=1` 时放行（显式意图优先）
- **依赖护栏**（`ensure_module_deps`）：所依赖模块不适用时报错
  `模块 X 依赖 Y，但 Y 不支持当前系统`，不尝试安装
- 状态子命令约定不变：直接调用隐藏模块的 `status` 仍输出 `n/a`、退出 0

### 5. escape hatch

统一用环境变量 `UNIX_SCRIPT_SHOW_ALL=1`，全出口生效（含 `--status-json`）。
不新增命令行 flag：`--status-json` 等本身是 flag，再叠 flag 会让 AI 解析规则复杂化；
环境变量对 AI agent 与 shell 脚本同样顺手。写入 `show_usage` 与 AGENTS.md。

### 6. 测试（新文件 tests/unit_platform_filter.sh，注册进 ci_run.sh phase_routing）

1. manifest 解析：有/无 `PLATFORMS` 键 → `registry_platforms` 正确
2. `uxs_module_supported` 真值表（linux/darwin 声明 × 当前 OS，含缺省声明）
3. `--list-modules` / `--status-json` / `search` 过滤生效；`UNIX_SCRIPT_SHOW_ALL=1` 恢复全量
4. dispatch 拦截：macOS 上 `./install.sh ufw` 退出非 0 且消息含平台信息（测试宿主为 darwin/linux 时分别断言对应方向）
5. apply 跳过不适用行且继续处理后续行
6. **关键不变量**：默认模式下 `--status-json` 输出零 `n/a` 行；`SHOW_ALL=1` 时 n/a 行数等于声明数
   （darwin 宿主上 = 15）——这一条把整个特性压缩成一句可断言的契约

### 7. 文档

- AGENTS.md：`--status-json` 契约段补"默认仅含本机适用模块 + SHOW_ALL 用法"；
  manifest 键表加 `PLATFORMS`；AI 典型工作流不改（`--status-json` 语义自洽）
- `show_usage` 补 escape hatch 一行
- CHANGELOG 随发版批次记录；README 不动（矩阵与本特性无交互）

## 兼容性说明

- `--status-json` 默认输出从 58 行缩到 43 行（macOS 实测，全量 58、n/a 15）：
  **breaking change**。
  缓解：头 3 行框架元数据不变；AGENTS.md 同步更新；`UNIX_SCRIPT_SHOW_ALL=1` 可恢复全量。
  按 MEMORY 既有约定，随下一个 minor 版本（v1.15.0）发布并在 CHANGELOG 标注。
- 无 `PLATFORMS` 声明的模块行为完全不变（向后兼容）。
- profile 文件行格式与语义不变；仅 export 的导出范围收敛为本机适用模块
  （与第 3 节一致），跨机器可移植性由 apply 端的跳过逻辑保证。

## 验收标准

- macOS 上 `./install.sh --list` 不再出现 15 个 Linux-only 模块；`search swap` 无匹配；
  交互菜单（bash/fzf）与卸载菜单同步收敛
- `UNIX_SCRIPT_SHOW_ALL=1 ./install.sh --status-json` 输出全量 58 行（含 15 行 n/a）
- macOS 上 `./install.sh ufw` 得到解释性报错而非模块内部的安装报错
- `tests/ci_run.sh --phase routing` 全绿（含新单测）
