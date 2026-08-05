# 目录重构设计方案

日期: 2026-08-05
状态: 已批准，实施中

## 目标

将 51 个模块从根目录平铺重构为分类子目录，同时保持用户接口完全兼容。

## 目录映射

| manifest CATEGORY | 目录名 | 模块 |
|---|---|---|
| 服务 | `services/` | caddy, certbot, cockpit, ddns-go, docker, fail2ban, gitea, grafana, nginx, node_exporter, openlist, postgres, prometheus, redis, tailscale, uptime-kuma, wireguard |
| 装机必备 | `essentials/` | bbr, brew, essential-pkgs, nvm, swap, sys-setup |
| 开发环境 | `dev-tools/` | bun, code-lint, deno, dev-enhance, dev-mirror, dev-tui, go, minikube, modern-cli, pnpm, rust, zsh_setup |
| AI工具 | `ai-tools/` | ollama, opencode, pi |
| 系统工具 | `sys-tools/` | clash, deskflow, disk-usage, docker-image, k7s, multi-net, nat, process_manager_tool, restic, safe-rm, shutdown_timer, sys-cmd, ufw, upftp |

## 核心改动

1. `lib/registry.sh`: 扫描子目录，新增 PHYSICAL_PATH 字段和 registry_path() API
2. `lib/menu.sh`, `lib/status.sh`: 路径查询改用 registry_path()
3. `lib/submenus.sh`: 所有 run_in_dir 调用更新为分类路径
4. `lib/scaffold.sh`: 创建模块到分类目录
5. `install.sh`, `uninstall.sh`: dispatch 路径更新
6. 51 个模块 install.sh: source 路径 `../lib/` → `../../lib/`
7. `tests/ci_run.sh`: manifest 扫描和路径引用更新

## 用户接口兼容性

- `./install.sh docker` 仍然工作（框架内部解析路径）
- `./install.sh --list` 输出不变
- `./install.sh --status-json` 输出不变
- 直接调用变为 `./services/docker/install.sh install`
