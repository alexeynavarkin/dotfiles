export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Antigen.
## Load antigen itself.
source $HOME/bin/antigen.zsh

## Load the oh-my-zsh's library.
antigen use oh-my-zsh

## Load default plugins.
antigen bundle git

## Load custom plugins.
antigen bundle zsh-users/zsh-completions
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-syntax-highlighting

## Load theme.
antigen theme mortalscumbag

## All done, let's apply.
antigen apply
# Antigen.

# User binaries to PATH.
export PATH="$PATH:$HOME/bin"
#

# Python
## Pyenv
export PYENV_ROOT="$HOME/.pyenv"
eval "$(pyenv init -)"
#

# JS
## Node
export NVM_DIR="$HOME/.nvm"
[ -s "/usr/local/opt/nvm/nvm.sh" ] && \. "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/usr/local/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion
#

# Golang
export GOPATH=$HOME/go
export GOBIN=$HOME/go/bin
#