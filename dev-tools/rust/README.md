# Rust（通过 rustup）

安装 [Rust](https://rustup.rs/) —— 通过官方 rustup 安装器。Linux + macOS，用户态安装无需 sudo。

## 安装

```bash
chmod +x rust/install.sh
./rust/install.sh            # 安装（默认动作）
```

包装官方 rustup 安装器 `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y`。装到 `~/.rustup` + `~/.cargo`。

## 使用

```bash
rustc --version              # 查看版本
cargo new my-project         # 创建新项目
cd my-project && cargo run   # 编译并运行
cargo test                   # 运行测试
rustup component add rust-analyzer  # 添加 LSP（IDE 集成）
rustup update                # 更新 Rust 工具链
```

若 `~/.cargo/bin` 不在 PATH，运行 `source ~/.cargo/env` 或添加到 shell 配置：
```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

## 状态与卸载

```bash
./rust/install.sh status      # 查看状态
./rust/install.sh uninstall   # 卸载（rustup self uninstall，或手动删除 ~/.rustup + ~/.cargo）
```

## 说明
- rustup 会自动配置 `~/.cargo/env` 到 bash/zsh/profile。
- 已安装时 `install` 会调用 `rustup update` 更新而非重装。
- 卸载会清理 shell rc 中的 cargo env 引用。
- 文档：https://rustup.rs / https://doc.rust-lang.org
