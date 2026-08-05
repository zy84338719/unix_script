# Ollama（本地大模型运行时）

安装 [Ollama](https://ollama.com/) —— 在本地运行开源大语言模型（Llama/Qwen/DeepSeek/Gemma 等），提供 CLI 与 API（默认 11434 端口）。Linux + macOS。

## 安装

```bash
chmod +x ollama/install.sh
./ollama/install.sh               # 安装（默认动作）
```

安装方式：
- Linux：官方脚本 `curl -fsSL https://ollama.com/install.sh | sh`（含 systemd 服务）
- macOS：`brew install ollama`

## 运行模型

```bash
ollama run qwen3:8b        # 下载并交互运行（首次拉取较慢）
ollama pull deepseek-r1    # 仅下载
ollama list                # 已下载模型
ollama serve               # 启动 API 服务（http://localhost:11434）
```

常用模型（[模型库](https://ollama.com/library)）：`qwen3:8b` / `llama3.2` / `deepseek-r1` / `gemma3`。

## 通过脚本拉取模型

```bash
./ollama/install.sh pull qwen3:8b
./ollama/install.sh pull deepseek-r1
```

## API 调用

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "qwen3:8b",
  "prompt": "你好"
}'
```

## 状态与卸载

```bash
./ollama/install.sh status      # 查看状态
./ollama/install.sh uninstall   # 卸载（可选删除已下载模型，~/.ollama 可能很大）
```

## 说明
- Linux 上由官方脚本配置 systemd 服务 `ollama`。
- 模型文件默认存在 `~/.ollama`，体积大（几 GB 起），卸载时建议确认是否删除。
- 与 opencode 等工具配合，可形成"本地 AI 编程栈"（本地模型 + 编程助手）。
