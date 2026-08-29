# Atuin（SQLite 化 shell 历史）

用 SQLite 数据库替代传统 shell 历史：全量模糊搜索（Ctrl+R）、可跨机端到端加密同步。macOS + Linux。

## 安装

```bash
./install.sh atuin                          # 默认纯本地模式
UXS_CONFIG_SYNC=1 ./install.sh atuin        # 启用同步（需自行 atuin register 注册）
```

安装后自动：rc 写入初始化（带标记块）→ `atuin import auto` 迁移旧历史。

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 安装（默认动作） |
| `sync` | 手动同步（需已注册；纯本地模式会提示） |
| `uninstall` | 显示卸载说明 |
| `status` | 查看状态（机器模式 `EXTRA=sync=on\|off`） |
| `help` | 帮助信息 |

## 安装方式与回退

- macOS：`brew install atuin`
- Linux：包管理器 → 回退官方脚本 `setup.atuin.sh`（装到 `~/.atuin/bin`，rc 自动加 PATH）
- profile 复现：`EXPORTABLE=sync`（apply 时 `UXS_CONFIG_SYNC` 注入）

## 说明

- 同步注册是交互式操作，模块不代注册；`UXS_CONFIG_SYNC=1` 时 install 会提示 `atuin register`。
- 隐私：同步为端到端加密（密钥只在本地）；纯本地模式不出网。
