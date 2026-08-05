# safe-rm（安全删除 / 回收站）

用"移动到回收站"替代 `rm` 直接删除，告别 `rm -rf` 误删灾难。纯 shell 函数实现，不依赖外部工具，Linux + macOS 通用。

## 设计原则
- **`rm` 保持原样不动**：不破坏脚本/Makefile 中依赖 `rm` 真删除的契约。
- **新增 `t`/`trash` 命令**做安全删除（养成"重要文件用 t 删"的习惯）。
- **可选的 rm 危险路径保护**：对根目录/家目录/系统目录等关键路径的 `rm` 加二次确认（不改语义，只防误删），可随时开关。

## 安装

```bash
chmod +x safe-rm/install.sh
./safe-rm/install.sh install     # 安装回收站函数并配置 shell rc
```

安装后**重新加载 shell**生效：
```bash
source ~/.bashrc    # bash
source ~/.zshrc     # zsh
```

## 命令

| 命令 | 说明 |
|------|------|
| `t <文件...>` / `trash <文件...>` | 安全删除（移到回收站，兼容 rm 的 `-r`/`-f` 选项） |
| `tls` / `trashlist` | 查看回收站内容（带序号与原路径） |
| `trash-restore <序号>` / `restore <序号>` | 恢复（序号来自 `tls`，最新删除的为序号 1） |
| `trash-empty --force` | 清空回收站（不可恢复） |
| `trash-empty` | 查看回收站项数与占用（不清空） |
| `trash-size` | 查看回收站占用空间 |

## 示例

```bash
t important.txt              # 安全删除（移到回收站）
t -rf some_dir               # 兼容 rm 习惯，同样移到回收站
tls                          # 查看，例如：
#  1) some_dir_20260731_...   <- /home/user/some_dir
#  2) important.txt_20260731_... <- /home/user/important.txt
trash-restore 2              # 恢复 important.txt
trash-empty --force          # 确认清空全部
```

## rm 危险路径保护（可选）

```bash
./safe-rm/install.sh on      # 启用：rm 对根/家/系统目录等加二次确认
./safe-rm/install.sh off     # 关闭，恢复原始 rm
```

启用后，`rm -rf /` 或 `rm -rf $HOME` 这类操作会被拦截要求确认，避免灾难性误删。普通路径的 rm 不受影响，仍是真删除。

## 回收站位置

遵循 [FreeDesktop Trash 规范](https://specifications.freedesktop.org/trash-spec/trashspec-1.0.html)：
```
~/.local/share/Trash/
├── files/    # 删除的文件（带时间戳后缀，避免重名冲突）
└── info/     # .trashinfo 元数据（记录原路径与删除时间，用于恢复）
```

## 状态与卸载

```bash
./safe-rm/install.sh status     # 查看安装状态与回收站占用
./safe-rm/install.sh uninstall  # 卸载（保留已删除的回收站数据）
```

## 说明
- 删除时文件名加时间戳后缀（`原名_YYYYMMDD_HHMMSS`），避免同名文件互相覆盖。
- 恢复时若原路径已被新文件占用，会恢复为 `<原名>.restored.<时间戳>`，不覆盖现有文件。
- 跨 shell 兼容：bash 与 zsh 均可使用（`trash-empty` 用 `--force` 而非交互 read，避免跨 shell 差异）。
