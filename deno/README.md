# Deno（JavaScript/TypeScript 运行时）

安装 [Deno](https://deno.land/) —— 安全的 JavaScript/TypeScript/WebAssembly 运行时。Linux + macOS。

## 安装
```bash
chmod +x deno/install.sh
./deno/install.sh            # 安装（默认动作）
```
macOS 优先 `brew install deno`，否则包装官方脚本 `https://deno.land/install.sh`（装到 `~/.deno`）。

## 使用
```bash
deno run https://deno.land/std/examples/welcome.ts
deno serve main.ts          # 启动服务
deno test                   # 运行测试
deno compile app.ts         # 编译为单文件可执行
```

## 状态与卸载
```bash
./deno/install.sh status
./deno/install.sh uninstall
```
