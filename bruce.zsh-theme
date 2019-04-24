local ret_status="%(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"
#PROMPT='${ret_status} %{$fg[cyan]%}%c%{$reset_color%} $(git_prompt_info)'
PROMPT='${ret_status}%{$reset_color%} %{$fg[green]%}%n%{$reset_color%}@%{$fg[green]%}%m%{$reset_color%} %{$fg[cyan]%}%c%{$RESET_COLOR%} $(git_prompt_info)'

#ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:%{$fg[red]%}("
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:("
ZSH_THEME_GIT_PROMPT_SUFFIX=")%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_SEPARATOR="|"
ZSH_THEME_GIT_PROMPT_BRANCH="%{$fg_bold[magenta]%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_STAGED="%{$fg[red]%}%{●%G%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_CONFLICTS="%{$fg[red]%}%{✖%G%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_CHANGED="%{$fg[red]%}%{✚%G%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_BEHIND="%{↓%G%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_AHEAD="%{↑%G%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_UNTRACKED="%{$fg[red]%}%{…%G%}%{$fg_bold[blue]%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%}%{✔%G%}"
