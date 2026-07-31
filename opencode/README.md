# OpenCode（终端 AI 编程助手）

安装 [OpenCode](https://opencode.ai/)（sst/opencode）—— 开源终端 AI 编程助手，在终端里用 AI 辅助写代码。Linux + macOS。

## 安装

```bash
chmod +x opencode/install.sh
./opencode/install.sh            # 安装（默认动作）
```

安装方式：
- macOS 优先用 `brew install opencode`
- Linux / 无 brew：包装官方脚本 `curl -fsSL https://opencode.ai/install | bash`

## 使用

```bash
cd your-project
opencode            # 在项目目录启动 AI 编程会话
opencode --help
```

首次使用需配置模型与 API Key，参考 [OpenCode 文档](https://opencode.ai/docs/)。

## 状态与卸载

```bash
./opencode/install.sh status      # 查看状态
./opencode/install.sh uninstall   # 卸载（配置保留在 ~/.config/opencode）
```

## 说明
- opencode 是用户态工具（装到 `~/.local/bin` 或 brew），无需 sudo。
- 若装到 `~/.local/bin` 不在 PATH，脚本会提示添加 `export PATH="$HOME/.local/bin:$PATH"`。
