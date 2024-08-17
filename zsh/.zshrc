# p10k enable
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ---------------------------------------------------------------------------------------
# ----------------------Z-S-H---C-O-N-F-I-G----------------------------------------------
# ---------------------------------------------------------------------------------------

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
WHITE='\033[0;36m'
CEND='\033[0m' # No color (default text color)

# Vars
EDITOR="vim"

# ZSH Settings
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH_COLORIZE_TOOL="pygmentize"
ZSH_DISABLE_COMPFIX="true"
POWERLEVEL9K_MODE="nerdfont-complete"
export ZSH="$HOME/.oh-my-zsh"

# PLUGINS
plugins=(git colorize colored-man-pages zsh-syntax-highlighting command-not-found)

# Running Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Greeting
# echo "🕑 $(date +"%Y.%m.%d %T")"
# echo

# PATH
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
export PATH=$PATH:/usr/sbin:~/.local/bin

export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# ALIASES
alias zshrc="$EDITOR ~/.zshrc"
alias ohmyzsh="$EDITOR ~/.oh-my-zsh"
alias zshreload="source ~/.zshrc && clear"

alias get="sudo dnf install"
alias remove="sudo dnf remove"
alias upgrade="sudo dnf upgrade"
alias installed="dnf list installed"
alias search="dnf search"

alias ga="g add"
alias gaa="g add --all"
alias gc="g commit -m"
alias gam="g commit --amend"
alias gp="g push"
alias gpf="g push --force"

alias sys="sudo systemctl"

alias temperature="sensors | grep °C"
alias hardware="inxi"
alias cat="bat"
alias ls="eza -a --icons always"
alias la="eza -la --icons always"
alias dd="sudo dd status=progress"
alias e="$EDITOR "
alias cp="cp -r "
alias scp="scp -r "
alias cls="clear && ls"
alias format="sudo mkfs.vfat -IF 32 "
alias rm="gio trash "
alias rmf="command rm "
mcd() {
  md $1
  cd $1
}

# ---------------------------------------------------------------------------------------
# --------------E-N-D---Z-S-H---C-O-N-F-I-G----------------------------------------------
# ---------------------------------------------------------------------------------------

# p10k ending
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
