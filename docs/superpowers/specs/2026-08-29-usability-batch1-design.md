# 设计：易用性快修包（批次①——status-json 提速 / doctor 误报 / ufw 截断 / dry-run 诚实化 / 文档补齐）

**日期**: 2026-08-29
**状态**: 待实现
**作者**: brainstorming 会话产出（2026-08-29 巡审证据驱动）
**范围**: `--status-json` 并行化与防截断、doctor 无 TTY 误报、ufw status 中止、dry-run 副作用收敛、AGENTS.md/README 元数据文档
**后续批次**: ② 新手引导（装完 next-step 提示 + bootstrap 输出精简）；③ `uxs search <关键字>`。各自独立小 PR，不与本次堆叠。

---

## 背景与证据（2026-08-29 macOS 本机实测 + 2026-08-28 实机记录）

| # | 问题 | 证据 |
|---|------|------|
| 1 | `--status-json` 串行逐模块查询，54 模块耗时 **2 分 16 秒**（macOS 实测）；菜单已有并行批查+TTL 缓存（`status_batch_query`，lib/status.sh:188），AI/脚本主路径却没接上。单模块 status 实测：tailscale 21.9s / clash 15.3s / docker 13.6s / k7s 11.5s，慢根因是模块内网络探测无超时护栏 | 实测 2026-08-29 |
| 2 | `show_status_json` 中 `raw=$(module_status_raw "$mod")` 在 `set -e` 下：模块 status 子 shell 非零退出会**中止整个输出**。实机案例：ufw 的 `status_ufw` 裸 `sudo ufw status`（无缓存凭据/无 TTY）静默失败 → `--status-json` 只输出 50/54 行且不报错 | 实机 2026-08-28（[[unix-script-verification-findings-2026-08]]） |
| 3 | doctor 无 TTY 时 `sudo -n true` 失败后回落 `sudo -v`（无 TTY 必然失败）→ 误报「sudo 不可用」并计入问题数；macOS 缺 os-release 的正常现象也被 WARNING 计数（「发现 2 个问题」） | 本机复现 2026-08-29，lib/doctor.sh:117-122 |
| 4 | `--dry-run essential-pkgs` 实测仍执行 Homebrew auto-update（更新 3 个 tap）。用法文案已声明「用户级操作仍会执行」（非 bug），但 auto-update 这种纯网络副作用最违和且拖慢预览 | 本机实测 2026-08-29 |
| 5 | `--status-json` 头部 `os:/arch:/version:` 三行框架元数据，AGENTS.md/README 未记载，AI 严格按文档解析会意外 | 文档比对 |

## 目标

- `--status-json` 常规耗时从分钟级降到 **≈ 最慢单模块耗时**（并行批查 + 超时护栏后预期 < 10s），且**任何单模块异常都不再截断输出**
- doctor 在无 TTY 环境不再误报；问题计数只数真问题
- ufw status 在无凭据/无 TTY 下有降级链，零输出中止不复现
- dry-run 下压制 brew auto-update 类纯副作用网络操作
- 机器可读输出的文档与实现严格一致

## 非目标（YAGNI）

- 不改 `--status-json` 输出格式（`os/arch/version` 头三行保留，`模块:状态[:版本]` 行格式不变）
- 不给 `--status-json` 加跨进程 TTL 缓存（AI 场景要新鲜数据；并行化后无必要）。菜单缓存机制不动
- 不逐模块重写 status 逻辑（只在确认阻塞点后加超时护栏）
- 不做批次②③的内容

---

## ① `--status-json` 提速与防截断（lib/menu.sh + lib/status.sh）

1. **并行批查**：`show_status_json` 改为先 `status_batch_query $_REGISTRY_MODULES`（并发度 `UXS_STATUS_JOBS` 默认 8），再从 `_UXS_STATE_<mod>` 会话缓存读结果输出。批查结果只进会话内变量，不写跨进程 TTL 缓存（与菜单行为区分：菜单走 `menu_status_ensure` 的 TTL 缓存路径不变）。
2. **防截断（治本）**：批查内部对每个模块的调用需容错——单模块失败只记录该模块状态为 `unknown`，不外溢。`show_status_json` 读取侧对空结果兜底 `模块名:unknown`。
3. **防截断（兜底，框架层保险）**：任何直接调用 `module_status_raw` 的路径统一改为 `raw=$(module_status_raw "$mod") || raw=""` 形态；`module_status_raw` 自身已对脚本缺失兜底，保持。
4. **超时护栏**：`lib/common.sh` 新增 `uxs_with_timeout <秒> <命令...>`（可移植实现：perl alarm + 子进程 kill——不能 exec，否则超时退出码变成信号 142；契约：超时 rc=124 与 GNU timeout 对齐；macOS/Linux 通用，无 GNU timeout 依赖）。批次①仅将其应用到**实测确认阻塞**的模块 status 调用点（实现阶段先用 `UXS_DEBUG` 逐一定位 tailscale/clash/docker/k7s 的阻塞命令，护栏加在确认的阻塞点，不盲加）。
5. 状态值为 `unknown` 的行照常输出（格式不变），保证 54 行 + 3 元数据行恒定。

## ② doctor 误报修复（lib/doctor.sh）

1. sudo 检查：`sudo -n true` 失败后，若 `[[ ! -t 0 ]]`（无 TTY）→ 输出「无法检测 sudo（非交互环境），已跳过」按 **skip** 处理，不计入问题数；有 TTY 才回落 `sudo -v`。
2. macOS/无 os-release：发行版识别失败在 macOS 上属预期，降为 INFO（「macOS 不适用发行版检测」），不计入问题数。Linux 上缺 os-release 仍保留 WARNING。
3. 报告汇总语义不变：返回值 = 真问题数。

## ③ ufw status 降级链（sys-tools/ufw/install.sh）

按 2026-08-28 记录的修法落地：

1. `sudo -n ufw status` 成功 → 正常输出；
2. 失败 → 降级 `systemctl is-active ufw`（active→`STATE=installed:running`，否则 `STATE=installed`）；
3. `systemctl` 也无 → 兜底 `STATE=installed`（命令存在即视为已装）；
4. 任何路径都必须输出一行 `STATE=`，杜绝静默零输出。

## ④ dry-run 副作用收敛（lib/common.sh）

1. `uxs_install_sudo_shim`（dry-run 启用统一入口，install.sh 与菜单共用）内追加 `export HOMEBREW_NO_AUTO_UPDATE=1`，压制 brew auto-update 网络副作用。
2. 用法/README 的 dry-run 说明补一句：用户级操作仍会执行（现状声明保留，措辞不变）。

## ⑤ 文档补齐（AGENTS.md + README.md）

1. AGENTS.md `--status-json` 节补：输出首部固定 3 行 `os:<值>`、`arch:<值>`、`version:<值>` 元数据，其后每模块一行 `模块:状态[:版本]`；解析按「跳过前 3 行」或按 key 是否为模块名判断。
2. README 机器可读输出示例同步（示例里补上前 3 行）。
3. CHANGELOG `[Unreleased]` 记录本批全部变更。

## 测试（tests/ci_run.sh + 单测）

1. **防截断单测**：伪造一个 status 必然非零退出的假模块（临时 manifest + 脚本），断言 `--status-json` 输出行数 = 模块总数 + 3 且该模块行为 `:unknown`，退出码 0。
2. **doctor 单测**：无 TTY（管道）跑 `doctor`，断言输出含「跳过」且问题数不含 sudo 项；macOS 下不含 os-release WARNING。
3. **ufw 单测**：无 sudo 环境（`sudo -n true` 失败模拟）断言 `ufw status` 输出含 `STATE=` 且退出 0（CI 容器免密 sudo 需用 PATH 遮蔽 sudo 模拟）。
4. **uxs_with_timeout 单测**：`uxs_with_timeout 1 sleep 3` → rc=124、耗时 <2s；`uxs_with_timeout 2 true` → rc=0。
5. **路由测试**：`--status-json` 在 CI 容器（含无 fzf/无 sudo 的 Alpine 腿）全绿。
6. shellcheck：全部改动文件过 `shellcheck -e SC2164,SC1091,SC2317,SC2329 -x`（与 ci_run.sh:127 一致）；bash 3.2 兼容（不用关联数组/wait -n）。

## 文件改动清单

| 文件 | 动作 | 要点 |
|---|---|---|
| `lib/menu.sh` | 修改 | `show_status_json` 并行批查 + unknown 兜底 |
| `lib/status.sh` | 修改 | 批查容错（单模块失败不外溢）；`module_status_raw` 调用点 `|| raw=""` |
| `lib/common.sh` | 修改 | 新增 `uxs_with_timeout`；`uxs_install_sudo_shim` 加 `HOMEBREW_NO_AUTO_UPDATE=1` |
| `lib/doctor.sh` | 修改 | 无 TTY skip、macOS os-release 降 INFO |
| `sys-tools/ufw/install.sh` | 修改 | status 三级降级链 |
| 慢模块 install.sh（实现时确认） | 修改 | 阻塞点加 `uxs_with_timeout` |
| `AGENTS.md` `README.md` `CHANGELOG.md` | 修改 | ⑤ 文档补齐 |
| `tests/ci_run.sh`（或新增 tests/unit_*.sh） | 修改 | 上述测试段 |

## 实施顺序

1. ③ ufw + ② doctor（小而独立，先消除「静默错误」）
2. ① status-json 并行 + 防截断（依赖 1 的降级链先行，防截断测试才能全绿）
3. ④ dry-run + ⑤ 文档
4. 测试随每步走，最后跑全量 `./tests/ci_run.sh --phase static / routing`

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| `status_batch_query` 后台任务在 bash 3.2 的兼容性 | 沿用菜单已验证的实现（v1.13.0 已在跑），不新造轮子 |
| `--status-json` 并行化改变「逐模块实时」语义（缓存内状态滞后） | 批查只用会话内缓存（进程生命周期），不落 TTL 盘缓存，单次调用内恒新鲜 |
| uxs_with_timeout 的 perl 依赖缺失（极简容器） | `command -v perl` 探测，缺失则不套超时直接执行（行为退化为现状）；CI Alpine 腿验证 |
| ufw 单测在免密 sudo 的 CI 上无法触发降级链 | PATH 遮蔽法注入假 sudo，测试内可控 |
| 修改 show_status_json 影响下游 AI 解析 | 输出格式不变（含头 3 行与 unknown 行），仅耗时与完整性变化 |
