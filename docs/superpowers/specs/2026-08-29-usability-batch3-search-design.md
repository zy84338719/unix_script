# 设计：易用性批次③——`uxs search <关键字>` 命令行模块搜索

**日期**: 2026-08-29
**状态**: 待实现
**前置**: 批次①已合入；批次② NEXT_STEPS 同分支进行中
**范围**: 框架级模块搜索子命令（模块名/别名/LABEL/DESC）、bash+zsh 补全、文档

---

## 背景

2026-08-29 巡审：`uxs search <关键字>` 不存在（grep 证实），命令行发现模块只能 `--list-modules | grep`，丢掉了 LABEL/DESC/别名的语义。fzf 菜单有模糊搜索，但脚本化/远程/无 TTY 场景没有等价物。用户方向澄清时选定，分批交付排第三批。

## 目标

- `./install.sh search <关键字> [关键字...]`：全注册表搜索，多关键字 **AND**（全部命中才列出），大小写不敏感子串匹配
- 匹配域：模块名 + 别名 + LABEL + DESC（拼接后匹配）
- 人类输出按分类分组；机器模式（`UXS_STATUS_MODE=machine`）输出 TSV（模块名 + DESC），AI/脚本可解析
- 无匹配退出 1（脚本可判定）；缺关键字退出 1 并给用法

## 非目标

- 不做正则/模糊编辑距离（did-you-mean 已有 suggest.sh，仅用于未知模块纠错）
- 不动菜单/补全的模块级搜索

## 方案

### ① registry 层查询（lib/registry.sh）

```bash
registry_search <关键字...>   # 输出命中模块名（换行分隔，注册表序）；无匹配输出空
```

- 实现：遍历 `$_REGISTRY_MODULES`，对每个模块拼 `mod + aliases + LABEL + DESC`（转小写），所有关键字逐一 `contains` 判定（bash 3.2 无 `${hay,,}`？——bash 4 特性，改用 `tr '[:upper:]' '[:lower:]'` 预生成小写串）
- 关键字同样转小写后匹配

### ② 展示层（lib/menu.sh）

`show_search_results <关键字...>`：

- 人类模式：按分类分组，行格式 `  <模块名>  <LABEL> — <DESC>  [别名: a,b]`（无 DESC 显示 LABEL，无别名省略方括号段）；组头 `[分类]`
- 机器模式：每行 `模块名<TAB>DESC`（与 `--list-modules` 第 3 列同源，无 DESC 空）
- 末尾打一条总数提示（`n 个匹配`，人类模式）

### ③ install.sh 接入 + 退出码

- `case` 加分支：
  - `search)`：`shift` 后无参数 → `error "用法: ./install.sh search <关键字> [关键字...]"` exit 1；否则 `show_search_results "$@"`，无匹配 exit 1，有匹配 exit 0
- 无匹配的 warn 信息给替代建议：`试试更短的关键字，或 ./install.sh --list-categories 看全部`

### ④ 补全（completions/）

- `uxs.bash:27` globals 串加 `search`
- `uxs.zsh` 全局命令描述列表加 `'search:搜索模块（名称/别名/描述）'`

### ⑤ 文档

- README「信息查询」表加一行 search 示例
- AGENTS.md AI 工作流节：`--list-modules` 后补 `./install.sh search <关键字>` 更精准
- CHANGELOG `[Unreleased]` Added

## 测试

1. `registry_search`：单关键字命中（模块名/别名/DESC 各一例）、多关键字 AND（都中/一不中）、大小写不敏感、无命中空输出
2. `show_search_results`：人类模式行含 `—` 与别名段、机器模式 TSV 两列、无匹配 rc=1、缺关键字 rc=1
3. 路由：`./install.sh search docker` 退出 0 且含 docker；`./install.sh search`（无参）退出 1
4. shellcheck + bash 3.2 + 全量 static/routing

## 文件改动清单

| 文件 | 动作 |
|---|---|
| `lib/registry.sh` | `registry_search` |
| `lib/menu.sh` | `show_search_results` |
| `install.sh` | `search)` 分支 |
| `completions/uxs.bash` `uxs.zsh` | 命令清单 |
| `tests/unit_usability.sh` | 测试段 |
| `README.md` `AGENTS.md` `CHANGELOG.md` | 文档 |

## 风险

| 风险 | 缓解 |
|---|---|
| bash 3.2 无 `${var,,}` 小写化 | `tr` 预生成小写串；CI macOS 腿（bash 3.2）验证 |
| 中文 DESC 大小写无意义但 tr 不影响 | 纯子串匹配天然兼容 |
| search 退出码 1 被误当错误 | README/AGENTS 写明语义（无匹配=1） |
