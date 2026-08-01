# Pi（AI 编程代理框架）

安装 [Pi](https://pi.dev/)（Earendil Inc.）—— 极简可定制的 AI 编程代理框架。支持 15+ 模型提供商、树状会话历史、扩展/技能/提示模板自定义。Linux + macOS。

## 特性
- **多模型**：Anthropic/OpenAI/Google/Groq 等 15+ 提供商，会话中途切换
- **树状历史**：倒退到任意节点分支继续，可导出/分享
- **可扩展**：扩展、技能、提示模板、主题，甚至让 Pi 自己构建缺失功能
- **上下文工程**：极简系统提示，支持 `AGENTS.md`/`SYSTEM.md` 项目级配置

## 安装

```bash
chmod +x pi/install.sh
./pi/install.sh            # 安装（默认动作）
```

包装官方脚本 `curl -fsSL https://pi.dev/install.sh | sh`。

也可通过 npm/pnpm/bun 全局安装：
```bash
npm install -g @earendil-works/pi-coding-agent
bun add -g @earendil-works/pi-coding-agent
```

## 使用

```bash
pi                          # 启动交互式 TUI
pi '修复这个 bug'           # 直接给提示
pi --help                   # 查看帮助
```

## 状态与卸载

```bash
./pi/install.sh status      # 查看状态
./pi/install.sh uninstall   # 卸载（询问删除 ~/.pi）
```

## 说明
- Pi 是用户态安装，无需 sudo。
- 首次使用需配置模型 API Key，参考 https://pi.dev
- 开源（MIT），GitHub: https://github.com/earendil-works/pi
