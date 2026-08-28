# disk-usage top 深度下钻 + 交互模式 — 设计

日期：2026-08-28
状态：已批准（用户确认：增强现有模块、双下钻、智能 TTY）
分支：`feat/disk-usage-top-drill`（基于 v1.10.0 / origin/main）

## 背景与目标

`sys-tools/disk-usage` 已有 `top` 子命令做大小排行（`du -sh path/* | sort -rh | head -N`），
但存在四个问题：

1. **只看第一层**：无法看子目录里是什么占的空间（无下钻）
2. **空格路径显示截断**：Linux 分支 `awk '{printf $1, $2}'` 遇到含空格路径只显示首段
3. **漏隐藏目录**：`path/*` 通配不匹配点开头目录（`~/.cache`、`/private` 常是磁盘大户）
4. **`sort -h` 兼容性**：BSD/GNU/BusyBox 行为有差异；且固定扫 `/var/log` 等常见位置找大文件，
   `top <路径>` 的路径参数对文件榜不生效

目标（用户确认范围）：

1. `--depth D` 参数下钻：一条命令直接看 D 层内最大的 N 个目录
2. 交互式逐层下钻：终端里输序号进入目录继续扫（智能 TTY 检测，管道/CI 自动纯输出）
3. 大小以 M/G 人类可读单位显示；可选 `--min-size` 过滤出纯 M/G 级大家伙
4. 顺手修空格路径、隐藏目录、sort -h 三个 bug；大文件榜语义与路径参数对齐

非目标（YAGNI）：全屏 TUI、top 内集成删除（`clean` 已覆盖）、top 机器可读输出。

## 一、命令接口（向后兼容）

```
用法: disk-usage top [路径] [--count N] [--depth D] [--min-size SIZE] [--no-interactive]
```

| 参数 | 默认 | 说明 |
|------|------|------|
| `路径` | `/` | 扫描起点（文件榜目录路径 ≠ / 时在该路径下找） |
| `--count N` | `10` | 显示条数，任意正整数（帮助文档用 10/20/30/50 做示例） |
| `--depth D` | `1` | 目录扫描深度；`--depth 2` 能同时看到 `/var` 和 `/var/lib/docker` |
| `--min-size SIZE` | 无 | 过滤小于阈值的条目，如 `--min-size 100M`；必须带 `K`/`M`/`G` 后缀，缺单位报错提示（避免纯数字歧义） |
| `--no-interactive` | — | TTY 下也强制纯输出（管道/CI 本来就不进交互） |

现有调用 `top`、`top /home`、`top --count 20` 行为不变（输出格式微调见下）。

## 二、扫描内核（跨平台重写）

- **`du -k -d <depth> <路径>`** 统一 macOS（BSD du）/ Linux（GNU du）：输出
  `KB<TAB>路径`，纯数字 + tab 分隔。相比 `path/*` 通配：覆盖隐藏目录、空格路径天然安全。
  排除包含路径自身的第一行。
- **排序 `sort -k1,1 -rn`**：纯数字 KB 排序，不再依赖 `sort -h`，也使 `--min-size`
  和精确格式化成为可能。
- **`_fmt_kb` 纯函数**：KB → 人类可读。`≥1G` 显示 `1.2G`（一位小数）；`≥1M` 显示
  `123M`；未设 `--min-size` 时的小条目显示 `456K`。对齐列宽输出。
- **降级**：`du -d` 不被支持时（极老 BusyBox），回退 depth=1 行为：对
  `"$path"/*` 与 `"$path"/.[!.]*`（显式排除 `.`/`..`，覆盖隐藏目录）逐项 `du -sk`，
  2>/dev/null 吞不存在的 glob，stderr 提示一次「当前 du 不支持深度扫描，已回退单层」。
- **sudo**：延续现状——仅初始路径为 `/` 时整个会话的 du/find 统一加 sudo 前缀
  （一次授权全程有效，交互下钻不重复弹密码）。
- 深层扫描可能耗时，保留现有「正在扫描…」提示。

## 三、大文件榜（语义修正）

- 路径 ≠ `/`：`find <路径> -type f -size +50M`（含隐藏文件），`du -k` 取大小，
  同样数字排序 + `_fmt_kb` 输出 Top N。
- 路径 = `/`：保留现有常见位置清单（Linux: `/var/log` `/tmp` `/var/cache`；
  macOS: `/var/log` `/tmp` `~/Library/Logs` `~/Library/Caches`）。
- 交互模式下只在顶层打印文件榜；下钻层只刷目录榜（避免每次重扫大文件）。

## 四、交互模式（智能 TTY）

- 触发：`[ -t 1 ]`（stdout 为 TTY）且未给 `--no-interactive`。管道/CI/AI agent
  自动退化为纯输出，零负担。
- 每轮目录榜输出后显示提示符并 `read`：

  ```
  序号=下钻该目录  u=上一层  c=改数量(当前 10, 如 10/20/30/50)  q=退出
  ```

- 路径栈（bash 数组，存「路径+深度」）：序号下钻 push 新路径且 depth 重置 1；
  `u` pop 恢复上一层路径与其原 depth。count 为全局状态，`c` 进入输入提示
  （展示当前值，回车保留，接受任意正整数）；栈底再 `u` 给无操作提示。
  非法输入（非数字/越界/非正整数 count）重新提示不退出；EOF（Ctrl-D）安全退出。
- 交互内目录榜重绘带当前路径标题，空目录/无权限目录给出提示而非空屏。

## 五、文档与测试

- `usage()`、`README.md` 同步新参数与 10/20/30/50 示例；`.manifest` 不动。
- `_fmt_kb`、参数解析、min-size 过滤为纯函数，配 stub du/find 输入的单测，
  挂进 `tests/ci_run.sh`（仿 disk 模块护栏纯函数测试模式）。
- CI 增加只读 routing 断言：临时 fixture 目录跑 `top --no-interactive`，
  断言输出含路径与 `M`/`K` 单位、退出码 0。
- 质量门：`bash -n` + `shellcheck` 干净。
- 实测：macOS 本机交互流；murphy-server（Ubuntu 26.04，SSH 免密）Linux 侧
  `--depth`/`--min-size`/管道纯输出。

## 六、风险与边界

- `du -k -d` 在符号链接、.bindfs 等场景双计属 du 语义，不做特殊处理（与现状一致）。
- `/` 深扫慢是客观现实：文档标注 `--depth` 越深越慢，交互模式本身缓解（先看一层再下钻）。
- CI 容器（BusyBox）走降级路径，routing 断言只验证「能出结果」不验证格式细节。
