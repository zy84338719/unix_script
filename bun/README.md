# Bun（JavaScript/TypeScript 运行时与工具链）

安装 [Bun](https://bun.sh/)（oven-sh/bun）—— 快速的 JavaScript/TypeScript 运行时，内置打包器、转译器、测试运行器与包管理器。Linux + macOS。

## 安装

```bash
chmod +x bun/install.sh
./bun/install.sh            # 安装（默认动作）
```

安装方式：
- macOS 优先 `brew install bun`
- Linux / 无 brew：包装官方脚本 `curl -fsSL https://bun.sh/install | bash`（装到 `~/.bun`）

## 使用

```bash
bun --version           # 查看版本
bun install             # 安装依赖（替代 npm install，速度更快）
bun run dev             # 运行脚本
bun build ./index.ts    # 打包
bun test                # 运行测试
bunx prettier --version # 执行本地/远程 CLI（替代 npx）
```

若 `~/.bun/bin` 不在 PATH，脚本会提示添加：`export PATH="$HOME/.bun/bin:$PATH"`

## 状态与卸载

```bash
./bun/install.sh status      # 查看状态
./bun/install.sh uninstall   # 卸载（询问删除 ~/.bun）
```

## 说明
- Bun 是用户态安装（`~/.bun` 或 brew），无需 sudo。
- 与 nvm/Node 的区别：Bun 是独立运行时（非 Node），可直接运行 .ts/.js，内置包管理。
- 文档：https://bun.sh/docs
