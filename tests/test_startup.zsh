# `axle doctor --startup`, and the prompt's program lookups (_axle_which).

# A setup with known costs: a slow "nvm", a slow $(...) line, compinit twice.
_slow_setup() {
  mkdir -p $HOME/.nvm
  print -r -- 'zmodload zsh/zselect; zselect -t 15; nvm() { :; }' > $HOME/.nvm/nvm.sh
  cat > $HOME/.zshrc <<'EOF'
export NVM_DIR=$HOME/.nvm
source $NVM_DIR/nvm.sh
eval "$(sleep 0.08; echo 'x=1')"
autoload -Uz compinit; compinit -u -d $HOME/.zcompdump
compinit -u -d $HOME/.zcompdump
PS1='%~ %# '
EOF
}

test_startup_names_the_costs() {
  load_tool
  _slow_setup
  print -l 'ls' 'cd /tmp' > $HOME/.zsh_history; HISTFILE=$HOME/.zsh_history
  local before=$(<$HOME/.zsh_history)
  local -a left=(${${TMPDIR:-/tmp}%/}/axle-startup.*(N))
  local out=$(COLUMNS=100 axle doctor --startup --no-login --runs 2 2>&1); plain "$out"; out=$REPLY
  assert_match "$out" "*Your shell starts in [0-9]## ms*" "a total"
  assert_contains "$out" "~/.zshrc" "its parts"
  assert_contains "$out" "nvm loads node at every start (about" "nvm named"
  assert_match "$out" "*compinit runs [23] times*" "compinit twice"
  assert_match "$out" "*line 3*eval*" "the slow line, with its number"
  assert_match "$out" "*~/.zshrc line 3 runs sleep at every start*" "and what it runs"
  # The biggest fix first: nvm (150 ms) before the line (80 ms).
  [[ ${out[(i)nvm loads node]} -lt ${out[(i)line 3 runs sleep]} ]] || fail "biggest first: $out"
  assert_eq "$(<$HOME/.zsh_history)" "$before" "history not written"
  local -a after=(${${TMPDIR:-/tmp}%/}/axle-startup.*(N))
  assert_eq ${#after} ${#left} "nothing left behind"
}

test_startup_stops_a_shell_that_waits() {
  load_tool
  print -r -- 'zmodload zsh/zselect; zselect -t 3000   # (hangs, as a prompt for input would)' > $HOME/.zshrc
  local out
  out=$(_AXLE_SU_LIMIT_CS=200 axle doctor --startup --no-login --runs 1 2>&1) && fail "fails"
  assert_contains "$out" "didn't reach a prompt" "says so"
  assert_contains "$out" "in ~/.zshrc" "and where"
}

test_which_finds_and_remembers() {
  load_theme
  mkdir -p $T/bin1 $T/bin2
  print '#!/bin/sh' > $T/bin2/tool-xyz; chmod +x $T/bin2/tool-xyz
  path=($T/bin1 $T/bin2 $path)
  _axle_which tool-xyz || fail "found"
  assert_eq "$_axle_found" "$T/bin2/tool-xyz" "its path"
  REPLY=keep; _axle_which tool-xyz; assert_eq "$REPLY" keep "REPLY left alone (segments use it)"
  print '#!/bin/sh' > $T/bin1/tool-xyz; chmod +x $T/bin1/tool-xyz
  _axle_which tool-xyz; assert_eq "$_axle_found" "$T/bin2/tool-xyz" "remembered"
  path=($path /nonexistent)
  _axle_which tool-xyz; assert_eq "$_axle_found" "$T/bin1/tool-xyz" "PATH changed: looked up again"
  _axle_which no-such-tool-xyz && fail "not found"
  print '#!/bin/sh' > $T/bin1/no-such-tool-xyz; chmod +x $T/bin1/no-such-tool-xyz
  _axle_which no-such-tool-xyz && fail "'not found' is remembered for a while"
  _axle_which_at[no-such-tool-xyz]=$(( EPOCHSECONDS - 61 ))      # (a minute later)
  _axle_which no-such-tool-xyz || fail "then looked up again"
  [[ -d $T/bin1 ]] && mkdir $T/bin1/dir-xyz && { _axle_which dir-xyz && fail "a folder isn't a program" }
  return 0
}

# compinit's "insecure directories" question (a folder others can write to, on fpath) would
# wait forever in the measured shell: it's measured without stopping to ask.
test_startup_with_insecure_completion_folders() {
  load_tool
  mkdir -p $HOME/insecure; chmod 777 $HOME/insecure
  print -r -- 'fpath=($HOME/insecure $fpath); autoload -Uz compinit; compinit -d $HOME/.zcompdump; PS1="> "' > $HOME/.zshrc
  local out
  out=$(_AXLE_SU_LIMIT_CS=1000 axle doctor --startup --no-login --runs 1 2>&1) || fail "measured: $out"
  plain "$out"; assert_match "$REPLY" "*Your shell starts in [0-9]## ms*" "it finished"
}
