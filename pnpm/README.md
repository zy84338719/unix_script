# pnpm（Node.js 包管理器）

安装 [pnpm](https://pnpm.io/) —— 快速、节省磁盘的 Node.js 包管理器。Linux + macOS。

## 安装
```bash
chmod +x pnpm/install.sh
./pnpm/install.sh            # 安装（默认动作）
```
macOS 优先 `brew install pnpm`，否则包装官方独立脚本 `https://get.pnpm.io/install.sh`（不依赖 Node，装到 `~/.local/share/pnpm`）。

## 使用
```bash
pnpm install         # 安装依赖
pnpm run dev         # 运行脚本
pnpm add <包名>       # 添加依赖
```

## 状态与卸载
```bash
./pnpm/install.sh status
./pnpm/install.sh uninstall
```
