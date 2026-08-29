# 设计：易用性批次②——新手引导 next-step 提示 + bootstrap 尾屏精简

**日期**: 2026-08-29
**状态**: 待实现
**前置**: 批次①（2026-08-29-usability-batch1-design.md）已合入
**范围**: `.manifest` 新增 `NEXT_STEPS` 字段、安装成功后打印「下一步」引导块、scaffold 模板同步、bootstrap 尾屏文案精简

---

## 背景

2026-08-29 巡审（[[usability-batch1-landed]] 同日）：bootstrap 装完把引导一次性倒满一屏，之后装完某个服务（如 docker）没有任何「下一步建议」——新手装完不知道还能装什么配套。用户在方向澄清时选定「新手引导全程」，并确认分批交付。

## 目标

- 模块**默认安装动作成功后**，给 1-4 条针对性的「下一步」提示（配套模块、生效方式）
- 提示内容由各模块自带（manifest 单一数据源），框架只负责展示
- bootstrap 尾屏从 ~20 行减到 ≤10 行，去掉重复信息

## 非目标

- 不做交互式 wizard（2026-08-15 ux-overhaul 已裁）
- 不改机器可读输出（machine 模式下 next-step 块不打印）
- 不给子命令透传路径（如 `bun mirror`）加提示——只引导「安装后」

## 方案

### ① `.manifest` 可选字段 `NEXT_STEPS=`

- 分号 `;` 分隔的多条提示（单行值，避免多行解析）；条目即面向用户的完整句子
- 例：`NEXT_STEPS=装 dev-tui 获得 lazydocker/lazygit:./install.sh dev-tui;装 docker-image 离线导出镜像:./install.sh docker-image`
  - 条目内再以半角冒号 `:` 分隔「说明:命令」（命令部分可省略）
- `lib/registry.sh`：`_parse_manifest` 白名单加 `NEXT_STEPS)`；初始化空值；新增 `registry_next_steps <mod>`
- `lib/scaffold.sh` 模板加 `NEXT_STEPS=` 注释占位行（可选字段说明）

### ② 框架展示 `show_next_steps <mod>`（lib/menu.sh）

- 仅当：registry 有 NEXT_STEPS、`uxs_is_machine_mode` 为假、非 `UNIX_SCRIPT_DRY_RUN=1`（预览不引导）
- 输出形态：

```
💡 下一步：
   • 装 dev-tui 获得 lazydocker/lazygit → ./install.sh dev-tui
   • 装 docker-image 离线导出镜像 → ./install.sh docker-image
```

- 带冒号命令的条目渲染 `说明 → 命令`；无冒号条目整句作为 `• 整句`

### ③ install.sh 接入

- `dispatch_module` 中 `run_in_dir` 改为捕获 rc：成功（rc=0）且 default action 首词为 `install` 时，打印 `show_next_steps "$resolved"`，最后 `return $rc`
- 子命令透传（`dispatch_module_or_passthrough` 的 passthrough 分支）不接

### ④ 首批 manifest 接线（6 个模块）

| 模块 | NEXT_STEPS（草拟，实现时按实际命令核对） |
|---|---|
| docker | 装 dev-tui 获得 lazydocker/lazygit；装 docker-image 离线导出镜像 |
| bun | 装 pnpm 补全包管理；换国内镜像加速 |
| nvm | 装特定版本后 `nvm use`；装 pnpm |
| zsh_setup | 新开终端或 `exec zsh` 生效 |
| modern-cli | 新开终端生效；装 zsh_setup 组合终端体验 |
| dev-enhance | 新开终端生效 |

### ⑤ bootstrap 尾屏精简

- 现状 outro ~20 行：同一条 curl 命令出现 3 次、透传示例 4 行、目录/更新/uxs 各一段
- 精简为 ≤10 行：克隆位置 + `./install.sh` 菜单一条、uxs 一条（含 source 提示）、更新命令仅出现一次、透传示例压缩成 1 行

## 测试

1. registry 解析：NEXT_STEPS 含分号/冒号的值拆分正确（单测，仿 unit_platform 模式入 unit_usability.sh 或新 unit_next_steps.sh——入现有 unit_usability.sh）
2. show_next_steps：有人类模式输出块、machine 模式零输出、无 NEXT_STEPS 模块零输出、dry-run 零输出
3. 路由：`--dry-run docker` 输出不含「下一步」
4. shellcheck + bash 3.2 + 全量 static/routing

## 文件改动清单

| 文件 | 动作 |
|---|---|
| `lib/registry.sh` | NEXT_STEPS 解析 + `registry_next_steps` |
| `lib/menu.sh` | `show_next_steps` |
| `install.sh` | dispatch 成功后接入 |
| `lib/scaffold.sh` | 模板占位 |
| 6 个模块 `.manifest` | NEXT_STEPS 内容 |
| `bootstrap.sh` | 尾屏精简 |
| `tests/unit_usability.sh` | 新测试段 |
| `README.md` `CHANGELOG.md` | manifest 格式 + 记录 |

## 风险

| 风险 | 缓解 |
|---|---|
| manifest 中文分号/冒号混排解析错 | 只认半角 `;` `:`，文档写明；单测覆盖 |
| dry-run/机器模式误打印 | show_next_steps 内部三重 gate + 单测 |
| bootstrap 文案删过头 | 保留幂等更新命令、uxs、菜单三条主路径 |
