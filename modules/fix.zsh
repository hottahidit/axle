# Fix the last command, in the spirit of thefuck (and oh-my-zsh's sudo plugin): after a
# typo or a "permission denied", `fix` (or Esc Esc) puts the corrected command on the line
# for you to check, then Enter runs it. Nothing runs by itself.
#
#   gti status            → git status            (a command that doesn't exist)
#   git psuh              → git push              (a git subcommand that doesn't exist)
#   git push              → git push -u origin x  (the branch has no upstream yet)
#   cd Donwloads          → cd Downloads          (a file or folder that doesn't exist)
#   ./deploy.sh           → chmod +x ./deploy.sh && ./deploy.sh
#   apt install htop      → sudo apt install htop (needs root)
#
# Esc Esc on an empty line: the fix, or the last command with sudo. On a line you're
# typing: adds or removes sudo.
#
# On Enter, a command that doesn't exist with one close to it that does (ckear → clear):
# asks "run clear?". Enter or y runs clear; n runs ckear as you typed it; e puts clear
# on the line to edit; Esc goes back to the line. After `axle run` says why a service or task failed (a
# missing package, a port that's taken, a database not started), its fix comes first.
#
#   AXLE_FIX_CMD=fix      the command's name ('' = none; Esc Esc still works)
#   AXLE_FIX_KEY='^[^['   the key (Esc Esc; '' = none)
#   AXLE_FIX_CORRECT=1    ask on Enter (0 = never; zsh's own `setopt correct` also turns it off)

: ${AXLE_FIX_CMD=fix}
(( ${+AXLE_FIX_KEY} )) || typeset -g AXLE_FIX_KEY='^[^['

typeset -ga _axle_fix_git_cmds

# Keys next to each other on a QWERTY keyboard (ckear: k is next to l).
typeset -gA _axle_fix_near=(
  q wa  w qeas  e wrsd  r etdf  t ryfg  y tugh  u yihj  i uojk  o ipkl  p ol
  a qwsz  s awedxz  d serfcx  f drtgvc  g ftyhbv  h gyujnb  j huikmn  k jiolm  l kop
  z asx  x zsdc  c xdfv  v cfgb  b vghn  n bhjm  m njk
)

# Edit distance in half mistakes (REPLY): a letter added or missing is a mistake (2); a
# wrong letter is one (2), or half of one (1) when its key is next to the right one; two
# letters swapped (gti) is half of one (1).
_axle_fix_distance() {
  local a=$1 b=$2 x y
  local -i la=${#a} lb=${#b} i j cost best
  local -A d
  for (( i = 0; i <= la; i++ )); do d[$i,0]=$(( 2 * i )); done
  for (( j = 0; j <= lb; j++ )); do d[0,$j]=$(( 2 * j )); done
  for (( i = 1; i <= la; i++ )); do
    for (( j = 1; j <= lb; j++ )); do
      x=${a[i]} y=${b[j]}
      if [[ $x == $y ]]; then cost=0
      elif [[ ${_axle_fix_near[${(L)x}]} == *${(L)y}* && -n $y ]]; then cost=1
      else cost=2; fi
      best=$(( d[$((i-1)),$j] + 2 ))
      (( d[$i,$((j-1))] + 2 < best )) && best=$(( d[$i,$((j-1))] + 2 ))
      (( d[$((i-1)),$((j-1))] + cost < best )) && best=$(( d[$((i-1)),$((j-1))] + cost ))
      if (( i > 1 && j > 1 )) && [[ ${a[i]} == ${b[j-1]} && ${a[i-1]} == ${b[j]} ]]; then
        (( d[$((i-2)),$((j-2))] + 1 < best )) && best=$(( d[$((i-2)),$((j-2))] + 1 ))
      fi
      d[$i,$j]=$best
    done
  done
  REPLY=${d[$la,$lb]}
}

# The closest of the candidates to a word (REPLY), or status 1. Close means one mistake for
# short words, two for longer ones; ties go to the candidate you use most, then the shorter.
# (_axle_fix_limit, set by a caller: at most that many half mistakes.)
_axle_fix_closest() {
  local word=$1 c; shift
  local -i max=$(( ${#word} > 4 ? 4 : 2 )) best=99 uses bestuses=-1
  (( ${_axle_fix_limit:-0} )) && max=$_axle_fix_limit
  local found=''
  for c; do
    [[ $c == $word ]] && continue
    (( 2 * (${#c} - ${#word}) <= max && 2 * (${#word} - ${#c}) <= max )) || continue
    # Cheap first: share the first letter, or the first two are swapped (sl → ls).
    [[ ${c[1]} == ${word[1]} || ( ${c[1]} == ${word[2]} && ${c[2]} == ${word[1]} ) ]] || continue
    _axle_fix_distance $word $c
    (( REPLY <= max )) || continue
    uses=${_axle_sg_count[$c]:-0}
    if (( REPLY < best || ( REPLY == best && uses > bestuses ) ||
          ( REPLY == best && uses == bestuses && ${#c} < ${#found} ) )); then
      best=$REPLY found=$c bestuses=$uses
    fi
  done
  REPLY=$found
  [[ -n $found ]]
}

# A name that runs: an alias, function, builtin, reserved word or command on PATH.
_axle_fix_exists() {
  (( $+aliases[$1] || $+functions[$1] || $+builtins[$1] || $+reswords[$1] || $+commands[$1] ))
}

# Commands worth comparing a typo against (reply): what you've run that still exists,
# aliases, functions, builtins.
_axle_fix_mine() {
  local c
  reply=()
  for c in ${(k)_axle_sg_count}; do reply+=(${c%% *}); done
  reply=(${(u)reply})
  for c in $reply; do _axle_fix_exists $c || reply=(${reply:#${(b)c}}); done
  reply+=(${(k)aliases} ${(k)builtins} ${${(k)functions}:#_*})
}

# The closest command to a word (REPLY): yours first, then (only if that finds nothing)
# everything on PATH.
_axle_fix_command() {
  local word=$1 reply
  _axle_fix_mine
  _axle_fix_closest $word $reply && return 0
  _axle_fix_closest $word ${(k)commands}
}

# The best fix for a command that failed with <exit> in <dir> (REPLY), or status 1.
_axle_fix_suggest() {
  setopt localoptions extendedglob
  local cmd=$1 dir=${3:-$PWD}
  local -i exit=$2
  local -a w=(${(z)cmd})
  (( ${#w} )) || return 1
  local first=${(Q)w[1]} word arg new i
  REPLY=''

  # Not executable: make it so, then run it.
  if (( exit == 126 )) && [[ $first == */* && -f ${~first} && ! -x ${~first} ]]; then
    REPLY="chmod +x ${w[1]} && $cmd"; return 0
  fi

  if [[ $first == git && exit -ne 0 ]]; then
    # git push on a branch with no upstream yet.
    if [[ $w[2] == push && ${#w} == 2 ]] && ! command git -C $dir rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      local branch=$(command git -C $dir symbolic-ref --short HEAD 2>/dev/null)
      local remote=$(command git -C $dir remote 2>/dev/null | head -1)
      [[ -n $branch && -n $remote ]] && { REPLY="git push -u ${remote} ${branch}"; return 0 }
    fi
    # A git subcommand that doesn't exist (git's own list, and your aliases).
    if [[ -n $w[2] && $w[2] != -* ]]; then
      (( ${#_axle_fix_git_cmds} )) ||
        _axle_fix_git_cmds=(${(f)"$(command git --list-cmds=main,others,alias,nohelpers 2>/dev/null)"})
      if (( ${#_axle_fix_git_cmds} )) && (( ! ${_axle_fix_git_cmds[(Ie)$w[2]]} )) &&
         _axle_fix_closest $w[2] $_axle_fix_git_cmds; then
        w[2]=$REPLY; REPLY=${(j: :)w}; return 0
      fi
    fi
  fi

  # A command that doesn't exist.
  if (( exit == 127 )) && [[ $first != */* ]]; then
    _axle_fix_command $first && { w[1]=$REPLY; REPLY=${(j: :)w}; return 0 }
    return 1
  fi

  # A file or folder that doesn't exist: the closest name in its folder.
  if (( exit != 0 )); then
    for (( i = 2; i <= ${#w}; i++ )); do
      arg=${(Q)w[i]}
      [[ $arg == -* || $arg == *[\*\?\[\$\`]* || -z $arg ]] && continue
      local full=${~arg}
      [[ $full != /* ]] && full=$dir/$full
      [[ -e $full ]] && continue
      local parent=${full:h} name=${full:t}
      [[ -d $parent ]] || continue
      local -a entries=($parent/*(DN:t))
      new=''
      # Only the case differs (readme.md → README.md), else the closest name.
      new=${(M)entries:#(#i)${(b)name}}
      [[ -n $new ]] || { _axle_fix_closest $name $entries && new=$REPLY }
      if [[ -n $new ]]; then
        [[ $arg == */* ]] && new=${arg:h}/$new
        w[i]=${(q-)new}
        REPLY=${(j: :)w}; return 0
      fi
    done
  fi

  # Needs root.
  if (( exit != 0 )) && [[ $first != (sudo|doas) ]]; then
    local needs=0
    case $first in
      apt|apt-get|aptitude|dnf|yum|zypper|pacman|apk|snap|flatpak)
        [[ ${w[2]} == (install|remove|purge|update|upgrade|autoremove|dist-upgrade|full-upgrade|reinstall|-S*|-R*|-U*|add|del) ]] && needs=1 ;;
      systemctl|service)
        [[ ${(j: :)w} == *(start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload)* ]] && needs=1 ;;
      mount|umount|modprobe|useradd|userdel|usermod|groupadd|ufw|iptables|nft|reboot|shutdown|poweroff|chroot|visudo)
        needs=1 ;;
      chown|chmod|chgrp)
        local last=${~${(Q)w[-1]}}
        [[ -e $last && ! -O $last ]] && needs=1 ;;
      tee|cp|mv|rm|mkdir|touch|ln|vi|vim|nvim|nano)
        local t=${~${(Q)w[-1]}}
        [[ $t == /* && $t != $HOME(|/*) && $t != /tmp(|/*) ]] && needs=1 ;;
    esac
    (( needs )) && { REPLY="sudo $cmd"; return 0 }
  fi
  return 1
}

# `fix`: the corrected last command, on the line to check.
_axle_fix_cmd() {
  if [[ -n $_axle_run_fix ]]; then                 # (axle run's, until the next command)
    print -z -r -- "$_axle_run_fix"; _axle_run_fix=''; return 0
  fi
  local last=$_axle_ev_last_cmd
  [[ -n $last ]] || { print -u2 "axle: nothing to fix yet"; return 1 }
  if (( _axle_ev_last_exit == 0 )); then
    print -u2 -r -- "axle: the last command worked: $last"; return 1
  fi
  if _axle_fix_suggest "$last" $_axle_ev_last_exit "$_axle_ev_last_dir"; then
    print -z -r -- "$REPLY"
  else
    print -u2 -r -- "axle: no fix found for: $last"; return 1
  fi
}

# Esc Esc: on an empty line the fix (or the last command with sudo); else toggle sudo.
axle-fix() {
  if [[ -z $BUFFER ]]; then
    local last=$_axle_ev_last_cmd
    if [[ -n $_axle_run_fix ]]; then
      BUFFER=$_axle_run_fix
    elif [[ -z $last ]]; then
      return 0
    elif (( _axle_ev_last_exit )) && _axle_fix_suggest "$last" $_axle_ev_last_exit "$_axle_ev_last_dir"; then
      BUFFER=$REPLY
    else
      BUFFER="sudo $last"
    fi
  elif [[ $BUFFER == sudo\ * ]]; then
    BUFFER=${BUFFER#sudo }
  else
    BUFFER="sudo $BUFFER"
  fi
  CURSOR=${#BUFFER}
}

# --- install -------------------------------------------------------------------------

# A command that doesn't exist, said in Axle's colours with the one you probably meant:
#   ✘ gti: no such command
#     did you mean git? (Esc Esc puts it on the line)
# The guess only looks at what you run, aliases, functions and builtins (listing all of
# PATH is slow; Esc Esc looks there too). A handler another tool set up is left alone.
: ${AXLE_FIX_NOTFOUND=1}
if (( AXLE_FIX_NOTFOUND )) && (( ! $+functions[command_not_found_handler] )); then
  command_not_found_handler() {
    local w=${1//[[:cntrl:]]/?} REPLY reply
    local m=${_axle_c[muted]:-244}
    _axle_printp "%F{${_axle_c[error]:-red}}✘%f %B${w//\%/%%}%b%F{$m}: no such command%f" >&2
    (( ${_axle_fix_declined[(Ie)$1]} )) && return 127   # (you said no to the close one on Enter)
    _axle_fix_mine
    if _axle_fix_closest "$1" $reply; then
      local how='fix puts it on the line'
      [[ -n $AXLE_FIX_KEY ]] && how='Esc Esc puts it on the line'
      [[ -z $AXLE_FIX_KEY && -z $AXLE_FIX_CMD ]] && how=''
      _axle_printp "  %F{$m}did you mean%f %F{${_axle_c[accent]:-magenta}}${REPLY//\%/%%}%f%F{$m}?${how:+ ($how)}%f" >&2
    fi
    return 127
  }
fi

# A line zsh can't read as a command (it would only say "parse error near `<>'"): said on
# Enter in Axle's style, and the line stays to fix. Enter again runs it as it is (zsh then
# says its own). An unfinished line (an open quote, if, for, {, $(, a | at the end) goes on
# to the next line as zsh does: it's parsed as a function body (in this shell, nothing
# runs) with a line after it; when only that line is wrong, it was just unfinished.
: ${AXLE_FIX_PARSE=1}
typeset -g _axle_fix_refused=''
_axle_fix_parse_ok() {
  setopt localoptions extendedglob
  (( AXLE_FIX_PARSE )) || return 0
  local text=$PREBUFFER$BUFFER msg='' f
  [[ -n ${text//[[:space:]]/} ]] || return 0
  [[ $text == $_axle_fix_refused ]] && { _axle_fix_refused=''; return 0 }
  _axle_fix_refused=''
  (( $+functions[_axle_fix_chk] )) && unfunction _axle_fix_chk
  functions[_axle_fix_chk]=$text 2>/dev/null
  (( $+functions[_axle_fix_chk] )) && { unfunction _axle_fix_chk; return 0 }
  f=${XDG_CACHE_HOME:-$HOME/.cache}/axle/parse.$$
  command mkdir -p -- ${f:h} 2>/dev/null
  functions[_axle_fix_chk]=$text$'\n'_axle_fix_next_line 2>$f
  (( $+functions[_axle_fix_chk] )) && { unfunction _axle_fix_chk; command rm -f -- $f; return 0 }
  [[ -r $f ]] && msg=${${(f)"$(<$f)"}[1]}
  command rm -f -- $f
  local -i lines=$(( ${#text//[^$'\n']/} + 1 ))
  [[ $msg =~ ':([0-9]+): (.*)$' ]] || return 0      # (not one we know: zsh's turn)
  local -i at=$match[1]; local what=$match[2]
  (( at > lines )) && [[ $what != *'near `\n'"'"* ]] && return 0   # unfinished
  # Wrong as it is: say why, keep the line.
  local why=$what
  case $what in
    *'near `\n'"'"*)
      why="something is missing at the end"
      [[ ${text%%[[:space:]]#} =~ '([<>|&;]+)$' ]] && why="something is missing after $match[1]" ;;
    'parse error near `'*) why="unexpected ${${what#*\`}%\'}" ;;
    'parse error: '*)  why=${what#parse error: } ;;
  esac
  why=${why//[[:cntrl:]]/?}
  local m=${_axle_c[muted]:-244}
  zle -I
  _axle_printp "%F{${_axle_c[error]:-red}}✘%f zsh can't read this line: %B${why//\%/%%}%b"
  _axle_printp "  %F{$m}it's kept to fix; Enter again runs it as it is%f"
  _axle_fix_refused=$text
  return 1
}
# --- correcting on Enter ------------------------------------------------------------

: ${AXLE_FIX_CORRECT=1}
typeset -ga _axle_fix_declined=()
# Commands that delete or overwrite: a correction into one of them is asked with No first.
typeset -g _axle_fix_risky='(rm|rmdir|unlink|shred|dd|mkfs|mkfs.*|fdisk|parted|wipefs|kill|killall|pkill|reboot|shutdown|poweroff|halt|truncate|mv|cp|ln|chmod|chown|chgrp|install)'

# One word in command position that isn't a command, and the one close to it that is
# (REPLY), or status 1. Only plain names: not a path, a variable, a pattern, a folder
# (auto_cd) or a file a suffix alias opens. Close, in half mistakes: 1 for up to three
# letters (only two swapped, or a key next to the right one: rg is never rm), 2 for four,
# 3 for five or more.
_axle_fix_typo_word() {
  setopt localoptions extendedglob
  local w=$1 reply
  REPLY=''
  [[ ${#w} -ge 2 && $w == [[:alnum:]][[:alnum:]._+-]# ]] || return 1
  _axle_fix_exists $w && return 1
  (( $+galiases[$w] )) && return 1
  [[ -o autocd && -d $w ]] && return 1
  [[ $w == *.* && -n ${saliases[${w##*.}]} ]] && return 1
  whence -p -- $w >/dev/null 2>&1 && return 1     # (installed since the last rehash)
  local -i _axle_fix_limit=$(( ${#w} >= 5 ? 3 : ${#w} == 4 ? 2 : 1 ))
  _axle_fix_mine
  _axle_fix_closest $w $reply || _axle_fix_closest $w ${(k)commands} || return 1
  # (two letters are too few to be sure of one that deletes things: rn is never rm)
  (( ${#w} < 3 )) && [[ $REPLY == ${~_axle_fix_risky} ]] && return 1
  _axle_fix_exists $REPLY
}

# A line with its mistyped commands corrected (REPLY; reply: the words it changed), or
# status 1. Commands are the first word, and the first after ; | || && & ( { ! and
# after if, while, then, do, else, sudo, command, env, time, nice, nohup, VAR=value.
# A line that defines a function or alias, or runs over several lines, is left alone.
_axle_fix_typos() {
  setopt localoptions extendedglob
  local line=$1 t
  REPLY='' reply=()
  [[ $line == *$'\n'* || $line == *'()'* ]] && return 1
  local -a tok=(${(Z+C+)line}) at=() to=() typo=()
  local -i pos=1 i expect=1 n
  for t in $tok; do
    n=${line[pos,-1][(i)${(b)t}]}
    (( n > ${#line} - pos + 1 )) && return 1        # (not found as written: leave it)
    (( pos += n - 1 ))
    if (( expect )); then
      case $t in
        ('|'|'||'|'&&'|'&'|'|&'|'&|'|'&!'|';'|';;'|'('|'{'|'!'|if|elif|while|until|then|do|else|time|nocorrect|noglob|builtin|command|exec|sudo|doas|env|nice|nohup) ;;
        ([[:alpha:]_][[:alnum:]_]#(\[*\])#(|+)=*) ;;
        (function|alias|unalias|hash|unhash|unfunction) return 1 ;;   # (names change here)
        (*)
          expect=0
          if [[ $t != -* ]] && _axle_fix_typo_word $t; then
            at+=($pos) to+=($REPLY) typo+=($t)
          fi ;;
      esac
    else
      [[ $t == ('|'|'||'|'&&'|'&'|'|&'|'&|'|'&!'|';'|';;'|'('|'{') ]] && expect=1
    fi
    (( pos += ${#t} ))
  done
  (( ${#at} )) || return 1
  # From the end, so the positions before stay right.
  for (( i = ${#at}; i >= 1; i-- )); do
    line=${line[1,at[i]-1]}${to[i]}${line[at[i]+${#typo[i]},-1]}
  done
  REPLY=$line reply=($typo)
}

# On Enter: a mistyped command is asked about below the line. Status 0: run the line
# (corrected, or as typed); 1: stay on it.
_axle_fix_correct_ok() {
  _axle_fix_declined=()
  (( AXLE_FIX_CORRECT )) || return 0
  [[ -o correct || -o correctall ]] && return 0     # (zsh's own asks: not twice)
  [[ -z $PREBUFFER ]] || return 0
  local REPLY reply
  _axle_fix_typos "$BUFFER" || return 0
  local new=$REPLY key w
  local -a typo=($reply)
  local def=y
  for w in ${(z)new}; do [[ $w == ${~_axle_fix_risky} ]] && def=n; done
  local what="${(j:, :)typo} isn't a command"
  (( ${#typo} > 1 )) && what="${(j:, :)typo} aren't commands"
  local q="  $what: run " hint=' (Y/n, e to edit)'
  [[ $def == n ]] && hint=' (y/N, e to edit)'
  local shown=${(V)new}
  local -a hl_was=("${(@)region_highlight}")
  local post_was=$POSTDISPLAY
  POSTDISPLAY=$'\n'"$q$shown?$hint"
  local -i s=$(( ${#BUFFER} + 1 + ${#q} ))
  local acc=${_axle_c[accent]:-magenta} muted=${_axle_c[muted]:-244}
  region_highlight+=("${#BUFFER} $s fg=$muted" "$s $(( s + ${#shown} )) fg=$acc,bold"
                     "$(( s + ${#shown} + 1 )) $(( s + ${#shown} + 1 + ${#hint} )) fg=$muted")
  zle -R
  read -k 1 key
  POSTDISPLAY=$post_was region_highlight=("${(@)hl_was}")
  [[ $key == ($'\r'|$'\n') ]] && key=$def          # (Enter: the answer shown first)
  case $key in
    (y|Y) BUFFER=$new; CURSOR=${#BUFFER}; return 0 ;;
    (n|N) _axle_fix_declined=($typo); return 0 ;;
    (e|E) BUFFER=$new; CURSOR=${#BUFFER}; zle -R; return 1 ;;
    (*)   zle -R; return 1 ;;
  esac
}

# Everything Enter checks before the line runs (suggest's Enter calls it too).
_axle_fix_enter_ok() { _axle_fix_parse_ok && _axle_fix_correct_ok }
_axle_fix_accept_line() { _axle_fix_enter_ok && zle .accept-line; return 0 }   # (no beep when it stays)

if [[ -n $AXLE_FIX_CMD ]]; then
  functions[$AXLE_FIX_CMD]='_axle_fix_cmd "$@"'
  axle_command fix _axle_fix_cmd tool "fix  ($AXLE_FIX_CMD)" 'correct the last command (on the line, to check)'
fi
if (( $+builtins[zle] )) && [[ -n $AXLE_FIX_KEY ]]; then
  zle -N axle-fix
  bindkey -M emacs "$AXLE_FIX_KEY" axle-fix
fi
# Enter checks the line first (suggest's own Enter calls the check too, whichever loads first).
if (( $+builtins[zle] )) && [[ ${widgets[accept-line]} == builtin ]]; then
  zle -N accept-line _axle_fix_accept_line
fi
