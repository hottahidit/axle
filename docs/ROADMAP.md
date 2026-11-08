# Roadmap: v0.3.1 → v0.4.0

Two themes, in order:

- **v0.3.2 – v0.3.5 · Know your shell**: insight from what Axle already records, and from
  your own `~/.zshrc`. Built on `main`, one tagged release per step.
- **v0.3.6 – v0.4.0 · Find anything**: fuzzy search everywhere (Tab, files, folders,
  history, projects), finished as v0.4.0.

Everything is built on `main`, one tagged release per step: each step stands on its own and
leaves the build working, even when it adds pieces a later step uses.

The rules that held for `axle run` hold here: plain zsh, nothing new to install, loading
stays ≈ 3 ms (new code is lazy-loaded), nothing from a repository or a file runs unseen,
every step tested on Linux and macOS before it's tagged.

---

## Part 1 · Know your shell (v0.3.2 – v0.3.5)

(v0.3.1 went to `fix` asking before a mistyped command runs; the steps below moved up one,
with the finishing work folded into v0.3.5.)

### v0.3.2 · Why is my shell slow? (`axle doctor --startup`) · done

A bare interactive zsh takes about 250 ms to start on this machine before any plugin loads.
Most people never find out where their startup time goes. This measures it.

```
$ axle doctor --startup
  Your shell starts in 612 ms (zsh itself: 248 ms, your setup: 364 ms)

  oh-my-zsh                         141 ms
    plugins/nvm                      96 ms   ← loads node at startup; lazy-load it
    compinit                         31 ms   ← runs a full check every time; once a day is enough
  ~/.zshrc line 42  eval "$(pyenv init -)"   58 ms   ← a subprocess every start
  conda initialize                   52 ms
  Axle                                3 ms
  PATH: 46 folders, 31 on Windows drives (WSL)  ← slows every unknown command

  Fixes, biggest first: ...
```

- Runs your real setup in a separate zsh (in a pty, so it's interactive), with a timer
  around every file sourced and every line of `~/.zshrc`; your files aren't changed.
- Finds the usual suspects by name: nvm, pyenv/rbenv `init`, conda, `compinit` without
  `-C`, uncompiled files, `$(...)` subprocesses, oh-my-zsh update checks, slow PATH entries
  (WSL's Windows folders; the `appendWindowsPath=false` setting).
- Each finding comes with the fix as text to copy; Axle never edits `~/.zshrc`.
- Total time to the first prompt is measured against a bare `zsh -i` for the baseline.
- **Done when:** on prepared sample setups (nvm, pyenv, oh-my-zsh with plugins, conda) it
  names the top cost correctly, and the totals match a stopwatch measurement within 10%.

### v0.3.3 · Alias reminders (`hints` module)

- After a command that an existing alias would have covered, one quiet line:
  `hint: you have an alias for that: gst` (shell aliases, global aliases, git aliases).
  At most once per alias per day; off with `AXLE_HINTS=0`.
- `axle alias suggest`: long commands you type often, with a proposed short name
  (avoiding names already taken: commands, functions, aliases), picked with checkboxes and
  saved to Axle's config as plain `alias` lines.
- **Done when:** a hint appears for an alias-able command and never for the alias itself,
  a git alias, or a command run through `sudo`/`time`; suggestions never shadow a command.

### v0.3.4 · Command not found → how to get it

- When a command doesn't exist: if it's a typo of one you have, `fix` already handles it;
  otherwise say what provides it and put the install command on the line (Esc Esc):
  `ripgrep provides rg: sudo apt install ripgrep`.
- Sources, fastest first: Debian/Ubuntu's command-not-found database (read directly, not
  through its Python script, which takes ~100 ms), `pacman -F`, `dnf provides`, Homebrew,
  and a small built-in list of common tools installed with pip / npm / cargo / go.
- Chains to an existing `command_not_found_handler` (oh-my-zsh's plugin, distro defaults)
  instead of replacing it silently.
- **Done when:** answers in under 30 ms from the database; installs nothing itself.

### v0.3.5 · Your week, and Know your shell finished

- `axle stats --week`: time spent per project (from the history log: commands and the gaps
  between them), most-run and slowest commands, what failed most, compared with the week
  before ("npm test: 42 s on average, up from 18 s").
- Once a week, one line before the prompt: `Last week: 1,240 commands, most time in shop
  (11 h); npm test got 2× slower. axle stats --week`. **Off by default**
  (`AXLE_WEEKLY=1` turns it on), and offered as its own question in `axle configure`, so it's
  never hidden.
- `axle stats --project [name]`: one project's history.
- **Done when:** numbers match a hand count on a fixture history; the weekly line shows once.

Finishing (in the same release):
- Wizard: `hints`, the command-not-found handler and the weekly line, each its own visible
  choice (the weekly line shown as off, ready to switch on).
- `axle help`, Tab completion, `axle config` entries, README section, CHANGELOG.
- Security review: everything that reads `~/.zshrc`, history, or package databases.
- Startup still ≈ 3 ms; all tests green on Linux and macOS.

---

## Part 2 · Find anything (v0.3.6 – v0.4.0)

Fuzzy search, the reason people install fzf and zsh4humans, in plain zsh.

### v0.3.6 · The fuzzy engine
- One matcher shared by everything below: letters in order, bonuses for word starts,
  consecutive runs and path ends, smart case; matches highlighted.
- Speed budget: 5,000 candidates filtered in under 15 ms per keystroke; beyond that, it
  narrows incrementally from the previous result.
- Uses `fzf` instead when it's installed and `AXLE_FUZZY=fzf` (or `auto`).

### v0.3.7 · Tab completion as a fuzzy menu
- Tab shows zsh's own completions (so every command's completion works) in a filterable
  menu with their descriptions and groups; one candidate: completed directly, as now.
- Steps aside when fzf-tab is loaded.

### v0.3.8 · Files, folders, history
- **Ctrl-T**: pick files into the line (in a git repo: tracked and untracked-not-ignored
  files; elsewhere: a bounded walk skipping `node_modules`, `.git`, venvs).
- **Alt-C**: go to a folder: frecent ones from `j` first, then subfolders.
- **Ctrl-R**: a fuzzy mode for the existing picker.
- Keys configurable; doesn't take over keys fzf's own bindings already use without asking.

### v0.3.9 · Pickers for Axle itself
- `j -i` (or `ji`): choose among frecent folders.
- `axle run` with several recent projects: a fuzzy picker.
- `axle` alone in a terminal: a palette of commands and settings.

### v0.4.0 · Previews, and Find anything finished
- A preview pane for files (`bat` if installed, else plain text), folders (their contents)
  and history entries (where and when they ran).

- Wizard module `find`, docs, help, completion, settings, CHANGELOG; security review
  (file names with control characters shown safely, every inserted path quoted);
  startup ≈ 3 ms; green on Linux and macOS.

---

## Versions

All on `main` (worktree `~/repos/axle-main`), commits `vX.Y.Z - Title`, each tagged and pushed
when asked; no branch:

| Version | Step |
|---|---|
| v0.3.1 | *(done)* Typo correction: `fix` asks before a mistyped command runs |
| v0.3.2 | *(done)* Startup profiler (`axle doctor --startup`) |
| v0.3.3 | Alias reminders |
| v0.3.4 | Command not found |
| v0.3.5 | Your week; Know your shell finished |
| v0.3.6 | Fuzzy engine |
| v0.3.7 | Fuzzy Tab completion |
| v0.3.8 | Files, folders, history |
| v0.3.9 | Pickers for Axle |
| v0.4.0 | Previews; Find anything finished |

A fix needed in between takes the next number, and the plan moves along.

Decided: the profiler is `axle doctor --startup`; the weekly line is off by default and asked
about in `axle configure`; no separate branch.

## Future ideas (not scheduled)

- **Keys you keep.** Axle changes what some standard keys do (Ctrl-R, ↑/↓ with text typed,
  Ctrl-N/Ctrl-P with a suggestion list, → / End with a suggestion), which can fight muscle
  memory. Ideas: a "Keys" step in `axle configure` showing each key's current job and Axle's,
  each kept or given to Axle; a setting for every binding (`''` = leave the key alone); never
  take a key that you or another plugin (fzf) already bound without asking; `axle keys` to
  list Axle's bindings and what each key did before (from the saved `axle-orig-*` keymaps).
- From the `axle run` merge: a checked-in `.axle-run` project file + `axle run set --export`;
  mise tasks; npm workspaces as parts; start order between parts; stable ports per project;
  `axle run share` (cloudflared / ngrok); "Run it?" before stopping another service on a
  port clash.
