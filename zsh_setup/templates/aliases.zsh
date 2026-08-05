# ~/.config/zsh_setup/templates/aliases.zsh
# 通用别名模板

# 常用别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# 安全操作
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# 快捷命令
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Git 别名
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph'
alias gd='git diff'

# Docker 别名
alias dk='docker'
alias dkc='docker compose'
alias dkps='docker ps'
alias dki='docker images'

# 系统信息
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias diskinfo='df -h'

# 开发工具
alias py='python3'
alias pip='pip3'
alias serve='python3 -m http.server'
