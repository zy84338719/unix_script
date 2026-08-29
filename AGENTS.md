# AGENTS.md

本文件供 AI agent（Claude Code / Cursor / Copilot / opencode / Pi 等）阅读，说明如何使用 unix_script 脚本库。

## 这是什么

unix_script 是一个 macOS/Linux 脚本库，提供 54 个模块的安装、配置与管理。每个模块支持统一的子命令接口。

模块按功能分类组织在子目录中：

| 分类目录 | 说明 | 模块数 |
|----------|------|--------|
| `services/` | 服务类（Web/数据库/监控/VPN 等） | 17 |
| `essentials/` | 装机必备（基础工具/系统初始化） | 6 |
| `dev-tools/` | 开发环境（语言/编辑器/工具链） | 12 |
| `ai-tools/` | AI 工具（大模型/编程助手） | 3 |
| `sys-tools/` | 系统工具（安全/网络/备份/进程管理） | 16 |

## 快速调用（AI agent 友好）

### 列出所有模块

```bash
./install.sh --list
# 输出：空格分隔的模块名
# node_exporter ddns-go wireguard tailscale docker ...
```

### 机器可读的模块清单（含子命令）

```bash
./install.sh --list-modules
# 输出 TSV：模块名\t支持子命令[  requires:...]\t描述
# node_exporter	install uninstall status help	Prometheus 系统指标收集器
# bun	install mirror unmirror uninstall status help	Bun 运行时（含国内镜像加速）
# minikube	install uninstall status help  requires:docker	本地 Kubernetes 开发环境
```

第 3 列为 `.manifest` 的 `DESC`（一句话中文描述；无描述的模块该列为空）。前两列语义与历史版本一致。

### 按分类列出模块

```bash
./install.sh --list-categories
# 输出：按分类分组的模块列表（服务/装机必备/开发环境/AI工具/系统工具）
```

### 机器可读状态

```bash
./install.sh --status-json
# 输出 key:value（每行一个，无颜色无 emoji）
# node_exporter:not_installed
# docker:installed:running
# bun:installed:v1.3.14
```

输出首部固定 3 行框架元数据（AI 解析时跳过前 3 行，或按 key 是否为模块名判断）：

```
os:darwin       # 宿主 OS（darwin/linux）
arch:ARM64      # CPU 架构
version:1.14.0  # unix_script 自身版本
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

### 安装/操作模块

```bash
# 非交互安装某模块（AI 推荐方式）
./install.sh <模块名>           # 默认动作（通常=install）
./install.sh <模块名> install   # 显式安装
./install.sh bun mirror         # 模块子命令透传
./install.sh --no-deps <模块名> # 安装但跳过依赖自动安装（阶段 E）

# 示例
./install.sh docker             # 安装 Docker
./install.sh minikube           # 安装 minikube（自动先装其依赖 docker）
./install.sh fail2ban           # 安装 Fail2ban
./install.sh sys-setup all      # 全部系统初始化配置
./install.sh bun mirror         # Bun 换国内镜像源
```

### 模块依赖与配置复现（阶段 E + D）

**依赖图（阶段 E）**：模块可在 `.manifest` 中声明 `REQUIRES=<模块名>[,...]`。安装时框架自动先装缺失的依赖（拓扑序），循环依赖会被检测并报错。`--list-modules` 对有依赖的模块追加 `requires:...` 列。

```bash
./install.sh --no-deps minikube   # 跳过自动装依赖
UNIX_SCRIPT_NO_DEPS=1 ./install.sh minikube   # 等价环境变量
```

**配置复现 / profile（阶段 D）**：把"哪些模块已装 + 关键配置"导出为可 git 的纯文本 profile，在新机器一键复现。模块用 `EXPORTABLE=<key>[,...]` 声明可导出的配置键（其 `status` 用 `emit_extra "key=value"` 输出当前值）。

```bash
./install.sh export                  # 导出到 ~/.config/unix_script/profile.txt
./install.sh export /path/profile    # 导出到指定文件
./install.sh apply                   # 应用默认 profile（已装模块跳过）
./install.sh apply /path/profile --force    # 强制重装
./install.sh apply /path/profile --dry-run  # 预览
```

profile 行格式：`<模块名> [key=value ...]   # 注释`。apply 时把 `key=value` 注入为 `UXS_CONFIG_<KEY>` 环境变量传给模块 install（模块自行读取，如 bun 读 `UXS_CONFIG_REGISTRY`）。

### 去除颜色（管道/日志场景）

所有输出支持 `NO_COLOR=1` 环境变量（或管道自动检测）：

```bash
NO_COLOR=1 ./install.sh --status
./install.sh --status-json       # --status-json 始终无颜色
```

### 调试模式

`UXS_DEBUG=1` 会把库内原本静默的 stderr（`2>/dev/null`，如 GitHub API 请求/解析失败）透出到终端，便于排查：

```bash
UXS_DEBUG=1 ./install.sh check-update
```

## 模块子命令约定

所有可执行模块遵循统一接口：

| 子命令 | 说明 |
|--------|------|
| `install` | 安装/配置（默认动作） |
| `uninstall` | 卸载 |
| `status` | 查看状态（输出一行结论） |
| `help` | 用法说明 |

部分模块有额外子命令（如 `bun mirror`、`clash start`、`sys-setup all`），用 `--list-modules` 查询。

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
| `uxs_svc <action> <unit>...` | systemd 服务动作（start/stop/restart/reload/enable/enable-now/is-active），原生兼容 `--dry-run`；双平台（macOS launchd）场景仍用 `service_start` 等 |
| `pkg_install` / `pkg_remove` / `pkg_installed` | 跨包管理器安装/卸载/查询（存量，直接用） |

归属原则：跨模块复用的「动词」进 lib；单模块专用的平台差异放模块内 `platform/` 文件（样板见 `essentials/sys-setup`）。

### 发行版与桌面环境检测

模块可用 `lib/common.sh` 的以下函数做平台差异化处理（覆盖麒麟/统信/openEuler/deepin/openKylin 等国产系统）：

| 函数/变量 | 说明 |
|-----------|------|
| `detect_distro` | 读取 `/etc/os-release`，设置 `DISTRO_ID`（ubuntu/kylin/uos…）、`DISTRO_VERSION_ID`、`DISTRO_NAME`、`DISTRO_FAMILY`（debian\|rhel\|suse\|arch\|alpine\|unknown）。主机模式按包管理器实测定族（麒麟/统信服务器版=RPM 系、桌面版=Deb 系，均能正确归类）；显式传 os-release 文件路径则为纯词表分类（测试用） |
| `detect_desktop` | 检测桌面环境，设置 `DESKTOP_ENV`（ukui/dde/gnome/kde/xfce/mate/cinnamon/lxqt/budgie/none）与 `IS_DESKTOP`（1/0）。ukui=麒麟桌面、dde=统信/深度桌面 |

注意：麒麟（kylin）刻意不在 ID 硬表里——其服务器版基于 RHEL 系、桌面版基于 Ubuntu 系，族归属交由包管理器实测/ID_LIKE 判定。CI 在多发行版容器（含麒麟 V10、统信 UOS V20、openEuler、deepin、openKylin 镜像）中对识别结果做「外部真值断言」（`UXS_EXPECT_DISTRO_ID`/`UXS_EXPECT_DISTRO_FAMILY`），修改 `detect_distro`/`detect_desktop` 后请本地跑 `./tests/ci_run.sh --phase routing` 验证。

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

1. `./install.sh --status-json` → 了解当前已装/未装
2. `./install.sh --list-modules` → 了解可用模块及子命令（或 `./install.sh search <关键字>` 按名称/别名/描述精准搜索）
3. `./install.sh <需要的模块>` → 安装
4. `./install.sh <模块> status` → 确认结果

## 注意事项

- `install` 类操作可能需要 sudo（脚本内部处理 `require_sudo`）
- 某些模块仅 Linux（macOS 会输出"不适用"并退出 0）
- 状态子命令始终退出 0（用于探测），安装子命令失败退出非 0
- 输出为中文，子命令名和模块名为英文
