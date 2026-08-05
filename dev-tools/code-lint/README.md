# 代码分析工具集 (code-lint)

为 Go / Rust / Java / Python 提供静态分析、安全扫描工具的一键安装与便捷运行。

## 支持平台

- ✅ Linux（通过包管理器 + 官方脚本）
- ✅ macOS（通过 Homebrew）

## 工具清单

| 语言 | 工具 | 用途 |
|------|------|------|
| **Go** | [golangci-lint](https://golangci-lint.run/) | 聚合 linter（100+ 规则） |
| | [gosec](https://github.com/securego/gosec) | 安全漏洞扫描 |
| **Rust** | [clippy](https://github.com/rust-lang/rust-clippy) | 官方 linter |
| | [cargo-audit](https://github.com/rustsec/cargo-audit) | 依赖漏洞扫描 |
| **Java** | [SpotBugs](https://spotbugs.github.io/) | 字节码静态分析 |
| | [PMD](https://pmd.github.io/) | 源码级分析 |
| | [Checkstyle](https://checkstyle.org/) | 代码风格检查 |
| **Python** | [Ruff](https://docs.astral.sh/ruff/) | 极速 linter + formatter |
| | [mypy](https://mypy-lang.org/) | 静态类型检查 |
| | [bandit](https://bandit.readthedocs.io/) | 安全漏洞扫描 |
| **跨语言** | [semgrep](https://semgrep.dev/) | 多语言 SAST |

## 安装

```bash
# 安装全部工具
./install.sh code-lint

# 仅安装特定语言工具
./install.sh code-lint install-go
./install.sh code-lint install-rust
./install.sh code-lint install-java
./install.sh code-lint install-python
./install.sh code-lint install-semgrep
```

> 注意：安装时会自动检测已安装的语言环境，未安装的语言工具会被跳过。

## 运行分析

```bash
# 运行特定语言分析
./install.sh code-lint go-lint [path]
./install.sh code-lint rust-lint [path]
./install.sh code-lint java-lint [path]
./install.sh code-lint py-lint [path]

# 跨语言安全扫描
./install.sh code-lint security-scan [path]

# 自动检测语言并运行所有适用的分析
./install.sh code-lint lint-all [path]

# 也可以直接调用脚本
./code-lint/scripts/go-lint.sh /path/to/project
```

## 子命令一览

| 子命令 | 说明 |
|--------|------|
| `install` | 安装全部工具（默认动作） |
| `install-go` | 仅安装 Go 工具 |
| `install-rust` | 仅安装 Rust 工具 |
| `install-java` | 仅安装 Java 工具 |
| `install-python` | 仅安装 Python 工具 |
| `install-semgrep` | 仅安装 semgrep |
| `go-lint [path]` | 运行 Go 分析 |
| `rust-lint [path]` | 运行 Rust 分析 |
| `java-lint [path]` | 运行 Java 分析 |
| `py-lint [path]` | 运行 Python 分析 |
| `security-scan [path]` | 跨语言安全扫描 |
| `lint-all [path]` | 自动检测语言并运行全部分析 |
| `uninstall` | 显示卸载说明 |
| `status` | 查看各工具安装状态 |
| `help` | 帮助信息 |

## CI 集成

```bash
# 在 CI 中运行（有错误返回非 0）
./install.sh code-lint lint-all . || exit 1

# 仅检查 Python
./install.sh code-lint py-lint src/
```
