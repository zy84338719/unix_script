# 设计：易用性改造（UX Overhaul — 菜单双轨 / did-you-mean / 补全动态化 / 状态内联）

**日期**: 2026-08-15
**状态**: 已评审通过，待实施
**作者**: brainstorming 会话产出
**范围**: 交互菜单双轨重构（fzf 优先 + bash 降级）、`.manifest` DESC 单一数据源、CLI 模糊纠错、补全注册表驱动、状态并行缓存、网络超时、文档同步

---

## 背景与动机

unix_script 的 CLI/机器侧（统一子命令、别名、`--status-json`、依赖自动安装、dry-run、doctor）已经成熟；但「人类日常交互」侧存在系统性短板。用户反馈「不太好用」，澄清后确认四个痛点全中：**交互菜单难用、命令行不顺手、模块发现性差、新手上手门槛高**。

探索发现的具体证据：

| # | 问题 | 证据 |
|---|------|------|
| 1 | 主菜单 52 项平铺，无搜索/无分页/无状态标注/无描述，多选要点 N 轮且每轮整屏重画 | `lib/menu.sh:50-71` |
| 2 | 敲错模块名只报错 + 一行倾倒 52 个名字，无 did-you-mean | `install.sh:51-55` |
| 3 | 模块中文描述存在三份（README 表格 / 模块 README / zsh 补全）但菜单与 `--list` 均不使用；zsh 补全描述比菜单本身信息更全 | `completions/uxs.zsh:10-59` |
| 4 | bash/zsh 补全硬编码模块清单，已落后注册表 4 个模块（缺 certbot、code-lint、disk-usage、nat），新增模块不会自动进补全 | `completions/uxs.bash:14` |
| 5 | 启动时更新检查的 curl 无超时，弱网卡菜单；关闭只能靠环境变量无 CLI 开关 | `lib/common.sh:265,269,286,291` |
| 6 | 实测全量 52 模块 machine 状态查询串行耗时 **5.4s**，是状态内联显示的性能约束 | 实测 2026-08-15 |
| 7 | 面向人的文档只有「新服务器」场景，README 未描述交互菜单形态 | `docs/` |

用户约束（澄清确认）：

- **人机并重**：机器接口保持现有语义（只追加不破坏），人类交互层同等打磨。
- **可选 fzf，优雅降级**：检测到 fzf 用它，没有则回退纯 bash。零强制外部依赖。

## 目标与非目标

**目标**：上表 7 项全部覆盖——1/3 由 ①②④⑦ 解决，2 由 ④ 解决，4 由 ⑤ 解决，5 由 ⑥ 解决，6（性能约束）由 ③ 化解为可行方案。

**非目标**（刻意不做，YAGNI）：

- 不做新手引导 wizard（doctor + README 增补已覆盖）
- 不做 fish 补全
- 不做每模块独立使用手册汇总（模块 README 已存在）
- 不改机器接口现有列语义（`--list-modules` 前两列、`--status-json` 格式不变，只追加）
- 不动 6 个模块子菜单（`lib/submenus.sh`）的内部结构

---

## ① 数据层：`.manifest` 增加 `DESC=` 字段（单一数据源）

- 52 个 `.manifest` 各增加一行 `DESC=<一句中文描述>`，建议 ≤ 20 字，例：`DESC=容器引擎，一键安装 Docker CE`
- `lib/registry.sh`：`_parse_manifest` 初始化/解析 `DESC`，新增查询 API `registry_desc <mod>`（空值返回空串，菜单侧自行回退到 LABEL）
- `lib/scaffold.sh` 模板增加 `DESC=` 占位行，保证新模块有描述
- 描述内容以 README 52 模块表格 + zsh 补全现成中文描述为底稿逐一校对，消除三份数据源不一致
- DESC 为可选字段（向后兼容：无 DESC 的 manifest 不报错）

## ② 交互菜单双轨重构

模式选择：环境变量 `UXS_MENU=fzf|bash` 强制指定；未指定时 `command -v fzf` 存在 → fzf 模式，否则 → bash 模式。强制 fzf 但 fzf 不存在时报错并提示安装方式后回退 bash 模式（不中断）。

### fzf 模式（新文件 `lib/menu_fzf.sh`）

- 列表行格式：`<状态图标> <模块名> <LABEL> <DESC>`（状态图标来自 ④ 的缓存）
- `fzf --multi`：TAB 多选、模糊搜索、回车对所选模块**依序执行默认动作**（DEFAULT_ACTION，通常 install）
- 批量执行时对每个 install 动作复用现有 `ensure_module_deps`（依赖拓扑序自动前置，`--no-deps` 语义不变）
- `HAS_SUBMENU` 的模块（docker/clash/sys-setup/dev-mirror/multi-net/pm）选中后进入对应 `manage_*` 子菜单，**不参与批量**
- `--preview` 显示模块 README 前 20 行（模块目录 README.md；不存在则显示 LABEL/DESC/别名/依赖）
- fzf 被取消（ESC）返回主流程，不算错误

### bash 降级模式（重构 `lib/menu.sh`）

- **两级导航**：首页 = 5 个分类入口 + 管理项（s 状态 / u 卸载 / c 更新 / q 退出 + `f` 强制刷新状态缓存）；进入分类后 ≤ 17 项一屏展示
- 分类页行格式：`  <序号>) <状态图标> <LABEL> - <模块名> - <DESC>`
- **多选**：输入支持 `1`、`1,3`、`2-5`、`1,3,5-8` 组合，解析后逐个执行（有 HAS_SUBMENU 的模块在多选中单独提示「请单独进入」并跳过）
- **过滤**：输入 `/关键字` 进入过滤态，按子串匹配（模块名/LABEL/DESC，大小写不敏感），空关键字恢复全列表
- 错误输入不再 `sleep 1` 清屏重画：保留当前屏幕，仅打印一行错误提示后重新等待输入
- 卸载菜单（u）复用两级导航结构（分类 → 模块），带已安装状态图标

## ③ 状态内联显示与性能（关键设计点）

约束：串行全量查询 5.4s，不可接受每次重画都跑。

三层方案：

1. **并行批查**：`lib/status.sh` 新增 `status_batch_query <mods...>`，以固定并发（默认 8，`UXS_STATUS_JOBS` 可覆盖）后台批量执行 `module_status_machine`，结果写 `mktemp` 临时文件后回收。bash 3.2 兼容（`jobs`/`wait`，不用 `wait -n`）。预期耗时 ~1s。
2. **会话内缓存**：结果存普通变量（`_UXS_STATE_<mod>`，沿用 registry 的 `_reg_varname` 模式）；菜单重画零开销；执行动作成功后仅刷新受影响模块的单条状态。
3. **跨进程 TTL 缓存**：`/tmp/uxs-status-$UID/`（macOS/Linux 通用路径）写 `cache` 文件（`mod\tstate` 每行一条 + 首行 `#ts=<epoch>`），TTL 默认 300s（`UXS_STATUS_CACHE_TTL` 可覆盖，0 = 禁用）。菜单启动时命中则秒开。`f` 管理项 / 动作后强制绕过。

状态图标映射（人类菜单用）：

| machine state | 图标 |
|---|---|
| `installed` / `installed:running` / `installed:stopped` / `configured` | `✓`（绿） |
| `not_installed` / `not_configured` | 空 |
| `n/a` | `·`（暗色） |
| 其他/查询失败 | `?` |

## ④ CLI 容错：did-you-mean + usage 分组

新文件 `lib/suggest.sh`（纯函数、bash 3.2 兼容、无关联数组）：

- `levenshtein <a> <b>`：经典 DP 实现（模块名 ≤ 25 字符，52 模块全量比对开销可忽略）
- `suggest_module <输入>`：先精确/别名命中 → 前缀匹配 → 子串匹配 → 编辑距离 ≤ 2，返回至多 3 个候选（按距离升序）
- `parse_multiselect <输入> <最大序号>`：解析 `1,3,5-8` 为排序列表，越界/格式错误返回非 0

接入点：

- `install.sh` `dispatch_module` 未知模块分支：输出 `未知模块: doker` + `  你是想输入 docker 吗？（./install.sh docker）`（有候选时），退出码仍为 1；usage 不再自动倾倒，改为提示 `--list-categories` 查看全部
- `show_usage` 的模块清单改为按分类分组、每模块一行带 DESC（多行缩进格式），替换现在挤一行的 52 名单
- 模块级未知子命令：在 `lib/core.sh` 或公共 usage 兜底处给同样建议（能力提供，各模块逐批接入，本次不强制改 52 个模块）

## ⑤ 补全动态化（修复脱节）

- `completions/uxs.bash`、`completions/uxs.zsh` 重写：
  - 补全脚本通过自身路径定位仓库根（`${BASH_SOURCE[0]%/*}/..` / zsh `%` 展开），实时 grep 各分类目录 `.manifest` 的模块名（`basename`）——与注册表**同源**，新增/删除模块自动同步
  - 子命令补全沿用 `show_list_modules` 的提取启发式（usage 行 `{a|b|c}` 或 case 分支 grep），在补全内以 grep 实现
  - zsh 保留对未知模块的 `install/uninstall/status/help` 回退；bash 增加同样回退
  - DESC 不进补全（保持补全轻量、避免每次 TAB 全量 grep manifest 的开销——模块名清单 grep 一次 < 50ms 可接受）
- 兼容场景：仓库被移动后旧 rc 里 source 的绝对路径失效属既有问题，不在本次范围（uxs wrapper 同理）

## ⑥ 网络超时

- `lib/common.sh` 中 `github_latest_tag` / `github_release_asset_url` / 相关 curl 全部加 `--connect-timeout 5 --max-time 10`，超时值可用 `UXS_CURL_TIMEOUT`（秒）覆盖 connect/max 单值
- 弱网表现：更新检查失败走现有「无法获取远端版本」提示，菜单不卡死

## ⑦ 文档与上手

- README 新增「交互菜单」一节：两种模式的形态说明、多选语法（`1,3,5-8` / TAB）、`/关键字` 过滤、`UXS_MENU` 环境变量、状态图标含义
- `--list-modules` TSV **末尾追加第 3 列 DESC**（`模块名\t子命令  requires:...\t描述`），前两列语义不变；AGENTS.md 的输出示例与说明同步更新
- CHANGELOG `[Unreleased]` 记录全部变更

## ⑧ 测试（`tests/ci_run.sh` 新增）

- **纯函数单测**（bash 子进程 source `lib/suggest.sh`）：`levenshtein` 已知值、`parse_multiselect`（`1`、`1,3`、`2-5`、`1,3,5-8`、越界、非法字符）、状态图标映射
- **路由测试**：`./install.sh doker` → 退出码 1 且 stdout/stderr 含 `docker` 建议；`./install.sh zzzqqq`（无相近候选）→ 退出码 1 无建议但有不倾倒 usage 的提示
- **数据完整性**：`--list-modules` 每行 ≥ 3 列且第 3 列（DESC）非空（对全部 52 模块）；补全脚本提取的模块清单 == 注册表清单（对比 `--list` 输出）
- **降级路径**：`UXS_MENU=bash` 与 `UXS_MENU=fzf`（CI 容器无 fzf）在非 TTY 下均优雅退出不报错；TTL 缓存文件写入/命中/过期逻辑（用短 TTL 实测）
- **静态**：shellcheck 通过（新文件 + 改动文件）；CI 三阶段（static/routing/install）全绿

## 文件改动清单

| 文件 | 动作 | 要点 |
|---|---|---|
| `*/.manifest` × 52 | 修改 | 追加 `DESC=` 行 |
| `lib/registry.sh` | 修改 | DESC 解析 + `registry_desc()` |
| `lib/suggest.sh` | **新增** | levenshtein / suggest_module / parse_multiselect |
| `lib/status.sh` | 修改 | `status_batch_query` 并行 + TTL 缓存 + 图标映射 |
| `lib/menu.sh` | 重构 | 两级 bash 菜单 + 多选 + 过滤 + 缓存消费 + 卸载菜单分组 |
| `lib/menu_fzf.sh` | **新增** | fzf 模式（--multi/--preview） |
| `install.sh` | 修改 | dispatch 接入 suggest、usage 分组、`UXS_MENU` 解析 |
| `completions/uxs.bash` `uxs.zsh` | 重写 | manifest 驱动动态补全 |
| `lib/common.sh` | 修改 | curl 超时 |
| `lib/scaffold.sh` | 修改 | 模板加 DESC 占位 |
| `lib/core.sh` | 修改（小） | 子命令兜底建议能力（可选接入） |
| `tests/ci_run.sh` | 修改 | 新增 ⑧ 测试段 |
| `README.md` `AGENTS.md` `CHANGELOG.md` | 修改 | ⑦ 文档同步 |

## 实施顺序

1. ① 数据层（DESC）—— 一切的前提
2. ④ CLI 容错 + ⑥ 超时 —— 小步快跑，独立可发布
3. ③ 状态并行缓存 —— 菜单前置
4. ② 菜单双轨重构 —— 最大块
5. ⑤ 补全动态化
6. ⑦⑧ 文档 + 测试收尾（测试实际随每步走，此为汇总校验）

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| fzf 版本差异（--multi/--preview 参数老版本不支持） | 运行时 `fzf --version` 探测，不支持 --preview 则降级去掉该参数 |
| 并行状态查询在低配 VPS 上并发 8 仍慢 | `UXS_STATUS_JOBS` 可调；TTL 缓存兜底二次进入秒开 |
| `/tmp` 缓存被多仓库实例混淆 | 缓存 key 加仓库路径 hash（`$SCRIPT_DIR` md5 前 8 位） |
| `--list-modules` 加列破坏下游 AI 解析 | 列**只追加在末尾**；AGENTS.md 明示前两列语义不变；TSV 解析按列名/位置消费均兼容 |
| bash 3.2 兼容回归（关联数组/wait -n 误用） | 全部新代码遵循现有 `_reg_varname` eval 模式；CI static 阶段含 bash -n + shellcheck |
| 菜单重构引入回归 | 菜单主循环此前无测试，本次为纯函数（suggest/parse/图标）建立单测 + 非交互路径路由测试；交互循环保持简单可读 |
