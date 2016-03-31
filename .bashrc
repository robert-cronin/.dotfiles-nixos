# .bashrc is sourced for interactive shells which can be login

# if not running interactively, don't do anything
[[ "$-" != *i* ]] && return

# xpg_echo - align with ZSH behaviour
# lastpipe - align with ZSH behaviour
# no_empty_cmd_completion - align with ZSH behaviour
BASHOPTS=\
'autocd:\
cdspell:\
checkhash:\
checkjobs:\
checkwinsize:\
cmdhist:\
extglob:\
globstar:\
histappend:\
interactive_comments:\
lastpipe:\
lithist:\
no_empty_cmd_completion:\
shift_verbose:\
xpg_echo'

HISTFILE="${HOME}/.bash_history"
HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL='ignoreboth'
HISTTIMEFORMAT='%F %T '

PS1='\[\e]0;\w\a\]\n\[\e[32m\]\u ➜ \h  ➜ \[\e[33m\]\w\[\e[0m\]\n \$ '
PS2='$> ';
PS4='$0 - $LINENO $+ '

#include "./.shell_functions"

# bash functions

#include "./.shell_aliases"

# bash aliases
