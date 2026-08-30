# 容器工具批次②：buildah / skopeo / kind / k3s / harbor / mysql / frp 设计

- 日期：2026-08-30
- 状态：已定稿（7 个模块），待实施
- 关联：批次① spec（2026-08-30-container-tools-design.md，排除清单即本批来源）、`services/podman`、`dev-tools/minikube`

## 背景

批次① 定稿时按 YAGNI 排除的容器生态候选，用户要求继续做齐。本批 7 个模块覆盖：
镜像构建/搬运（buildah、skopeo）、本地/边缘集群（kind、k3s）、自托管镜像仓库（harbor）、
数据库补齐（mysql——库内只有 postgres/redis）、内网穿透（frp）。

## 模块清单

| 模块 | 位置 | 平台 | 安装来源 | CATEGORY | REQUIRES |
|------|------|------|----------|----------|----------|
| `buildah` | `services/buildah` | **PLATFORMS=linux**（macOS 上无本地容器存储，不可用） | 发行版仓库 pkg_install | 服务 | — |
| `skopeo` | `services/skopeo` | 全平台 | Linux=pkg_install；macOS=brew | 服务 | — |
| `kind` | `dev-tools/kind` | 全平台 | Linux=GitHub release 二进制；macOS=brew | 开发环境 | docker |
| `k3s` | `services/k3s` | **PLATFORMS=linux** | get.k3s.io 官方脚本 | 服务 | — |
| `harbor` | `services/harbor` | **PLATFORMS=linux** | GitHub release offline installer | 服务 | docker |
| `mysql` | `services/mysql` | 全平台 | Linux=发行版仓库；macOS=brew | 服务 | — |
| `frp` | `services/frp` | 全平台 | GitHub release 二进制 | 服务 | — |

本批仍不做（后续）：MariaDB 独立模块、podman-desktop、lxd/incus、nomad。

## 统一约定

同批次①（骨架、用法行、manifest、状态契约、已装确认、数据二次确认），另注意：

- **REQUIRES=docker 的模块**（kind/harbor）：框架阶段 E 自动先装 docker；`--no-deps` 可跳过。
- **PLATFORMS=linux 的模块**（buildah/k3s/harbor）：macOS 全出口隐藏，直调报"不适用"。
- 服务类模块 status 用 `uxs_svc is-active` 判 `installed:running/stopped`。
- 修复批次①踩坑：status 一律先 `detect_os`；变量接全角字符一律 `${var}` 加花括号。

## 各模块设计

### services/buildah（PLATFORMS=linux）

- install：`pkg_install buildah`（Ubuntu 20.04+/Debian 12+/RHEL 系均有）。
- status：`buildah --version` → VERSION。
- uninstall：`pkg_remove buildah`；`~/.local/share/containers` 二次确认。

### services/skopeo（全平台）

- install：Linux `pkg_install skopeo`；macOS `brew install skopeo`（纯 registry 客户端
  操作无需本地运行时，全平台可用）。
- status：`skopeo --version` → VERSION。
- uninstall：pkg_remove / brew uninstall；不动镜像存储。

### dev-tools/kind（REQUIRES=docker）

- install：Linux 用 GitHub release 二进制（`kubernetes-sigs/kind`，资产
  `kind-linux-${arch}`，单文件），`/usr/local/bin/kind`；macOS `brew install kind`。
- status：`kind version` → VERSION。
- uninstall：删二进制 / brew uninstall；集群 `kind delete clusters` 提示用户自决，不自动删。

### services/k3s（PLATFORMS=linux）

- install：官方 `curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644`
  （官方分发域，非 raw.githubusercontent）；完成后 `k3s kubectl get node` 提示验证。
- status：`k3s --version` → VERSION；`uxs_svc is-active k3s` → running/stopped。
- uninstall：`/usr/local/bin/k3s-uninstall.sh`（官方卸载脚本，若存在）；数据
  `/var/lib/rancher/k3s` 随官方脚本清理，无需二次确认（脚本自带确认逻辑，删除前
  脚本内部已处理）。

### services/harbor（PLATFORMS=linux，REQUIRES=docker）

- install：下载 `goharbor/harbor` release 的 `harbor-offline-installer-v<ver>.tgz`
  （版本经 github_latest_tag），解压到 `/opt/harbor`；复制 `harbor.yml.tmpl` 为
  `harbor.yml`（hostname 默认本机 IP，`harbor_admin_password` 交互询问、非 TTY 用
  随机密码并回显）；`./install.sh`（官方编排脚本，含 prepare/compose up）。
- status：`docker ps` 中存在 `goharbor/harbor-core` 镜像容器 → running；`/opt/harbor`
  存在 → installed:stopped；都没有 → not_installed。
- uninstall：`docker compose down -v`（/opt/harbor 下）+ 提示；`/opt/harbor` 与
  `/data` 卷数据二次确认。

### services/mysql（全平台）

- install：Linux Deb 系 `pkg_install mysql-server`（Ubuntu）/ `default-mysql-server`
  回退；RHEL 系 `pkg_install mysql-server`（AppStream）。装后 `uxs_svc enable-now`
  （服务名 deb=`mysql`、rhel=`mysqld`，探测存在哪个用哪个）。macOS
  `brew install mysql` + 提示 `brew services start mysql`。
- 首次装后提示 `mysql_secure_installation`（不自动跑）；Deb 系 root 走
  auth_socket、RHEL 系临时密码在 `grep 'temporary password' /var/log/mysqld.log`，
  README 说明。
- status：`mysql --version` → VERSION；服务 running/stopped。
- uninstall：pkg_remove / brew uninstall；`/var/lib/mysql` 数据二次确认。

### services/frp（全平台）

- install：GitHub release（`fatedier/frp`，`github_latest_tag`）下载
  `frp_<ver>_<os>_<arch>.tar.gz`（arch 映射 amd64/arm64），取 `frpc`/`frps` 到
  `/usr/local/bin`；配置样例放 `/etc/frp/frpc.toml`、`/etc/frp/frps.toml`
  （已存在不覆盖）；附 systemd unit `frpc.service`/`frps.service`
  （`WantedBy=multi-user.target`，默认不启用），macOS 只装二进制并提示手跑。
- status：两二进制存在 → installed；版本 `frps --version`；Linux EXTRA
  `frps_active=<yes|no>`（uxs_svc is-active frps）。
- uninstall：删二进制与 unit（disable 后删）；`/etc/frp` 配置二次确认（含用户 token）。

## 框架联动

- 模块数 66 → 73；README 计数 3 处；AGENTS.md services 23→28、dev-tools 18→19、
  总数 66→73；CHANGELOG `[Unreleased]` 增条目。
- PLATFORMS/REQUIRES 均为框架既有字段，无需改 lib。

## 测试与验收

- static：shellcheck 0 告警（CI 同款排除清单）。
- routing：7 模块 status/help exit 0、set -u 干净、用法行解析、search 命中。
- 本地 Linux 容器复跑（debian bookworm）防"本地未装测不出"的环境差。
- macOS 冒烟：skopeo/kind/mysql/frp status 正常；buildah/k3s/harbor 直调报不适用。
- 实装验证（不阻塞合入）：murphy-server 实装 k3s/frps/mysql/harbor。
