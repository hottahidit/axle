# hints: when you type out a command one of your aliases covers, a quiet line says so
# (in the spirit of zsh-you-should-use), and `axle alias suggest` proposes aliases for the
# long commands you type often.
#
#   git status   →   hint: you have an alias for that: gst
#
# Shell aliases (oh-my-zsh's git plugin alone has about 200), global aliases (alias -g) and
# git's own aliases (git config alias.*). Each alias is mentioned at most once a day, and
# never for a line run through sudo, time and the like, or when you typed the alias.
#
#   axle alias suggest        long commands you type often, with a short name for each:
#                             tick the ones you want; saved to Axle's config
#   axle alias [ls]           the aliases Axle saved for you
#   axle alias rm <name>      remove one
#
#   AXLE_HINTS=1              0 = no hints (axle alias still works)

: ${AXLE_HINTS:=1}
typeset -gA _axle_hint_seen          # alias -> the day it was last mentioned
typeset -gA _axle_hint_git           # git alias's command -> its name
typeset -g  _axle_hint_file=${XDG_CACHE_HOME:-$HOME/.cache}/axle/hints
typeset -gi _axle_hint_loaded=0
typeset -g  _axle_hint_gitdir=$'\0'   # where git's aliases were read (they can be per repo)

# Which alias covers a command line (REPLY = what to type instead), or status 1. The
# longest alias value the line starts with, if the alias is shorter by 3 or more.
_axle_hint_find() {
  setopt localoptions extendedglob
  local line=${1##[[:space:]]#} name value best='' bestv='' first=${${1##[[:space:]]#}%%[[:space:]]*}
  REPLY=''
  # (Not for what you typed through sudo, time, ...: the alias wouldn't work there.)
  [[ $first == (sudo|doas|time|nice|nohup|command|builtin|exec|noglob|nocorrect|env|-*) ]] && return 1
  (( ${+aliases[$first]} )) && return 1           # (you typed an alias)
  for name value in "${(@kv)aliases}"; do
    [[ ${value%%[[:space:]]*} == $first ]] || continue          # (cheap check first)
    [[ $line == $value || $line == "$value "* ]] || continue
    (( ${#name} + 3 <= ${#value} && ${#value} > ${#bestv} )) || continue
    best=$name bestv=$value
  done
  if [[ -n $best ]]; then
    REPLY=$best${line#$bestv}
    return 0
  fi
  # git's own aliases: git config alias.st status → git st
  if [[ $first == git ]]; then
    if [[ $_axle_hint_gitdir != $PWD ]]; then
      _axle_hint_gitdir=$PWD _axle_hint_git=()
      local l
      for l in "${(@f)$(command git config --get-regexp '^alias\.' 2>/dev/null)}"; do
        [[ $l == alias.(#b)([^ ]##)\ (*) && $match[2] != \!* ]] && _axle_hint_git[$match[2]]=$match[1]
      done
    fi
    local rest=${line#git[[:space:]]##} sub
    for value name in "${(@kv)_axle_hint_git}"; do
      [[ $rest == $value || $rest == "$value "* ]] || continue
      (( ${#name} + 3 <= ${#value} && ${#value} > ${#bestv} )) || continue
      best=$name bestv=$value
    done
    [[ -n $best ]] && { REPLY="git $best${rest#$bestv}"; return 0 }
  fi
  # A global alias for a piece of it: alias -g G='| grep' covers "... | grep x"
  for name value in "${(@kv)galiases}"; do
    (( ${#name} + 3 <= ${#value} )) || continue
    [[ " $line " == *" $value "* ]] && { REPLY="${line/$value/$name}"; return 0 }
  done
  return 1
}

_axle_hint_load() {
  (( _axle_hint_loaded )) && return
  _axle_hint_loaded=1
  local name day
  [[ -r $_axle_hint_file ]] || return
  while IFS=$'\t' read -r name day; do
    [[ -n $name && $day == <-> ]] && _axle_hint_seen[$name]=$day
  done < $_axle_hint_file
}

_axle_hint_done() {
  (( AXLE_HINTS )) || return 0
  local -i code=$1
  (( code == 127 )) && return 0                    # (it didn't run: fix's turn)
  local REPLY
  _axle_hint_find "$3" || return 0
  local short=$REPLY name=${${REPLY#git }%%[[:space:]]*}
  _axle_hint_load
  local -i today=$(( EPOCHSECONDS / 86400 ))
  [[ ${_axle_hint_seen[$name]} == $today ]] && return 0
  _axle_hint_seen[$name]=$today
  mkdir -p ${_axle_hint_file:h} 2>/dev/null
  local k; { for k in ${(k)_axle_hint_seen}; do print -r -- "$k"$'\t'"$_axle_hint_seen[$k]"; done } >| $_axle_hint_file 2>/dev/null
  local m=${_axle_c[muted]:-244}
  _axle_printp "%F{$m}hint: you have an alias for that: %B${short//\%/%%}%b%f"
}

# --- axle alias ---------------------------------------------------------------------

# A short name for a command that nothing else uses (REPLY): the first letters of its
# words (options and paths left out), then more letters, then a number.
_axle_alias_name() {
  setopt localoptions extendedglob
  local -a w=(${(z)1}) words=()
  local t name
  for t in $w; do [[ $t == [[:alpha:]][[:alnum:]_-]# ]] && words+=($t); done
  (( ${#words} )) || words=(x)
  name=${(j::)${(@)words//(#b)(?)*/$match[1]}}
  _axle_alias_free $name && { REPLY=$name; return }
  local -i i
  for (( i = 2; i <= ${#words[-1]}; i++ )); do
    _axle_alias_free $name${words[-1][i]} && { REPLY=$name${words[-1][i]}; return }
  done
  for (( i = 2; i <= 9; i++ )); do _axle_alias_free $name$i && { REPLY=$name$i; return }; done
  REPLY=''
}

# Is a name free: no alias, function, builtin, keyword or program has it?
_axle_alias_free() {
  [[ ${#1} -ge 2 ]] || return 1
  (( ${+aliases[$1]} || ${+functions[$1]} || ${+builtins[$1]} || ${reswords[(Ie)$1]} )) && return 1
  whence -p -- $1 >/dev/null 2>&1 && return 1
  return 0
}

# Long commands you've typed often (from Axle's history log, the last 90 days): their
# first 2–5 words, at least 12 letters, 5 times or more; not already an alias. reply=()
# with "count<TAB>command", the most typing saved first.
_axle_alias_candidates() {
  setopt localoptions extendedglob
  reply=()
  [[ -r $_axle_hist_file ]] || return 1
  local -i since=$(( EPOCHSECONDS - 90 * 86400 ))
  local -A count=()
  local cmd
  local -a w
  local -i n
  for cmd in "${(@f)$(command awk -F'\t' -v s=$since 'NF == 6 && $1 ~ /^[0-9]+$/ && $1 >= s && $2 == 0 { print $6 }' $_axle_hist_file 2>/dev/null)}"; do
    [[ $cmd == *(\\n|\;|\&\&|\|\||\||\$\(|\`)* ]] && continue        # (one simple command)
    w=(${(z)cmd})
    (( ${+aliases[$w[1]]} )) && continue
    for (( n = 2; n <= ${#w} && n <= 5; n++ )); do
      local pre=${(j: :)w[1,n]}
      (( ${#pre} >= 12 )) && (( count[$pre]++ ))
    done
  done
  local -a scored=()
  local c v
  for c n in "${(@kv)count}"; do
    (( n >= 5 )) || continue
    for v in ${(v)aliases}; do [[ $v == $c ]] && continue 2; done
    scored+=("${(l:8::0:)$(( n * ${#c} ))}"$'\t'"$n"$'\t'"$c")
  done
  # Best first; a shorter prefix used no more often than a longer one is left out.
  local s prev='' k
  local -i dup
  local -a kept=()
  for s in ${(On)scored}; do
    c=${s#*$'\t'*$'\t'}
    dup=0
    for k in $kept; do
      k=${k#*$'\t'}
      [[ $k == "$c "* || $c == "$k "* || $k == $c ]] && dup=1    # (one inside the other)
    done
    (( dup )) || kept+=("${${s#*$'\t'}%%$'\t'*}"$'\t'"$c")
    (( ${#kept} >= 8 )) && break
  done
  reply=($kept)
  (( ${#reply} ))
}

_axle_cmd_alias() {
  setopt localoptions extendedglob
  local -a reply lines
  # (Axle's config file: read and written by lib/settings.zsh, loaded when first used)
  (( $+functions[_axle_config_lines] )) || _axle_lazy_load lib/settings.zsh _axle_config_write
  case ${1:-ls} in
    ls)
      _axle_config_lines
      lines=(${(M)reply:#alias *})
      if (( ! ${#lines} )); then
        print -r -- "No aliases saved by Axle yet. axle alias suggest proposes some."
      else
        print -rl -- $lines
      fi ;;
    suggest)
      _axle_alias_candidates || { print -r -- "Nothing typed often enough yet (5 times in 90 days, 12+ letters)."; return 0 }
      local -a opts=() names=() cmds=()
      local x c n
      for x in $reply; do
        n=${x%%$'\t'*} c=${x#*$'\t'}
        _axle_alias_name "$c"; [[ -n $REPLY ]] || continue
        names+=($REPLY) cmds+=("$c")
        opts+=("${(r:6:)REPLY} ${c//:/∶}  (${n}×):${#names}")
      done
      (( ${#opts} )) || { print -r -- "No free short names for them."; return 0 }
      axle_checkbox "Aliases to add (saved to Axle's config):" '' $opts || return 1
      (( ${#reply} )) || return 0
      local i line
      for i in $reply; do
        line="alias ${names[i]}=${(qq)cmds[i]}"
        _axle_config_write "alias ${names[i]}" "$line" || return 1
        alias -- "${names[i]}=${cmds[i]}"
        print -r -- "  $line"
      done
      print -r -- "Saved to ${AXLE_CONFIG/#$HOME/~} (axle alias rm <name> removes one)." ;;
    rm)
      [[ -n $2 ]] || { print -u2 "usage: axle alias rm <name>"; return 1 }
      _axle_config_lines
      lines=(${(M)reply:#alias $2=*})
      (( ${#lines} )) || { print -u2 -r -- "axle: no alias $2 saved by Axle"; return 1 }
      _axle_config_write "alias $2" '' || return 1
      unalias -- $2 2>/dev/null
      print -r -- "removed $2" ;;
    *) print -u2 "usage: axle alias [ls | suggest | rm <name>]"; return 1 ;;
  esac
}

# --- install -------------------------------------------------------------------------

zmodload zsh/parameter 2>/dev/null
_axle_hook_cmd command-done _axle_hint_done
axle_command alias _axle_cmd_alias tool 'alias [suggest|rm <name>]' 'aliases for what you type often'
