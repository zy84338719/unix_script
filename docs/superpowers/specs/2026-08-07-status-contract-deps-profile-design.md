# 设计：status 契约统一 + 依赖图 + 配置可重现（阶段 A + E + D）

**日期**: 2026-08-07
**状态**: 待实施
**作者**: brainstorming 会话产出
**范围**: 本次会话推进 A（status 契约）→ E（依赖图）→ D（export/apply 可重现部署）

---

## 背景与动机

unix_script 已是 52 模块、注册表驱动、有 bootstrap/CI/scaffold/doctor 的成熟项目。但三个相邻能力缺口限制了可用性的下一级跃升：

1. **status 输出无契约**：52 个模块各自输出自由格式中文 + emoji + 颜色，`--status-json` 靠 7 层 if-grep 反向猜测关键词，脆弱且不一致。
2. **模块依赖未声明**：minikube 隐式依赖 docker、grafana 可配 prometheus，但 manifest 无 `REQUIRES`，安装时不自动装前置，也无法拓扑排序。
3. **不可重现**：换机器/重装要回忆「装了什么」逐个点，没有可导出清单，没有一键复现。

三者有依赖关系：D（export/apply）需要 A（统一 status 判断已装）和 E（拓扑序安装），故按 A → E → D 顺序推进。

---

## 阶段 A：status 输出契约统一

### A.1 目标

- 每个模块的 `status` 子命令在被请求时输出**规范机器可读状态码**，同时保持人类可读输出向后兼容。
- `--status-json` 不再靠正则猜测，直接读规范字段。
- CI 校验契约，防止回归。

### A.2 规范状态码（有限状态集）

| 状态码 | 含义 | 适用场景 |
|--------|------|---------|
| `not_installed` | 未安装 | 通用 |
| `installed:running` | 已安装且服务运行中 | 服务类（docker/nginx/redis） |
| `installed:stopped` | 已安装但服务未运行 | 服务类 |
| `installed` | 已安装（无服务概念） | CLI 工具（bun/go/brew） |
| `configured` | 已配置 | 配置类（sys-setup/bbr/swap） |
| `not_configured` | 未配置 | 配置类 |
| `n/a` | 当前平台不适用 | 仅 Linux / 仅 macOS 的模块 |

### A.3 双轨输出协议（环境变量切换）

模块的 `status` 子命令通过环境变量 `UXS_STATUS_MODE` 决定输出模式：

- **`UXS_STATUS_MODE=human`（默认）**：保持现有 emoji + 中文 + 颜色输出，向后兼容。
- **`UXS_STATUS_MODE=machine`**：输出规范字段行，无颜色无 emoji：
  ```
  STATE=<状态码>           # 必填
  VERSION=<版本>           # 可选
  EXTRA=<附加信息>         # 可选，键值对（registry=cn; port=8080）
  ```

人类模式输出**零变化**，这是向后兼容的核心。

### A.4 辅助函数（lib/common.sh 新增）

```bash
# 人类模式输出 $2（含颜色/emoji）；机器模式输出 STATE=$1
emit_status() {
    local state="$1" human_msg="$2"
    if [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]; then
        printf 'STATE=%s\n' "$state"
    else
        echo -e "$human_msg"
    fi
}
# 仅机器模式输出 VERSION= 行
emit_version() {
    [[ "${UXS_STATUS_MODE:-human}" == "machine" ]] && printf 'VERSION=%s\n' "$1"
}
# 仅机器模式输出 EXTRA= 行（可多次调用，机器模式下每次一行 EXTRA=）
emit_extra() {
    [[ "${UXS_STATUS_MODE:-human}" == "machine" ]] && printf 'EXTRA=%s\n' "$1"
}
```

### A.5 改造模式（每个模块）

**改造前**（bun）：
```bash
status_bun() {
    if command_exists bun || [[ -x "$BUN_DIR/bin/bun" ]]; then
        local ver; ver=$(bun --version 2>/dev/null || echo "")
        echo -e "${GREEN}✅ 已安装${NC} ${ver:+(v$ver)}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
    local cur_reg="(默认官方源)"
    # ... 解析 registry ...
    echo "   registry: $cur_reg"
}
```

**改造后**：
```bash
status_bun() {
    if command_exists bun || [[ -x "$BUN_DIR/bin/bun" ]]; then
        local ver; ver=$(bun --version 2>/dev/null || echo "")
        emit_status "installed" "${GREEN}✅ 已安装${NC} ${ver:+(v$ver)}"
        emit_version "$ver"
        local cur_reg="(默认官方源)"
        # ... 解析 registry ...
        emit_extra "registry=$cur_reg"
        [[ "${UXS_STATUS_MODE:-human}" == "human" ]] && echo "   registry: $cur_reg"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
        emit_extra "registry=(默认官方源)"
    fi
}
```

**注意**：`echo "   registry: $cur_reg"` 这类纯人类辅助行需用 `[[ ... == human ]]` 守卫，避免污染机器输出。helper 函数内部已自带守卫，直接用 helper 输出的内容无需额外守卫。

### A.6 module_status() 重写（lib/status.sh）

```bash
module_status() {
    local mod="$1"
    local entry_script mod_path
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    local script="$SCRIPT_DIR/$mod_path/$entry_script"
    if [[ ! -f "$script" ]]; then
        emit_status "not_installed" "${RED}❌ 脚本不存在${NC}"
        return
    fi
    # 交互式/人类可读总览：调用人类模式
    bash "$script" status 2>/dev/null || echo "查询失败"
}

# 新增：机器模式查询，返回 STATE 值（供 status-json / export / health 复用）
module_status_machine() {
    local mod="$1"
    local entry_script mod_path
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    local script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>/dev/null \
        | sed -n 's/^STATE=//p' | head -1
}
```

### A.7 show_status_json() 重写（lib/menu.sh）

删掉 7 层 if-grep，改为：
```bash
show_status_json() {
    detect_os; detect_arch
    echo "os:$OS_TYPE"
    echo "arch:$ARCH_TYPE"
    echo "version:$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
    local mod state version extra raw
    for mod in $_REGISTRY_MODULES; do
        raw=$(module_status_raw "$mod")   # 见下
        state=$(echo "$raw" | sed -n 's/^STATE=//p' | head -1)
        version=$(echo "$raw" | sed -n 's/^VERSION=//p' | head -1)
        extra=$(echo "$raw" | sed -n 's/^EXTRA=//p' | head -1)
        # 组装输出行，保留现有 key:value 格式
        local line="$mod:$state"
        [[ -n "$version" ]] && line="$line:$version"
        printf '%s\n' "$line"
        # extra 暂不进 status-json 主行（避免破坏现有解析者），后续 health 复用
    done
}
# module_status_raw: 返回完整机器模式原始输出
module_status_raw() {
    local mod="$1" entry_script mod_path script
    entry_script=$(registry_entry_script "$mod"); mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "STATE=not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>/dev/null
}
```

输出格式与现状保持一致（`docker:installed:running` / `bun:installed:v1.3.14`），**现有 AGENTS.md 文档里描述的格式不变**，只是获得方式从猜测变成精确读取。

### A.8 CI 契约校验（tests/ci_run.sh）

新增静态/路由阶段的检查项：
```bash
# status 契约校验：每个模块在 machine 模式下首行必须 STATE= 且值在有限集
check_status_contract() {
    local valid="not_installed installed:running installed:stopped installed configured not_configured n/a"
    for mod in $(_all_modules); do
        local first
        first=$(UXS_STATUS_MODE=machine bash "$mod_path/install.sh" status 2>/dev/null | head -1)
        if [[ "$first" != STATE=* ]]; then
            fail "$mod: machine 模式首行不是 STATE= （实际: $first）"
        fi
        local val="${first#STATE=}"
        echo " $valid " | grep -q " $val " || fail "$mod: 状态码 '$val' 不在有限集"
    done
}
```

加入 routing 阶段（不实装，只跑 status），快速、低风险。

### A.9 验收标准

- [ ] 52 个模块的 status 函数全部改造为 emit_status 模式
- [ ] `UXS_STATUS_MODE=machine <module> status` 首行均为合法 `STATE=`
- [ ] 默认（人类）模式输出与改造前**逐字一致**（抽样比对）
- [ ] `--status-json` 输出格式与现状一致，但不再含猜测逻辑
- [ ] CI 契约校验通过

---

## 阶段 E：模块依赖图（manifest 声明 REQUIRES）

### E.1 目标

- manifest 声明模块依赖，安装时自动装前置，profile apply 时按拓扑序安装。
- 检测循环依赖并报错。

### E.2 manifest 扩展

新增字段：
```
REQUIRES=docker,k7s      # 逗号分隔的模块名（正式名或别名均可）
```

`registry.sh` 的 `_parse_manifest` 增加 `REQUIRES)` 分支，新增查询 API：
```bash
registry_requires() { _reg_get "$1" REQUIRES; }
```

### E.3 依赖解析（新增 lib/deps.sh）

```bash
# 返回某模块的完整依赖链（含传递依赖），拓扑有序（被依赖者在前）
# 用法: resolve_deps <模块名> → 输出模块名列表，每行一个
resolve_deps() {
    local mod="$1"
    # bash 3.2 兼容：用空格分隔字符串模拟 visited 集合与结果列表（无关联数组）
    _RESOLVE_VISITED="" _RESOLVE_RESULT=""
    _resolve_deps_visit "$mod"
    # 输出 _RESOLVE_RESULT（不含 mod 自身）
}

# 全拓扑排序：所有声明了 REQUIRES 的模块 + 其依赖，返回安全安装序
topo_sort_all() { ... }
```

实现要点（bash 3.2 兼容）：
- 用空格分隔字符串模拟 visited 集合（`[[ " $visited " == *" $m "* ]]`）
- DFS 后序输出 = 拓扑序
- 检测回边（访问中再次遇到）→ 报循环依赖错误

### E.4 install 调度增强

`dispatch_module`（install.sh）改造：
```bash
dispatch_module() {
    local name="$1"
    # ... 解析、校验 ...
    # 新增：解析依赖并自动安装未装的
    if [[ "${UNIX_SCRIPT_NO_DEPS:-0}" != "1" ]]; then
        local deps
        deps=$(resolve_deps "$resolved")
        for d in $deps; do
            if [[ "$(module_status_machine "$d")" == "not_installed" || ... ]]; then
                info "自动安装依赖: $d"
                run_in_dir "$(registry_path "$d")" install.sh install
            fi
        done
    fi
    # ... 原有 install 调用 ...
}
```

新增全局开关：
- `--no-deps`：跳过自动装依赖
- `UNIX_SCRIPT_NO_DEPS=1` 环境变量：同上（CI/脚本场景）

### E.5 --list-modules 增强

输出增加 requires 列（仅当有依赖时显示）：
```
minikube   install status help   requires: docker
docker     install status help
bun        install mirror unmirror uninstall status help
```

### E.6 循环依赖检测

`resolve_deps` 发现回边时报错退出：
```
[ERROR] 检测到循环依赖: a → b → c → a
```
CI 增加测试：构造（或用 mock）验证检测逻辑。

### E.7 初始 REQUIRES 声明

基于代码审查，首批声明依赖的模块（实施时逐一确认）：
- `minikube` → `docker`
- `gitea` → （可选 postgres，但可选依赖暂不声明，保持确定性）
- 其余模块多为独立安装，无硬依赖

**原则**：只声明「不装就必然失败」的硬依赖，不声明「搭配更好」的软依赖。

### E.8 验收标准

- [ ] manifest 支持 REQUIRES 字段
- [ ] `resolve_deps` / `topo_sort_all` 正确且检测循环
- [ ] `./install.sh minikube` 自动先装 docker（若未装）
- [ ] `--no-deps` 可跳过
- [ ] `--list-modules` 显示 requires 列
- [ ] 循环依赖被检测并报错

---

## 阶段 D：配置导出/应用（声明式可重现部署）

### D.1 目标

- `uxs export` 导出本机已装模块清单 + 关键配置，写入默认 profile 文件。
- `uxs apply <profile>` 按拓扑序复现安装，已装默认跳过，`--force` 强制重装。

### D.2 profile 格式（手编/git 友好）

```
# unix_script profile — 由 uxs export 生成 2026-08-07
# 平台: linux/arm64  版本: v3.x.x
docker
# EXTRA: installed:running (Docker version 29.6.2)

## 服务
node_exporter
fail2ban
tailscale

## 开发环境
bun mirror=cn            # 行内配置键值对
go version=1.23.0
```

格式规则：
- 每行一个模块名，`#` 起注释
- 空行忽略
- `## 标题` 纯人类分组注释（apply 忽略）
- 模块名后可跟空格分隔的 `key=value` 配置（可选）
- `# EXTRA: ...` 行是 export 写入的状态备注（apply 忽略，供人读）

### D.3 配置导出机制（模块声明 exportable 配置）

每个模块在 `.manifest` 声明可导出的配置键：
```
EXPORTABLE=mirror,port,autostart
```

模块的 status（机器模式）通过 `emit_extra "mirror=$cur"` 输出当前值。

export 时：
1. 读模块机器 status 的 `EXTRA=` 行
2. 按 EXPORTABLE 声明的键过滤
3. 写入 profile 的 `模块名 key1=v1 key2=v2`

apply 时：
1. 解析行内 `key=value`
2. 调用模块的 install 时透传配置（约定：模块 install 读取 `UXS_CONFIG_<KEY>` 环境变量）
   - 例：`UXS_CONFIG_MIRROR=cn ./install.sh bun install`
   - 模块 install 检测到该环境变量则用它，否则用默认

**为避免一次性改 52 个模块的 install**：本次只给少数有意义的模块实现配置透传（bun/mirror、dev-mirror、可能 nginx/port）。其余模块 export 只写模块名（无配置），apply 时纯安装。这是渐进的、不阻塞 D 闭环。

### D.4 export（lib/profile.sh 新增）

```bash
DEFAULT_PROFILE_DIR="$HOME/.config/unix_script"
DEFAULT_PROFILE_FILE="$DEFAULT_PROFILE_DIR/profile.txt"

export_profile() {
    local out="${1:-$DEFAULT_PROFILE_FILE}"
    mkdir -p "$(dirname "$out")"
    {
        echo "# unix_script profile — 由 uxs export 生成 $(date +%F)"
        detect_os; detect_arch
        echo "# 平台: $OS_TYPE/$ARCH_TYPE  版本: $(get_local_version)"
        local mod state raw
        for mod in $_REGISTRY_MODULES; do
            state=$(module_status_machine "$mod")
            case "$state" in
                installed*|configured)
                    echo "$mod"
                    raw=$(module_status_raw "$mod")
                    local extra; extra=$(echo "$raw" | sed -n 's/^EXTRA=//p' | head -1)
                    [[ -n "$extra" ]] && echo "# EXTRA: $state ($extra)"
                    ;;
            esac
        done
    } > "$out"
    success "已导出到 $out"
}
```

### D.5 apply（lib/profile.sh 新增）

```bash
apply_profile() {
    local file="${1:-$DEFAULT_PROFILE_FILE}"
    local force=0 dry=0
    # 解析 --force / --dry-run（从剩余参数）
    [[ ! -f "$file" ]] && { error "profile 不存在: $file"; return 1; }

    # 1. 解析模块列表（忽略注释/空行，提取 key=val 配置）
    #    实现细节：_parse_profile 把每行 "模块名 k1=v1 k2=v2" 解析后
    #    存入以模块名为键的并行字符串数组（bash 3.2 兼容），供后续读取
    _parse_profile "$file"

    # 2. 拓扑排序（复用 E 的 topo_sort_all，只排 profile 内出现的模块）
    #    实现细节：_topo_sort_profile_mods 调用 topo_sort_all 后过滤出 profile 集合
    local ordered; ordered=$(_topo_sort_profile_mods)

    # 3. 逐个安装
    local rc_ok=0 rc_skip=0 rc_fail=0
    for mod in $ordered; do
        local state; state=$(module_status_machine "$mod")
        if [[ "$force" == 0 ]] && [[ "$state" == installed* || "$state" == configured ]]; then
            info "跳过 $mod（已装）"; rc_skip=$((rc_skip+1)); continue
        fi
        # 注入配置环境变量（实现细节：_export_config_to_env 把 profile 行内的
        # key=val 转成 UXS_CONFIG_<KEY>=<val> 导出，供模块 install 读取）
        _export_config_to_env "$mod"
        # _run_install 封装 run_in_dir + 透传，返回模块 install 退出码
        if _run_install "$mod"; then
            rc_ok=$((rc_ok+1))
        else
            rc_fail=$((rc_fail+1)); warn "$mod 安装失败"
        fi
    done
    # 4. 报告
    echo "完成: 成功 $rc_ok / 跳过 $rc_skip / 失败 $rc_fail"
    [[ $rc_fail -eq 0 ]]
}
```

### D.6 路由（install.sh + uxs_cli.sh）

`install.sh` main 增加：
```bash
export|export-profile)
    shift; export_profile "$@"; exit $? ;;
apply|apply-profile)
    shift; apply_profile "$@"; exit $? ;;
```

`lib/uxs_cli.sh` 的 uxs wrapper 已透传参数，无需改动逻辑，但 completions 要补 `export`/`apply`。

### D.7 验收标准

- [ ] `uxs export` 生成合法 profile 到默认路径
- [ ] `uxs apply <profile>` 按拓扑序安装，已装跳过
- [ ] `--force` 强制重装
- [ ] `--dry-run` 预览
- [ ] 至少 1 个模块（bun mirror）配置可导出/还原
- [ ] 无配置的模块仍能正常 export（仅模块名）/apply（纯安装）
- [ ] completions 补全 export/apply

---

## 跨阶段改动地图

| 文件 | A | E | D |
|------|---|---|---|
| `lib/common.sh` | +emit_status/emit_version/emit_extra | — | — |
| `lib/status.sh` | 重写 module_status + 新增 module_status_machine/raw | — | — |
| `lib/menu.sh` show_status_json | 删 if-grep，读 STATE= | — | — |
| `lib/registry.sh` | — | +REQUIRES/EXPORTABLE 解析、registry_requires | — |
| **`lib/deps.sh`**（新） | — | resolve_deps / topo_sort_all + 循环检测 | D 复用 topo_sort |
| **`lib/profile.sh`**（新） | — | — | export_profile / apply_profile |
| `install.sh` main | — | dispatch 注入依赖解析 + --no-deps | +export/apply 路由 |
| `lib/uxs_cli.sh` | — | — | （透传已支持，无需改逻辑） |
| `completions/uxs.{bash,zsh}` | — | — | +export/apply |
| 52 模块 install.sh | status 函数全迁移到 emit_status | 声明 REQUIRES（有硬依赖的）+ EXPORTABLE（有可导配置的） | 少数模块 install 读 UXS_CONFIG_* |
| `tests/ci_run.sh` | +status 契约校验 | +依赖拓扑/循环检测测试 | +export/apply 往返测试 |
| `AGENTS.md` / `README.md` | 文档更新（status-json 说明） | 文档更新（REQUIRES/--no-deps） | 文档更新（export/apply） |

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| 52 模块 status 改造工作量大、diff 巨大 | 全迁移是用户明确选择；按分类分批 commit（每类一个 PR/commit），便于 review |
| 人类模式输出意外变化 | CI 增加抽样快照比对（改造前后输出 diff 为空） |
| REQUIRES 声明不全导致 apply 顺序错 | 只声明硬依赖；apply 对未声明依赖的模块按 profile 原始顺序兜底 |
| 配置透传需改模块 install | 本次只给 bun 等少数模块实现，其余纯安装，不阻塞闭环 |
| bash 3.2 兼容（macOS 默认） | deps.sh 用字符串集合模拟，避免关联数组；所有新代码 bash 3.2 可用 |

## 不做（YAGNI）

- 不做软依赖（"推荐搭配"），只做硬依赖
- 不做 profile 的 schema 版本号（格式极简，必要时再加）
- 不做 export 的加密/签名（profile 是明文清单，git 友好）
- 不做 apply 的并行安装（顺序更安全、日志清晰）
- 不给所有 52 模块实现配置透传（只做有意义的少数）
- 不做 Web UI / TUI 增强 profile 编辑（文本编辑器足够）
