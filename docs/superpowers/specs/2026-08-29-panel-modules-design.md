# 管理面板批次①：1Panel / 宝塔 / Webmin / CasaOS 设计

- 日期：2026-08-29
- 状态：已实现（批次①，4 个模块）
- 关联：`services/cockpit`（既有面板类模块，结构模板）；易用性批次③ `search`

## 背景

库内已有 Cockpit（系统级 Web 控制台）但缺少国内主流「服务器运维面板」。用户要求新增
1Panel、宝塔面板及「等等一些其他的管理面板」。本批次选定 4 个，均为官方一键脚本/官方
仓库安装，遵循 cockpit 模块的结构模板与统一子命令接口。

## 模块清单

| 模块 | LABEL | 定位 | 安装来源 | 默认端口 |
|------|-------|------|----------|----------|
| `services/1panel` | 1Panel | 新一代 Linux 运维面板（FIT2CLOUD，v2） | 官方 `quick_start.sh`（resource.fit2cloud.com） | 随机/自选 |
| `services/btpanel` | 宝塔面板 | 宝塔 Linux 面板；`en` 子命令装国际版 aaPanel | 官方 `install_lts.sh`（download.bt.cn）/ aapanel.com 脚本 | 8888（随机化后以 `bt default` 为准） |
| `services/webmin` | Webmin | 经典 Web 系统管理面板 | 官方 APT/YUM 仓库（download.webmin.com，不依赖 raw.githubusercontent，国内可达） | 10000 |
| `services/casaos` | CasaOS | 家庭云/NAS 轻量面板 | 官方 `get.casaos.io` 脚本 | 80（与 nginx/caddy 冲突需警告） |

不纳入本批次（YAGNI，后续可加）：CyberPanel、HestiaCP、FastPanel、 CSP 面板等。

## 统一约定（对齐 cockpit 与新模块踩坑清单）

- 骨架：`set -euo pipefail` + `source lib/common.sh` + `preflight()`（`detect_os`，非
  Linux → error+exit 1；`command_exists systemctl` 校验）。
- 子命令：`install | uninstall | status | help`（+ 模块特有，见下）；status 恒退出 0，
  macOS 输出 `emit_status "n/a"`。
- **文件头注释放规范用法行** `# 用法: $0 {install|uninstall|...}`——`lib/menu.sh:333`
  用 `grep -m1 '用法:'` 取首个含 `{}` 的行提取子命令列（ops-kit 踩坑③）。
- `.manifest`：`CATEGORY=服务`、`DESC`（≤20 字，供 search/--list-modules）、
  `DEFAULT_ACTION=install`、按需 `ALIASES` / `NEXT_STEPS`。
- 防火墙：沿用 cockpit 模式——存在 `firewall-cmd`/`ufw` 时尽力放行面板端口（失败不阻断）。
- 已装检测：install 前检测已装并 `yes_no` 确认重装；非 TTY（`</dev/null`）自动取消，
  不卡死。
- 遵循 `emit_status`/`emit_version`/`emit_extra` 机器可读 status 契约。

## 各模块设计

### services/1panel

- install：下载 v2 `quick_start.sh` 到临时文件后执行（透传用户已设的 `PANEL_*` 环境变量
  即获得官方非交互能力）；完成后提示 `1pctl user-info` 查看入口。
- 子命令：`install | info | update | uninstall | status | help`
  - `info`：`1pctl user-info`（面板地址/入口/账号）
  - `update`：`1pctl update`
- status：`command -v 1pctl` 判已装；`systemctl is-active 1panel` 判运行；
  `1pctl version` → VERSION。
- uninstall：确认后 `1pctl uninstall`。

### services/btpanel

- install：按发行版家族取官方脚本（Deb 系 `install-ubuntu_6.0.sh`，其余 `install_lts.sh`），
  模块自身先 `yes_no` 确认再 `echo y |` 自动应答官方脚本的 y/n 询问（非 TTY 不卡死）。
  README 注明宝塔官方要求「纯净系统」（无既有 Apache/Nginx/MySQL/PHP）。
- 子命令：`install | en | info | uninstall | status | help`
  - `en`：安装国际版 aaPanel（`install_7.0_en.sh`，英文界面）
  - `info`：`sudo bt default`（面板地址/入口/默认密码）
- status：`/etc/init.d/bt` 存在或 `command -v bt` 判已装；`/etc/init.d/bt status` 判运行。
- uninstall：确认后停服务、移除 `/etc/init.d/bt`、`bt` 链接与 `/www/server/panel`；
  站点数据 `/www`（wwwlogs/wwwroot 等含用户数据）单独二次确认，默认保留。

### services/webmin

- install：手工配官方仓库（避免 raw.githubusercontent 国内不可达）：
  - Deb 系：import `download.webmin.com/developers-key.asc` →
    `/etc/apt/sources.list.d/webmin.list` → `apt-get install --install-recommends webmin`
  - RHEL 系：`/etc/yum.repos.d/webmin.repo`（baseurl `download.webmin.com/download/newkey/yum`）
    → `pkg_install webmin`
- 子命令：`install | uninstall | status | help`
- status：`/etc/webmin` 判已装；`systemctl is-active webmin` 判运行；端口读
  `/etc/webmin/miniserv.conf` 的 `port=` → EXTRA；版本读 `/etc/webmin/version`。
- 卸载：`pkg_remove webmin` + 移除仓库文件，`/etc/webmin`（含 miniserv.pem 证书与配置）
  确认后删。

### services/casaos

- install：`curl -fsSL https://get.casaos.io | sudo bash`；**执行前显式警告默认占用
  80 端口**，与 nginx/caddy 等冲突时建议先改端口或放弃。
- 子命令：`install | uninstall | status | help`
- status：`command -v casaos` 判已装；`systemctl is-active casaos` 判运行。
- uninstall：官方卸载脚本 `https://get.casaos.io/uninstall`（保留用户 data 目录，脚本自处理）。

## 框架联动

- registry 自动发现：无需改 `lib/`（`.manifest` 即注册）。
- 计数刷新：主 README「54 个模块」3 处 → 58；AGENTS.md 表格 services 17→21、总数 54→58；
  CHANGELOG `[Unreleased]` 增「新增」条目。
- completions 动态生成，无需改。

## 测试与验收

- `./tests/ci_run.sh --phase static`：shellcheck 0 告警（含 info 级）。
- `./tests/ci_run.sh --phase routing`：动态循环覆盖新模块的 status/help exit 0、
  `set -u` 干净、`uninstall)` 分支存在；macOS 冒烟 4 个模块 status 输出 n/a。
- routing 新增小节断言：`--list-modules` 与 `search` 能按名称/别名/DESC 命中 4 个新模块
  （覆盖 menu.sh 用法行解析不回归）。
- 实装验证（不阻塞合入）：murphy-server（Ubuntu）实机安装 1panel/btpanel 各一次，
  验证面板可访问、`status`/`info` 输出正确。

## 风险与对策

| 风险 | 对策 |
|------|------|
| 官方脚本 URL/交互行为变化 | 包装层薄（下载→执行），脚本内容不解析；URL 集中在文件头常量 |
| 宝塔要求纯净系统 | install 前检测 nginx/apache/mysql/php 进程/包，命中则 warn+确认 |
| CasaOS 抢 80 端口 | install 前显式 warn + 确认 |
| raw.githubusercontent 国内不可达 | webmin 走 download.webmin.com 仓库；其余域（fit2cloud/bt.cn/casaos）国内可达 |
| 官方脚本非 TTY 卡死 | 模块自身先确认，再以 `echo y |`/`</dev/null` 约束 stdin；非 TTY 自动取消 |
