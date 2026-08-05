# ~/.config/zsh_setup/templates/env.zsh
# 环境变量模板

# 默认编辑器
export EDITOR='vim'
export VISUAL='vim'

# 语言环境
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# Go 环境
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Node.js 环境
export NODE_PATH="$HOME/.node_modules"
export PATH="$NODE_PATH/bin:$PATH"

# Python 环境
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1

# Rust 环境
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"
export PATH="$CARGO_HOME/bin:$PATH"

# Homebrew (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    export HOMEBREW_NO_AUTO_UPDATE=1
fi

# 自定义 PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
