# AGENTS.md

本文件供 AI agent（Claude Code / Cursor / Copilot / opencode / Pi 等）阅读，说明如何使用 unix_script 脚本库。

## 这是什么

unix_script 是一个 macOS/Linux 脚本库，提供 78 个模块的安装、配置与管理。每个模块支持统一的子命令接口。

模块按功能分类组织在子目录中：

| 分类目录 | 说明 | 模块数 |
|----------|------|--------|
| `services/` | 服务类（Web/数据库/监控/VPN/管理面板 等） | 33 |
| `essentials/` | 装机必备（基础工具/系统初始化） | 6 |
| `dev-tools/` | 开发环境（语言/编辑器/工具链） | 19 |
| `ai-tools/` | AI 工具（大模型/编程助手） | 3 |
| `sys-tools/` | 系统工具（安全/网络/备份/进程管理） | 16 |

## 快速调用（AI agent 友好）

### 列出所有模块

```bash
./install.sh list
# 输出：空格分隔的模块名
# node_exporter ddns-go wireguard tailscale docker ...
```

### 机器可读的模块清单（含子命令）

```bash
./install.sh list --full
# 输出 TSV：模块名\t支持子命令[  requires:...]\t描述
# node_exporter	install uninstall status help	Prometheus 系统指标收集器
# bun	install mirror unmirror uninstall status help	Bun 运行时（含国内镜像加速）
# minikube	install uninstall status help  requires:docker	本地 Kubernetes 开发环境
```

第 3 列为 `.manifest` 的 `DESC`（一句话中文描述；无描述的模块该列为空）。前两列语义与历史版本一致。

### 按分类列出模块

```bash
./install.sh list --grouped
# 输出：按分类分组的模块列表（服务/装机必备/开发环境/AI工具/系统工具）
```

### 机器可读状态

```bash
./install.sh status --json
# 输出 key:value（每行一个，无颜色无 emoji）
# node_exporter:not_installed
# docker:installed:running
# bun:installed:v1.3.14
```

输出首部固定 3 行框架元数据（AI 解析时跳过前 3 行，或按 key 是否为模块名判断）：

```
os:darwin       # 宿主 OS（darwin/linux）
arch:ARM64      # CPU 架构
version:1.21.0  # unix_script 自身版本
```

状态码含义（state 字段）：

| 状态码 | 含义 |
|--------|------|
| `not_installed` | 未安装 |
| `installed` | 已安装（无服务概念，如 CLI 工具） |
| `installed:running` | 已安装且服务运行中 |
| `installed:stopped` | 已安装但服务未运行 |
| `configured` | 已配置（配置类模块） |
| `not_configured` | 未配置 |
| `n/a` | 当前平台不适用 |

自 v1.15.0 起，`status --json` 默认仅输出**本机适用**的模块（平台不适用的模块被隐藏，正常输出中不出现 `n/a` 行）。需要全量清单（含不适用模块）时：

```bash
UNIX_SCRIPT_SHOW_ALL=1 ./install.sh status --json
```

### 安装/操作模块

```bash
# 非交互安装某模块（AI 推荐方式）
./install.sh <模块名>           # 默认动作（通常=install）
./install.sh <模块名> install   # 显式安装
./install.sh bun mirror         # 模块子命令透传
./install.sh install <模块名> --no-deps # 安装但跳过依赖自动安装（阶段 E）

# 示例
./install.sh docker             # 安装 Docker
./install.sh minikube           # 安装 minikube（自动先装其依赖 docker）
./install.sh fail2ban           # 安装 Fail2ban
./install.sh sys-setup all      # 全部系统初始化配置
./install.sh bun mirror         # Bun 换国内镜像源
```

### 模块依赖与配置复现（阶段 E + D）

**依赖图（阶段 E）**：模块可在 `.manifest` 中声明 `REQUIRES=<模块名>[,...]`。安装时框架自动先装缺失的依赖（拓扑序），循环依赖会被检测并报错。`list --full` 对有依赖的模块追加 `requires:...` 列。

```bash
./install.sh install minikube --no-deps   # 跳过自动装依赖
UNIX_SCRIPT_NO_DEPS=1 ./install.sh minikube   # 等价环境变量
```

**配置复现 / profile（阶段 D）**：把"哪些模块已装 + 关键配置"导出为可 git 的纯文本 profile，在新机器一键复现。模块用 `EXPORTABLE=<key>[,...]` 声明可导出的配置键（其 `status` 用 `emit_extra "key=value"` 输出当前值）。

```bash
./install.sh export                  # 导出到 ~/.config/unix_script/profile.txt
./install.sh export --out /path/profile  # 导出到指定文件
./install.sh apply                   # 应用默认 profile（已装模块跳过）
./install.sh apply /path/profile --force    # 强制重装
./install.sh apply /path/profile --dry-run  # 预览
```

profile 行格式：`<模块名> [key=value ...]   # 注释`。apply 时把 `key=value` 注入为 `UXS_CONFIG_<KEY>` 环境变量传给模块 install（模块自行读取，如 bun 读 `UXS_CONFIG_REGISTRY`）。

### 平台可见性（PLATFORMS 声明 + SHOW_ALL）

模块可在 `.manifest` 中声明适用 OS：`PLATFORMS=linux[,darwin]`（缺省 = 全平台适用）。
不适用当前系统的模块默认从**所有出口**隐藏：`list` / `list --full` / `list --grouped` /
`search` / 交互菜单（bash 与 fzf）/ 卸载菜单 / `status` / `status --json` / `export`。

- 直接安装不适用模块（如 macOS 上 `./install.sh ufw`）被框架拦截，给出解释性报错与恢复指引
- `apply` profile 时跳过本机不适用行（profile 可跨机器携带）
- `UNIX_SCRIPT_SHOW_ALL=1` 恢复全量显示（对上述所有出口生效）
- 绕过 install.sh 直接调用模块路径时，模块内部平台检查仍生效（输出 n/a / 报错，纵深防御）

### 去除颜色（管道/日志场景）

所有输出支持 `NO_COLOR=1` 环境变量（或管道自动检测）：

```bash
NO_COLOR=1 ./install.sh status
./install.sh status --json       # status --json 始终无颜色
```

### 调试模式

`UXS_DEBUG=1` 会把库内原本静默的 stderr（`2>/dev/null`，如 GitHub API 请求/解析失败）透出到终端，便于排查：

```bash
UXS_DEBUG=1 ./install.sh update --check
```


### CLI v2：旧写法已删除（无兼容期）

CLI 一次性切换到分组子命令面，旧扁平写法**全部删除**。命中旧写法会报错退出（退出码 2 = 用法错）并给一行迁移指引 —— 命令照样失败，**不是兼容路径**。

| 旧写法 | 新写法 |
|---|---|
| `--list` | `uxs list` |
| `--list-modules` | `uxs list --full` |
| `--list-categories` | `uxs list --grouped` |
| `--status` | `uxs status` |
| `--status-json` | `uxs status --json` |
| `--dry-run <模块>` | `uxs install <模块> --dry-run` |
| `--no-deps <模块>` | `uxs install <模块> --no-deps` |
| `check-update` | `uxs update --check` |
| `export` / `export-profile` | `uxs export [--out 文件]` |
| `apply` / `apply-profile` | `uxs apply <profile>` |
| `cli` / `install-cli` | `uxs cli install` |
| `uninstall-cli` / `remove-cli` | `uxs cli uninstall` |
| `completions` | `uxs completions [shell]` |
| `scaffold` / `doctor` / `update` | 同名分组命令（`uxs scaffold` / `uxs doctor` / `uxs update`） |

新增：`uxs info <模块>`（模块明细：标签/分类/依赖/子命令/适用平台）、`uxs --list-all`（全量 TSV 清单，含平台不适用）。

## 文案国际化（i18n）

面向用户的中文文案一律用 `_t` 包装；msgid 一律英文，译文在 `locale/zh_CN/LC_MESSAGES/unix_script.po`。

| Helper | 用法 | 说明 |
|--------|------|------|
| `_t 'msgid'` | `_t 'Cancelled'` | 查译文；查不到就原样输出 msgid（英文） |
| `_tf 'msgid' ARG...` | `_tf 'Unknown action: %s' "$action"` | **带变量时用这个** —— 译文当 printf 格式串，占位符按参数填 |

### 十条硬规则

1. **带变量的文案用 `_tf`，不要写 `printf "$(_t '...%s...')" "$x"`**
   后者会被 shellcheck 判成 SC2059（格式串是变量）。`_tf` 把这件事收口到一处。
2. **变量前面不要加反斜杠**
   双引号里的 `\${VAR}` 输出的是字面量，不是变量值 —— 错误消息会变成「未知操作: ${action}」，
   状态色码 `\${YELLOW}` 也不生效。同理 heredoc 里的 `$0` 不要转义（那是脚本路径）。
3. **`||` 分支里不能直接放 `$(...)`**
   `cmd || $(_t 'x')` 里的命令替换会被当**命令执行**（SC2091，真 bug）。
   写 `cmd || printf '%s' "$(_t 'x')"`。
4. **`echo "$(_t ...)"` 改成 `printf '%s\n' "$(_t ...)"`**
   shellcheck 判 SC2005（style 级，门禁不看 `-S`，所以会红）；
   而且 echo 会误处理内容（`-n` 被当选项、开头是反斜杠时各 shell 行为不同）。
5. **emoji 不要写进 msgid**
   emoji 是装饰，留在译文里（`msgstr`）或留在 `_t` 外面（`"🚀 $(_t '...')"`）都行，
   但**不要**把它音译成 `Rocket` / `Party popper` 塞进英文 msgid —— 那是重复，
   译文灌错时用户看到的就是「Rocket 开始安装」而不是 🚀。
6. **heredoc 里 `#` 在 `_t` 之前 ⇒ 这个 msgid 根本抽不出来**
   xgettext 扫 heredoc 正文时按 shell 注释处理，`#` 之后的内容不抽 ——
   msgid 不进 po，运行时静默回落英文（看起来「翻译了但还是英文」）。
   修法：把 `#` 挪进 `_t` 的参数里（`$(_t '# 初始化 eth1 策略路由')`），输出逐字不变。
   **`echo "  # $(_t '...')"` 不受影响** —— 那是双引号里的字符，不是注释。
7. **同英文对应不同中文 ⇒ msgid 必须更具体**
   一个 msgid 只能有一条译文。中文一字之差（「已安装并运行」vs「已安装且正在运行」、
   「显示本帮助」vs「显示此帮助」）就是两条 msgid，要写得更具体而不是共用一条。
   灌译文只填空、**不覆盖已有译文** ⇒ 撞车时先看到的是旧译文，必须主动改 msgid。
8. **行尾注释里的中文会被漂移门禁拦**
   门禁只豁免**整行**注释（行首空白 + `#`），`cmd   # 中文注释` 仍算硬编码中文。
   把行尾注释挪成整行注释（注释内容一字不改）。
9. **写配置文件用的 quoted heredoc（`<<'EOF'`）里的内容不能进 `_t`**
   quoted heredoc 原样写进文件，`$(_t '...')` 会变成字面量留在配置里。
   这类 heredoc 里的注释改成英文；unquoted heredoc（`<<EOF`）里的 `$(_t ...)`
   会在写文件时展开，可以翻译。
10. **命令替换（`$(...)`）不能进译文**
    译文在单引号里，`$(pwd)` 会被原样打印出来，输出就变了。
    改用变量：`$(pwd)` → `$PWD`（bash 里同值），变量记 `%s`。

### 改完必须做的两件事

- **与迁移前的输出逐字比对**：
  ```bash
  git show <base>:services/<mod>/install.sh > /tmp/base/services/<mod>/install.sh
  cp -R lib vendor /tmp/base/          # 让旧版能跑起来
  # 同样的命令、同样的 locale，两边跑，diff —— 只该差 $0 的路径
  ```
  这类缺陷（变量被转义、译文串到别的模块）肉眼扫代码看不出来，只有比对能发现。
- **跑门禁**：
  | 门禁 | 查什么 |
  |------|--------|
  | `bash tools/check_i18n_drift.sh <分类>` | 源码里没有残留硬编码中文 |
  | `bash tools/check_i18n_cross.sh` | 译文没串到别的模块 |
  | `bash tools/check_i18n_equiv.sh` | **译文与迁移前原文对得上**（不漏字、不吞 emoji） |
  | `bash tests/unit_i18n.sh` | 占位符个数一致 |

  `check_i18n_equiv.sh` 是后加的，抓到过三类真缺陷：
  msgid 写对了但 msgstr 被灌成别的模块的说法（caddy 的「服务状态：」显示成「查看状态」）、
  msgstr 少了字（docker 丢「当前」）、批量包装时把 🚀/🎉 当噪声删掉。
  ⚠️ 只比 help/status 不够：只在 **install 路径**上出现的文案（emoji、
  「服务状态：」这类）比对不到，得靠这道门禁兜底。

### 灌译文的规矩

- 用「**只填空 msgstr、保留原格式**」的脚本；**重建 po 会丢旧译文**。
- 译文的占位符个数必须与 msgid 一致 —— `msgfmt --check` 会校验（编译期就红）。
- `msgmerge` 已加 `-N`（--no-fuzzy-matching）：新增 msgid 一律留空，**绝不猜译文**。
  必须确认 `grep -c '^#, fuzzy' locale/*/LC_MESSAGES/*.po` 是 0。

## 模块子命令约定

所有可执行模块遵循统一接口：

| 子命令 | 说明 |
|--------|------|
| `install` | 安装/配置（默认动作） |
| `uninstall` | 卸载 |
| `status` | 查看状态（输出一行结论） |
| `help` | 用法说明 |

部分模块有额外子命令（如 `bun mirror`、`clash start`、`sys-setup all`），用 `list --full` 查询。

### 机器可读 status（模块内部）

模块的 `status` 子命令支持环境变量 `UXS_STATUS_MODE=machine`，输出规范字段（无颜色无 emoji）：

```
STATE=<状态码>           # 必填，见上表
VERSION=<版本>           # 可选
EXTRA=<key=value>        # 可选，附加信息
```

模块作者使用 `lib/common.sh` 的 `emit_status`/`emit_version`/`emit_extra` helper 输出，人类模式默认向后兼容：

| Helper | 签名 | 说明 |
|--------|------|------|
| `emit_status` | `emit_status <state> <human_msg>` | 机器模式输出 `STATE=<state>`；人类模式 `echo -e "<human_msg>"`（含颜色/emoji） |
| `emit_version` | `emit_version <version>` | 仅机器模式输出 `VERSION=<version>`（人类模式版本已在状态消息里，不重复），始终返回 0 |
| `emit_extra` | `emit_extra <key=value>` | 仅机器模式输出 `EXTRA=<key=value>`（人类模式额外信息由模块自行 echo），始终返回 0 |
| `uxs_is_machine_mode` | `uxs_is_machine_mode` | 判断函数：机器模式返回 0，人类模式返回 1，用于包裹纯人类辅助输出 |

详见 `docs/superpowers/specs/2026-08-07-status-contract-deps-profile-design.md`。

### 平台动词 helper（lib 层收敛）

模块内跨发行版重复的平台操作优先用 lib helper，勿手写 `sudo apt-get`/`systemctl`：

| Helper | 说明 |
|--------|------|
| `uxs_os_release <KEY> [file]` | 读 os-release 字段值（ID/VERSION_ID/VERSION_CODENAME…），替代手写 `. /etc/os-release` |
| `uxs_svc <action> <unit>...` | systemd 服务动作（start/stop/restart/reload/enable/disable/enable-now/disable-now/daemon-reload + 只读 is-active/is-enabled/list-unit-files），原生兼容 `--dry-run`；双平台（macOS launchd）场景仍用 `service_start` 等 |
| `install_systemd_unit <unit-name>`（stdin） | 从 stdin 读 unit 内容写入 `/etc/systemd/system/` 并自动 daemon-reload（替代手写 `sudo tee` + reload；heredoc 引号语义由调用方决定；dry-run 兼容） |
| `pkg_install` / `pkg_remove` / `pkg_installed` | 跨包管理器安装/卸载/查询（存量，直接用） |

归属原则：跨模块复用的「动词」进 lib；单模块专用的平台差异放模块内 `platform/` 文件（样板见 `essentials/sys-setup`）。

### 发行版与桌面环境检测

模块可用 `lib/common.sh` 的以下函数做平台差异化处理（覆盖麒麟/统信/openEuler/deepin/openKylin 等国产系统）：

| 函数/变量 | 说明 |
|-----------|------|
| `detect_distro` | 读取 `/etc/os-release`，设置 `DISTRO_ID`（ubuntu/kylin/uos…）、`DISTRO_VERSION_ID`、`DISTRO_NAME`、`DISTRO_FAMILY`（debian\|rhel\|suse\|arch\|alpine\|unknown）。主机模式按包管理器实测定族（麒麟/统信服务器版=RPM 系、桌面版=Deb 系，均能正确归类）；显式传 os-release 文件路径则为纯词表分类（测试用） |
| `detect_desktop` | 检测桌面环境，设置 `DESKTOP_ENV`（ukui/dde/gnome/kde/xfce/mate/cinnamon/lxqt/budgie/none）与 `IS_DESKTOP`（1/0）。ukui=麒麟桌面、dde=统信/深度桌面 |

注意：麒麟（kylin）刻意不在 ID 硬表里——其服务器版基于 RHEL 系、桌面版基于 Ubuntu 系，族归属交由包管理器实测/ID_LIKE 判定。CI 在多发行版容器（含麒麟 V10、统信 UOS V20、openEuler、deepin、openKylin 镜像）中对识别结果做「外部真值断言」（`UXS_EXPECT_DISTRO_ID`/`UXS_EXPECT_DISTRO_FAMILY`），修改 `detect_distro`/`detect_desktop` 后请本地跑 `./tests/ci_run.sh --phase routing` 验证。

## 退出码约定

全库统一到 shellkit 的 0/1/2/3/4/5：

| 码 | 含义 | 典型场景 |
|---|---|---|
| 0 | 成功 | 含**状态类子命令**（`status` / `status --json`）——探测语义，恒 0 |
| 1 | 一般错误 | 未归类的失败 |
| 2 | 用法错 | 参数不对、未知选项、未知子命令 |
| 3 | 前置不满足 | 模块不存在、平台不适用、缺命令、非 root、交互无默认值 |
| 4 | 网络失败 | 版本检查、GitHub 查询等联网动作失败 |
| 5 | 校验失败 | sha256 对不上、文档与代码不一致 |

纪律：

- **状态类子命令恒 0**（用于探测）——既有契约，任何模块都不得用它表达失败。
- 框架层（`install.sh` 分发、`doctor`、`export`/`apply`）已按此口径实现。
- 模块脚本自身的退出码在 Stage 3 随迁移逐个统一；**新写的模块直接按此表来**，
  别再用 `exit 1` 糊弄所有失败——退出码就是接口的一部分，
  调用方要能靠码区分「用法错」和「前置不满足」。
- 改退出码属于**行为变化**：要同步改断言、在 `CHANGELOG.md` 记一笔，并确认输出文案是否逐字未变。

## 直接调用模块（绕过 install.sh）

```bash
./<分类目录>/<模块目录>/install.sh <子命令>
# 例：./dev-tools/bun/install.sh status
#     ./sys-tools/clash/install.sh start
#     ./services/docker/install.sh install
```

## 一行安装（bootstrap）

```bash
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- <模块名> [子命令]
```

## AI agent 典型工作流

1. `./install.sh status --json` → 了解当前已装/未装
2. `./install.sh list --full` → 了解可用模块及子命令（或 `./install.sh search <关键字>` 按名称/别名/描述精准搜索）
3. `./install.sh install <需要的模块>` → 安装
4. `./install.sh status <模块>` → 确认结果

## 注意事项

- `install` 类操作可能需要 sudo（脚本内部处理 `require_sudo`）
- 平台不适用的模块默认从列表/菜单隐藏（manifest `PLATFORMS` 声明）；`UNIX_SCRIPT_SHOW_ALL=1` 显示全量；绕过入口直接调模块时仍输出「不适用」并退出 0
- 状态子命令始终退出 0（用于探测），安装子命令失败退出非 0
- 输出为中文，子命令名和模块名为英文
