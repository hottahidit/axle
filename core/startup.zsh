# `axle doctor --startup`: where your shell's startup time goes.
#
# Your real setup is started in a separate interactive zsh (in a pty), through a temporary
# ZDOTDIR whose files note the time and then source yours: ~/.zshenv, ~/.zprofile (login),
# ~/.zshrc, ~/.zlogin, exactly where zsh would. Your files aren't changed, history isn't
# written, oh-my-zsh's updater is told to stay quiet. Each file is sourced at top level
# (never from a function, which would change what `typeset` means in it).
#
#   clean runs (3)   wall-clock totals: zsh itself, /etc/zsh, each of your files, the time
#                    to the first prompt (each precmd hook, the prompt itself), compinit
#   one traced run   where ~/.zshrc's time goes, per file, plugin and line (xtrace with
#                    timestamps; scaled to the clean total, so "about")
#
#   axle doctor --startup [--runs N] [--all] [--no-login]

typeset -g _axle_su_dir='' _axle_su_zprof=''

# The temporary ZDOTDIR. Its files read AXLE_SU_* from the environment.
_axle_su_write_dotdir() {
  local d=$1
  # .zshenv: the start, compinit's timer, then yours; then find where your other files are
  # (your .zshenv may set ZDOTDIR) and keep ours in the way.
  cat > $d/.zshenv <<'EOF'
[[ -n $AXLE_SU_ZPROF ]] && zmodload zsh/zprof
zmodload zsh/datetime
print -r -- "mark env-start $EPOCHREALTIME" >> $AXLE_SU_OUT
# compinit, timed and counted wherever it's called from (it's a function either way).
compinit() {
  local -F s=$EPOCHREALTIME
  unfunction compinit; autoload -Uz compinit; compinit "$@"; local r=$?
  print -r -- "compinit $s $EPOCHREALTIME" >> $AXLE_SU_OUT
  functions[compinit]=$_axle_su_compinit
  return r
}
typeset -g _axle_su_compinit=$functions[compinit]
if [[ -n $AXLE_SU_TRACE ]]; then
  exec 2>>$AXLE_SU_OUT.trace
  PS4=$'+%D{%s.%6.}\x1f%x\x1f%I> '
  setopt xtrace
fi
ZDOTDIR=$AXLE_SU_HOMEDIR
[[ -r $ZDOTDIR/.zshenv ]] && source $ZDOTDIR/.zshenv
typeset -g AXLE_SU_REAL=${ZDOTDIR:-$HOME}
ZDOTDIR=$AXLE_SU_DOTDIR
print -r -- "mark env-end $EPOCHREALTIME" >> $AXLE_SU_OUT
EOF
  cat > $d/.zprofile <<'EOF'
print -r -- "mark profile-start $EPOCHREALTIME" >> $AXLE_SU_OUT
ZDOTDIR=$AXLE_SU_REAL
[[ -r $ZDOTDIR/.zprofile ]] && source $ZDOTDIR/.zprofile
ZDOTDIR=$AXLE_SU_DOTDIR
print -r -- "mark profile-end $EPOCHREALTIME" >> $AXLE_SU_OUT
EOF
  # .zshrc: yours; then ZDOTDIR back to yours (so .zlogin is yours), and at the first
  # prompt: each precmd hook timed, the prompt expanded, then out (history not saved).
  cat > $d/.zshrc <<'EOF'
print -r -- "mark rc-start $EPOCHREALTIME" >> $AXLE_SU_OUT
if [[ -n $AXLE_SU_TRACE ]]; then
  print -u2 -r -- "+$EPOCHREALTIME"$'\x1f'"BEGIN"$'\x1f'"0> "
fi
ZDOTDIR=$AXLE_SU_REAL
[[ -r $ZDOTDIR/.zshrc ]] && source $ZDOTDIR/.zshrc
if [[ -n $AXLE_SU_TRACE ]]; then
  print -u2 -r -- "+$EPOCHREALTIME"$'\x1f'"END"$'\x1f'"0> "
  unsetopt xtrace
fi
print -r -- "mark rc-end $EPOCHREALTIME" >> $AXLE_SU_OUT
[[ -n $AXLE_ROOT ]] && print -r -- "axleroot $AXLE_ROOT" >> $AXLE_SU_OUT
typeset -ga _axle_su_hooks=($precmd_functions)
(( $+functions[precmd] )) && _axle_su_hooks=(precmd $_axle_su_hooks)
_axle_su_first_prompt() {
  print -r -- "mark precmd-start $EPOCHREALTIME" >> $AXLE_SU_OUT
  local fn; local -F s
  for fn in $_axle_su_hooks; do
    (( $+functions[$fn] )) || continue
    s=$EPOCHREALTIME; $fn
    print -r -- "hook $fn $s $EPOCHREALTIME" >> $AXLE_SU_OUT
  done
  s=$EPOCHREALTIME
  # (as zsh draws it: with prompt_subst, its $(...) and ${...} too)
  local p r
  if [[ -o promptsubst ]]; then p=${(%)${(e)PS1}} r=${(%)${(e)RPS1}}; else p=${(%)PS1} r=${(%)RPS1}; fi
  print -r -- "hook (the prompt itself) $s $EPOCHREALTIME" >> $AXLE_SU_OUT
  print -r -- "mark prompt $EPOCHREALTIME" >> $AXLE_SU_OUT
  [[ -n $AXLE_SU_ZPROF ]] && zprof > $AXLE_SU_OUT.zprof
  unset HISTFILE
  print -r -- done > $AXLE_SU_OUT.done
  exit 0
}
precmd_functions=(_axle_su_first_prompt)
unfunction precmd 2>/dev/null
EOF
  print -r -- 'print -r -- "mark login-end $EPOCHREALTIME" >> $AXLE_SU_OUT' > $d/.zlogin
  print -r -- 'ZDOTDIR=$AXLE_SU_REAL; [[ -r $ZDOTDIR/.zlogin ]] && source $ZDOTDIR/.zlogin' >> $d/.zlogin
}

# One start: _axle_su_run <out> <traced 0|1> <login 0|1> [bare]. Status 1 if it never reached
# a prompt (waiting for input, exec'd something else) within the time limit.
_axle_su_run() {
  local out=$1 traced=$2 login=$3 bare=$4 chunk
  zmodload zsh/zpty zsh/datetime zsh/zselect 2>/dev/null || return 2
  : > $out; rm -f -- $out.done $out.trace
  local dotdir=$_axle_su_dir/dot
  [[ -n $bare ]] && dotdir=$_axle_su_dir/bare
  local -a envs=(
    AXLE_SU_OUT=$out AXLE_SU_DOTDIR=$dotdir AXLE_SU_HOMEDIR=${ZDOTDIR:-$HOME}
    AXLE_SU_TRACE=${traced:#0} AXLE_SU_ZPROF=$_axle_su_zprof ZDOTDIR=$dotdir
    AXLE_PROFILING=1 DISABLE_AUTO_UPDATE=true DISABLE_UPDATE_PROMPT=true
  )
  local -a args=(-i); (( login )) && args+=(-l)
  [[ -n $bare ]] && args+=(-d)                       # (no /etc/zsh files: zsh by itself)
  print -r -- "mark spawn $EPOCHREALTIME" >> $out
  zpty axle_su "env ${(j: :)${(@q)envs}} ${(q)commands[zsh]:-zsh} ${(j: :)args}" 2>/dev/null || return 2
  local -i i limit=${_AXLE_SU_LIMIT_CS:-1500}
  for (( i = 0; i < limit; i += 2 )); do
    while zpty -rt axle_su chunk 2>/dev/null; do :; done
    [[ -e $out.done ]] && break
    zselect -t 2
  done
  zpty -d axle_su 2>/dev/null
  [[ -e $out.done ]]
}

# The bare shell's run: zsh with no startup files at all, to the first prompt.
_axle_su_write_bare() {
  local d=$1
  print -r -- 'setopt no_global_rcs' > $d/.zshenv
  cat > $d/.zshrc <<'EOF'
zmodload zsh/datetime
_axle_su_first_prompt() {
  print -r -- "mark prompt $EPOCHREALTIME" >> $AXLE_SU_OUT; print done > $AXLE_SU_OUT.done
  unset HISTFILE; exit 0
}
precmd_functions=(_axle_su_first_prompt)
EOF
}

# Read a run's results into the associative array named $2.
_axle_su_read() {
  local line kind name a b
  local -A _su_res
  _su_res[compinit_n]=0 _su_res[compinit_ms]=0
  for line in "${(@f)$(<$1)}"; do
    case $line in
      'mark '*)     _su_res[${${line#mark }%% *}]=${line##* } ;;
      'axleroot '*) typeset -g _axle_su_axleroot=${line#axleroot } ;;
      'compinit '*) a=${${line#compinit }% *} b=${line##* }
                    (( _su_res[compinit_n]++ )); _su_res[compinit_ms]=$(( _su_res[compinit_ms] + (b - a) * 1000 )) ;;
      'hook '*)     name=${${line#hook }% * *} a=${${line% *}##* } b=${line##* }
                    [[ -n $_su_res[hooks] ]] && _su_res[hooks]+=$'\x1f'
                    _su_res[hooks]+=$name$'\x1e'$(( (b - a) * 1000 )) ;;
    esac
  done
  : ${(PAA)2::="${(@kv)_su_res}"}
}

# Milliseconds between two marks of a run (REPLY), or empty.
_axle_su_span() {
  local _su_a=${${(P)${:-${1}[$2]}}} _su_b=${${(P)${:-${1}[$3]}}}
  [[ -n $_su_a && -n $_su_b ]] || { REPLY=''; return 1 }
  REPLY=$(( (_su_b - _su_a) * 1000 ))
}

# The traced run, summed: lines "F <ms> <file>" (self time per file) and
# "L <ms> <line> <text>" (inclusive time per line of ~/.zshrc).
_axle_su_trace_sum() {
  # (~/.zshrc as zsh sourced it, and with symlinks resolved: a home folder can be a link)
  local trace=$1 rc=$2 rc2=${2:A}
  command awk -F $'\x1f' -v rc="$rc" -v rc2="$rc2" '
    /^\+[0-9]+\.[0-9]+\x1f/ {
      t = substr($1, 2) + 0; file = $2; split($3, p, "> "); line = p[1]; text = substr($3, length(line) + 3)
      if (have) { gap = t - pt; fself[pfile] += gap; fn[pfile]++; total += gap; n++
                  if (cur != "") { lincl[cur] += gap; ln[cur]++ } }
      if (file == "BEGIN") { have = 1; pt = t; pfile = "(start)"; cur = ""; next }
      if (file == "END") { have = 0; next }
      # Code run by eval (file "(eval)") counts where eval was called; the line stays.
      if (file == "" || file ~ /^\(/) { pt = t; next }
      if (file == rc2) file = rc
      if (file == rc) {
        if (line != cur && !(line in seen)) {
          seen[line] = 1
          if (cur != "") { pre[line] = gap; prev[line] = cur; first[line] = text }
        }
        cur = line
      }
      pt = t; pfile = file
    }
    END {
      printf "T %.3f %d\n", total * 1000, n
      for (f in fself) printf "F %.3f %d %s\n", fself[f] * 1000, fn[f], f
      for (l in lincl) printf "L %.3f %d %s\n", lincl[l] * 1000, ln[l], l
      for (l in pre) { split(first[l], w, " "); printf "P %.3f %d %s %s\n", pre[l] * 1000, prev[l], l, w[1] }
    }' $trace
}

# A file's group, for the report (REPLY).
_axle_su_group() {
  local f=$1 omz=${ZSH:-$HOME/.oh-my-zsh} custom=${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}
  local rc=${ZDOTDIR:-$HOME}/.zshrc
  case $f in
    $AXLE_ROOT/*|${_axle_su_axleroot:-$AXLE_ROOT}/*) REPLY='Axle' ;;
    $custom/plugins/*|$omz/plugins/*)     REPLY="oh-my-zsh plugin ${${f#*/plugins/}%%/*}" ;;
    $custom/themes/*|$omz/themes/*)       REPLY="oh-my-zsh theme ${${f:t}%.zsh-theme}" ;;
    $omz/*|$custom/*)                     REPLY='oh-my-zsh' ;;
    */compinit|*/compaudit|*/compdump|*/compdef|*/compinstall|*/.zcompdump*) REPLY='compinit' ;;
    $rc|${rc:A})                          REPLY='~/.zshrc itself' ;;
    */nvm.sh|*/nvm/*|*/.nvm/*)            REPLY='nvm' ;;
    */conda*|*/miniconda*|*/anaconda*)    REPLY='conda' ;;
    /etc/*)                               REPLY="system file ${f}" ;;
    */functions/*|*/Functions/*)          REPLY="zsh function ${f:t}" ;;
    *)                                    REPLY=${f/#$HOME/~} ;;
  esac
}

_axle_su_ms() { REPLY=$(( int(rint($1)) )) }

# The report.
_axle_su_report() {
  zmodload zsh/mathfunc 2>/dev/null
  local runs=$1 all=$2 login=$3
  local m=${_axle_c[muted]:-244} a=${_axle_c[accent]:-magenta} w=${_axle_c[warn]:-yellow} b=${_axle_c[error]:-red}
  local d=$_axle_su_dir rcfile=${ZDOTDIR:-$HOME}/.zshrc
  local -a totals bares rcs
  local -A run first
  local i REPLY
  for i in {1..$runs}; do
    local -A r=(); _axle_su_read $d/run$i r
    _axle_su_span r spawn prompt && totals+=($REPLY)
    (( i == 1 )) && first=("${(@kv)r}")
  done
  for i in {1..3}; do
    local -A r=(); _axle_su_read $d/bare$i r
    _axle_su_span r spawn prompt && bares+=($REPLY)
  done
  bares=(${(n)bares})
  # The median run: its total, and its phases.
  local -a order=()
  for i in {1..$runs}; do
    local -A r=(); _axle_su_read $d/run$i r
    _axle_su_span r spawn prompt && order+=("${(l:12::0:)$(( int(REPLY * 1000) ))} $i")
  done
  order=(${(o)order})
  local mid=${${order[(( (${#order} + 1) / 2 ))]}##* }
  local -F total=$(( ${${order[(( (${#order} + 1) / 2 ))]%% *}##0#} / 1000.0 )) bare=${bares[2]:-${bares[1]:-0}}
  local -A r=(); _axle_su_read $d/run$mid r
  local -F envs=0 sys=0 rc=0 prof=0 login_ms=0 pre=0
  _axle_su_span r env-start env-end && envs=$REPLY
  _axle_su_span r rc-start rc-end && rc=$REPLY
  _axle_su_span r profile-start profile-end && prof=$REPLY
  _axle_su_span r precmd-start prompt && pre=$REPLY
  _axle_su_span r rc-end precmd-start && login_ms=$REPLY
  # zsh's own start (and /etc/zshenv) up to ours, plus the gaps between our files: /etc/zsh/*.
  local -F before=0 gap1=0 gap2=0
  _axle_su_span r spawn env-start && before=$REPLY
  if [[ -n $r[profile-start] ]]; then
    _axle_su_span r env-end profile-start && gap1=$REPLY
    _axle_su_span r profile-end rc-start && gap2=$REPLY
  else
    _axle_su_span r env-end rc-start && gap1=$REPLY
  fi
  sys=$(( before - bare + gap1 + gap2 )); (( sys < 0 )) && sys=0
  local -F yours=$(( total - bare ))
  print
  _axle_su_ms $total; local T=$REPLY; _axle_su_ms $bare; local B=$REPLY; _axle_su_ms $yours
  _axle_printp "  %BYour shell starts in $T ms%b %F{$m}(zsh by itself: $B ms; your setup: $REPLY ms; median of $runs)%f"
  print
  _axle_su_line() { _axle_su_ms $2; _axle_printp "  ${(r:34:)1//\%/%%} %F{${3:-$a}}${(l:5:)REPLY} ms%f${4:+  %F{$m\}${4//\%/%%}%f}" }
  _axle_su_line 'zsh by itself' $bare $m
  (( sys >= 1 )) && _axle_su_line 'system files (/etc/zsh)' $sys $m
  (( envs >= 1 )) && _axle_su_line '~/.zshenv' $envs
  (( prof >= 1 )) && _axle_su_line '~/.zprofile' $prof
  _axle_su_line '~/.zshrc' $rc
  (( login_ms >= 1 )) && _axle_su_line '~/.zlogin, history' $login_ms
  _axle_su_line 'before the first prompt' $pre '' "precmd hooks and the prompt"
  local h; local -a hooks=("${(@ps:\x1f:)r[hooks]}")
  local hn hm
  for h in $hooks; do
    [[ -n $h ]] || continue
    hn=${h%%$'\x1e'*} hm=${h#*$'\x1e'}
    (( hm >= 2 || all )) && _axle_su_line "    $hn" $hm $m
  done
  # Where ~/.zshrc's time goes (the traced run, scaled to the clean ~/.zshrc time).
  local -A groups=() lines=() ltext=()
  local -a rclines=("${(@f)$(<$rcfile)}" '')
  local -i ln
  for ln in {1..${#rclines}}; do ltext[$ln]=${${rclines[ln]##[[:space:]]#}[1,70]}; done
  local -F traced=0 scale=1   # (scale: kept at 1, the per-line correction replaces it)
  local kind ms rest g
  local -F perline=0
  if [[ -s $d/trace.out.trace ]]; then
    local line2 n
    local -a sum=("${(@f)$(_axle_su_trace_sum $d/trace.out.trace $rcfile)}")
    # Tracing slows every traced line by about the same: what the traced ~/.zshrc took
    # beyond the clean one, shared out per line, is taken back off each part.
    for line2 in $sum; do
      [[ $line2 == 'T '* ]] && { traced=${${line2#T }%% *}; n=${line2##* } }
    done
    (( n > 0 && traced > rc )) && perline=$(( (traced - rc) / n ))
    for line2 in $sum; do
      kind=${line2%% *}; rest=${line2#* }; ms=${rest%% *}; rest=${rest#* }; n=${rest%% *}; rest=${rest#* }
      [[ $kind == (T|P) ]] && continue
      ms=$(( ms - n * perline )); (( ms < 0 )) && ms=0
      if [[ $kind == F ]]; then
        [[ $rest == '(start)' || $rest == '(other)' || -z $rest ]] && continue
        _axle_su_group $rest; groups[$REPLY]=$(( ${groups[$REPLY]:-0} + ms ))
      else
        lines[$rest]=$ms
      fi
    done
    # zsh traces a line after expanding it, so the time a $(...) in it takes shows up
    # before it: give that time to the line with the $(...), not the one before.
    local -F gap; local pl
    # (Only when the line's first trace is the line itself: when it's the first command
    # inside its $(...), that command was traced before running, and is counted right.)
    local fw srcw
    for line2 in ${(M)sum:#P *}; do
      rest=${line2#P }; gap=${rest%% *}; rest=${rest#* }; pl=${rest%% *}; rest=${rest#* }
      fw=${rest#* }; rest=${rest%% *}
      [[ ${rclines[rest]} == *('$('|'`')* ]] || continue
      srcw=${${rclines[rest]##[[:space:]]#}%%[[:space:]]*}
      [[ $fw == $srcw ]] || continue
      lines[$rest]=$(( ${lines[$rest]:-0} + gap ))
      lines[$pl]=$(( ${lines[$pl]:-0} - gap )); (( lines[$pl] < 0 )) && lines[$pl]=0
    done
  fi
  if (( ${#groups} )); then
    print
    _axle_printp "  %BWhere ~/.zshrc's time goes%b %F{$m}(about: measured once more, with tracing)%f"
    local -a sorted=()
    for g ms in "${(@kv)groups}"; do sorted+=("${(l:12::0:)$(( int(ms * scale * 1000) ))}"$'\x1f'"$g"); done
    local -i shown=0
    for g in ${(On)sorted}; do
      ms=$(( ${${${g%%$'\x1f'*}##0#}:-0} / 1000.0 )); g=${g#*$'\x1f'}
      (( ms < 2 && ! all )) && continue
      (( ++shown > 10 && ! all )) && break
      _axle_su_line "  $g" $ms
    done
    # The costliest lines of ~/.zshrc.
    sorted=()
    for g ms in "${(@kv)lines}"; do sorted+=("${(l:12::0:)$(( int(ms * scale * 1000) ))}"$'\x1f'"$g"); done
    shown=0
    local -a top=()
    for g in ${(On)sorted}; do
      ms=$(( ${${${g%%$'\x1f'*}##0#}:-0} / 1000.0 )); g=${g#*$'\x1f'}
      (( ms < 3 && ! all )) && continue
      (( ++shown > 6 && ! all )) && break
      _axle_su_line "  line ${(r:4:)g} ${ltext[$g][1,24]}" $ms
      top+=("$g"$'\x1f'"$ms"$'\x1f'"$ltext[$g]")
    done
  fi
  # The slowest functions (zprof in the first run: time spent in each function itself).
  if [[ -s $d/run1.zprof ]]; then
    # (zprof prints the list, then a call graph: only the list; one line per name)
    local -a slow=("${(@f)$(command awk 'NR > 2 && /^$/ { exit }
      $1 ~ /^[0-9]+\)$/ { name = $9; for (i = 10; i <= NF; i++) name = name " " $i
        if (name !~ /^_axle_su_/) self[name] += $6 }
      END { for (n in self) if (self[n] >= 5) printf "%.1f %s\n", self[n], n }' $d/run1.zprof | sort -rn | head -6)}")
    if (( ${#slow} )) && [[ -n $slow[1] ]]; then
      print
      _axle_printp "  %BThe slowest functions%b %F{$m}(time in each one itself, at startup and the first prompt)%f"
      local fn owner
      for g in $slow; do
        fn=${g#* }
        case $fn in
          _axle_*|axle_*) owner=Axle ;; nvm*) owner=nvm ;; comp*|_comp*) owner=completion ;;
          _omz*|omz*) owner=oh-my-zsh ;; *nemc*) owner=nemc ;; *) owner='' ;;
        esac
        _axle_su_line "  $fn" ${g%% *} '' "$owner"
      done
    fi
  fi
  (( first[compinit_n] )) && {
    _axle_su_ms $first[compinit_ms]
    _axle_su_line "  compinit (${first[compinit_n]}×)" $first[compinit_ms]
  }
  _axle_su_fixes "${(@kv)groups}" -- "${(@)top}" -- $first[compinit_n] $first[compinit_ms] $scale
}

# Known causes and what to do about them, biggest first.
_axle_su_fixes() {
  local -A groups; local -a top
  while [[ $1 != -- ]]; do groups[$1]=$2; shift 2; done; shift
  while [[ $1 != -- ]]; do top+=("$1"); shift; done; shift
  local -i cn=$1; local -F cms=$2 scale=$3
  local m=${_axle_c[muted]:-244} a=${_axle_c[accent]:-magenta}
  local -a fixes=()      # "<ms><US><title><US><what to do>"
  local REPLY t ms text
  local -F g
  g=$(( ${groups[nvm]:-0} + ${groups[oh-my-zsh plugin nvm]:-0} )); g=$(( g * scale ))
  (( g >= 15 )) && fixes+=("$g"$'\x1f'"nvm loads node at every start"$'\x1f'"Load it when first used: with oh-my-zsh, zstyle ':omz:plugins:nvm' lazy yes (before oh-my-zsh.sh); otherwise source nvm.sh --no-use, or switch to fnm.")
  if (( cn >= 2 )); then
    fixes+=("$(( cms / cn * (cn - 1) ))"$'\x1f'"compinit runs $cn times"$'\x1f'"Once is enough. On Ubuntu, /etc/zsh/zshrc runs it before your setup does: add skip_global_compinit=1 to ~/.zshenv.")
  elif (( cms >= 25 )); then
    fixes+=("$(( cms / 2 ))"$'\x1f'"compinit checks every completion file at every start"$'\x1f'"Check once a day: autoload -Uz compinit; if [[ -n \${ZDOTDIR:-~}/.zcompdump(#qN.mh+24) ]]; then compinit; else compinit -C; fi")
  fi
  local x line
  for x in $top; do
    line=${x%%$'\x1f'*}; x=${x#*$'\x1f'}; ms=${x%%$'\x1f'*}; text=${x#*$'\x1f'}
    (( ms >= 10 )) || continue
    if [[ $text == *'$('* || $text == *'`'* ]]; then
      local prog=${${${text#*\$\(}#*\`}%%[ )\`]*}
      prog=${${prog#\'}%\'}; prog=${prog:t}
      fixes+=("$ms"$'\x1f'"~/.zshrc line $line runs ${prog:-a program} at every start"$'\x1f'"Its output rarely changes: save it once and source the file, e.g. ${prog:-cmd} ... > ~/.cache/${prog:-cmd}-init.zsh, then source ~/.cache/${prog:-cmd}-init.zsh (redo it after upgrading ${prog:-it}).")
    fi
  done
  (( ${groups[conda]:-0} * scale >= 15 )) && fixes+=("$(( groups[conda] * scale ))"$'\x1f'"conda initialises at every start"$'\x1f'"conda config --set auto_activate_base false skips activating base; or load conda in a function the first time you use it.")
  # WSL: Windows folders on PATH make every unknown command and completion search them.
  if [[ -n $WSL_DISTRO_NAME || -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    local -a win=(${(M)path:#/mnt/[a-z]/*})
    if (( ${#win} )); then
      local -F s=$EPOCHREALTIME
      whence -p axle-no-such-command-$$ >/dev/null 2>&1
      local -F lookup=$(( (EPOCHREALTIME - s) * 1000 ))
      _axle_su_ms $lookup
      fixes+=("$lookup"$'\x1f'"${#win} of your ${#path} PATH folders are on Windows drives"$'\x1d'"per lookup of a command that doesn't exist"$'\x1f'"Not only at startup: every typo, completion and syntax check pays it. In /etc/wsl.conf: [interop] appendWindowsPath = false, then wsl --shutdown; add back what you use (e.g. VS Code's bin folder) to PATH yourself.")
    fi
  fi
  # A long history is read before the first prompt.
  if [[ -r $HISTFILE ]]; then
    local -a hl=("${(@f)$(<$HISTFILE)}")
    if (( ${#hl} > 50000 )); then
      fixes+=("0"$'\x1f'"your history has ${#hl} lines, read at every start"$'\x1f'"HISTSIZE / SAVEHIST of 50000 keeps it quick; Axle's own history log keeps everything for axle stats and search.")
    fi
  fi
  print
  if (( ! ${#fixes} )); then
    _axle_printp "  %F{${_axle_c[ok]:-green}}✓%f Nothing known to slow it down."
    return 0
  fi
  _axle_printp "  %BFixes, biggest first%b %F{$m}(text to copy; Axle never edits your files)%f"
  local f; local -i n=0
  for f in ${(On)${fixes/(#b)([0-9.]##)/${(l:10::0:)${$(( int(${match[1]} * 100) ))}}}}; do
    local rest=${f#*$'\x1f'}
    local title=${rest%%$'\x1f'*} what=${rest#*$'\x1f'} per=''
    [[ $title == *$'\x1d'* ]] && { per=" ${title#*$'\x1d'}"; title=${title%%$'\x1d'*} }
    _axle_ms_of() { REPLY=$(( ${${1##0#}:-0} / 100.0 )) }
    _axle_ms_of ${f%%$'\x1f'*}; _axle_su_ms $REPLY
    print
    if (( REPLY >= 1 )); then
      _axle_printp "  %F{$a}$(( ++n )).%f ${title//\%/%%} %F{$m}(about $REPLY ms${per//\%/%%})%f"
    else
      _axle_printp "  %F{$a}$(( ++n )).%f ${title//\%/%%}"
    fi
    print -r -- "     $what" | fold -s -w $(( ${COLUMNS:-80} - 6 )) | sed '2,$s/^/     /'
  done
}

_axle_cmd_startup() {
  setopt localoptions extendedglob
  local -i runs=3 all=0 login=0
  [[ -o login ]] && login=1
  while (( $# )); do
    case $1 in
      --runs) runs=${2:-3}; shift ;;
      --all) all=1 ;;
      --login) login=1 ;;
      --no-login) login=0 ;;
      *) print -u2 "usage: axle doctor --startup [--runs N] [--all] [--login|--no-login]"; return 1 ;;
    esac
    shift
  done
  (( runs >= 1 && runs <= 20 )) || runs=3
  zmodload zsh/zpty 2>/dev/null || { print -u2 "axle: this zsh has no zpty module, which the measurement needs"; return 1 }
  _axle_su_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/axle-startup.XXXXXX") || return 1
  {
    mkdir -p $_axle_su_dir/dot $_axle_su_dir/bare
    _axle_su_write_dotdir $_axle_su_dir/dot
    _axle_su_write_bare $_axle_su_dir/bare
    local m=${_axle_c[muted]:-244} i
    _axle_printp "%B axle doctor --startup%b %F{$m}starting your shell ${runs}× (and plain zsh), then once more with tracing…%f"
    for i in {1..3}; do _axle_su_run $_axle_su_dir/bare$i 0 0 bare; done
    for i in {1..$runs}; do
      _axle_su_zprof=${${(M)i:#1}:+1}       # (the first run also times every function)
      if ! _axle_su_run $_axle_su_dir/run$i 0 $login; then
        _axle_su_stuck $_axle_su_dir/run$i; return 1
      fi
    done
    _axle_su_zprof=''
    _axle_su_run $_axle_su_dir/trace.out 1 $login
    _axle_su_report $runs $all $login
  } always {
    # (_AXLE_SU_KEEP: leave the measurements, for debugging)
    if [[ -n $_AXLE_SU_KEEP ]]; then print -u2 -r -- "kept: $_axle_su_dir"
    elif [[ -n $_axle_su_dir && -d $_axle_su_dir && $_axle_su_dir == */axle-startup.* ]]; then
      rm -rf -- $_axle_su_dir
    fi
    _axle_su_dir=''
  }
}

# The shell never reached a prompt: say where it stopped.
_axle_su_stuck() {
  local -A r=(); _axle_su_read $1 r
  local where='in ~/.zshenv'
  [[ -n $r[env-end] ]] && where='before ~/.zshrc (~/.zprofile or /etc/zsh)'
  [[ -n $r[rc-start] ]] && where='in ~/.zshrc'
  [[ -n $r[rc-end] ]] && where='after ~/.zshrc (~/.zlogin, or a precmd hook)'
  print -u2 -r -- "axle: your shell didn't reach a prompt within ${$(( ${_AXLE_SU_LIMIT_CS:-1500} / 100 ))} s: something $where waits for input or replaces the shell (exec tmux, a menu, a password prompt)."
}
