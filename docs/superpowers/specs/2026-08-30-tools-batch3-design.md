# 工具批次③：MariaDB / MongoDB / podman-desktop / incus / nomad 设计

- 日期：2026-08-30
- 状态：已定稿（5 个模块），待实施
- 关联：`services/mysql`（数据库模块模板）、`services/k3s`（Linux 服务类）、`sys-tools/deskflow`（Flatpak/Homebrew 双通道先例）

## 背景

容器两批次（v1.18.0/v1.19.0）后，用户点名补齐剩余候选：MariaDB 独立模块、MongoDB、
podman-desktop、lxd/incus、nomad。本批 5 个模块，73 → 78。

## 模块清单

| 模块 | 位置 | 平台 | 安装来源 | CATEGORY |
|------|------|------|----------|----------|
| `mariadb` | `services/mariadb` | 全平台 | Linux=发行版仓库；macOS=brew | 服务 |
| `mongodb` | `services/mongodb` | **PLATFORMS=linux** | 官方 GPG key + TUNA 镜像仓库（apt/yum，8.0 系列） | 服务 |
| `podman-desktop` | `services/podman-desktop` | 全平台 | macOS=brew cask；Linux=Flatpak（flathub） | 服务 |
| `incus` | `services/incus` | **PLATFORMS=linux** | Deb 系=Zabbly 稳定仓；RHEL 系=发行版/EPEL 包 | 服务 |
| `nomad` | `services/nomad` | 全平台 | Linux=GitHub release zip；macOS=brew | 服务 |

## 各模块设计

### services/mariadb

- install：`pkg_install mariadb-server`（各大发行版均有）→ `uxs_svc enable-now mariadb`
  （服务名统一 mariadb，SUSE 为 mariadb，探测失败回退 mysql）；macOS `brew install
  mariadb` + 提示 `brew services start mariadb`。装后提示 `mariadb-secure-installation`。
- 与 mysql 模块关系：独立模块不互斥，但同机同端口 3306 冲突——install 检测
  `command_exists mysql` 时警告端口冲突仍可继续（用户显式选择）。
- status：`mariadb --version` → VERSION；Linux 服务 running/stopped。

### services/mongodb（PLATFORMS=linux）

- install：导入官方 GPG key（www.mongodb.org/static/pgp/server-8.0.asc，官方域可达），
  仓库 baseurl 走 **TUNA 镜像**（国内可达，沿用换源矩阵结论）：
  - Deb 系：`mirrors.tuna.tsinghua.edu.cn/mongodb/apt/ubuntu <codename>/mongodb-org/8.0`
    （codename 取 `uxs_os_release VERSION_CODENAME`，不在支持列表时报错退出并列出
    支持代号）
  - RHEL 系：`mirrors.tuna.tsinghua.edu.cn/mongodb/yum/el$releasever/mongodb-org/8.0`
  - `pkg_install mongodb-org` → `uxs_svc enable-now mongod`
- status：`mongod --version` → VERSION；服务 running/stopped。
- uninstall：`pkg_remove mongodb-org` + 移除仓库文件；`/var/lib/mongodb` 数据二次确认。

### services/podman-desktop

- install：macOS `brew install --cask podman-desktop`；Linux 检查 `flatpak` 存在
  （缺失则提示先装并退出），`flatpak install -y flathub io.podman_desktop.PodmanDesktop`。
- 提示：容器运行时配 podman 模块（machine），`./install.sh podman`。
- status：macOS 检测 `/Applications/Podman Desktop.app`；Linux `flatpak list` 含
  `io.podman_desktop.PodmanDesktop`。
- uninstall：brew cask uninstall / flatpak uninstall。

### services/incus（PLATFORMS=linux）

- install：Deb 系配 **Zabbly 稳定仓**（pkgs.zabbly.com，官方维护的 incus 打包）；
  RHEL 系直接 `pkg_install incus`（openEuler/Fedora 有包，失败给出手动指引）。
  装后 `uxs_svc enable-now incus`，提示 `incus admin init`（交互初始化，不自动跑）。
- status：`incus --version`；服务 running/stopped。
- uninstall：pkg_remove + 仓库文件；`/var/lib/incus` 数据二次确认。

### services/nomad

- install：Linux 用 GitHub release（`hashicorp/nomad`，资产
  `nomad_<ver>_<os>_${arch}.zip`，需 unzip），解压 `/usr/local/bin/nomad`；macOS
  `brew install nomad`。
- status：`nomad version` → VERSION（单二进制无服务概念，恒 installed）。
- uninstall：删二进制 / brew uninstall。

## 框架联动

- 模块数 73 → 78；README 计数 3 处；AGENTS.md services 28→33、总数 73→78；
  CHANGELOG `[Unreleased]` 增条目。
- 应用既有踩坑：status 先 detect_os；变量接全角字符加花括号。

## 测试与验收

- static（macOS + CI 容器矩阵）；routing 双环境（macOS 本地 + debian 容器）。
- macOS 冒烟：mariadb/mongodb/incus 隐藏或 n/a 正确；podman-desktop/nomad status 正常。
- 实装验证（不阻塞合入）：murphy-server。
