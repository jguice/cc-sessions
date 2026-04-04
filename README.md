# cc-sessions

A terminal UI for browsing, resuming, and managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions across all your projects.

![Built with Textual](https://img.shields.io/badge/TUI-Textual-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

Claude Code scatters session history across every project directory you've ever worked in. `cc-sessions` gives you one place to find, preview, and jump back into any of them.

## Features

- **Unified view**: All sessions grouped by project directory, across your whole machine
- **Resume from anywhere**: Pick a session and `cd` into its working dir + resume automatically
- **Preview pane**: See the first user message, session size, and metadata before resuming
- **Search / filter**: Find sessions by message content, directory, or custom name
- **Rename, archive, delete**: Tidy up old sessions (individually or in bulk)
- **Vi keybindings**: `h/j/k/l`, `g/G`, `ctrl-u/d`
- **Command palette**: `ctrl-p` for everything
- **Sort modes**: recency, size, or folder name
- **Themes**: All Textual themes supported
- **Skip-permissions toggle**: Resume sessions with `--dangerously-skip-permissions` when you want

## Requirements

- Python 3.10+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and in your `PATH`
- Supported shells: fish, bash, or zsh

## Install

```bash
git clone https://github.com/jguice/cc-sessions.git
cd cc-sessions
./install.sh
```

The install script:

1. Creates a Python venv at `~/.local/share/cc-sessions-venv`
2. Installs the `textual` dependency into it
3. Copies the TUI to `~/.local/bin/cc-sessions-tui`
4. Detects your shell and installs a wrapper function:
   - **fish**: function in `~/.config/fish/functions/cc-sessions.fish`
   - **bash**: wrapper in `~/.local/bin/cc-sessions.sh`, sourced from `~/.bashrc`
   - **zsh**: wrapper in `~/.local/bin/cc-sessions.sh`, sourced from `~/.zshrc`

Restart your shell (or `source` your rc file), then:

```bash
cc-sessions
```

## Usage

Run `cc-sessions` from any terminal. You'll get a tree view of every Claude Code session on your machine, grouped by working directory.

- Navigate with arrows or `h/j/k/l`
- Press `Enter` on a session to **resume it** (cc-sessions will `cd` to the session's original working directory and run `claude --resume <id>`)
- Press `/` to search, `s` to cycle sort modes, `n` to name a session
- Press `ctrl-p` for the full command palette

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Resume selected session |
| `/` | Search / filter |
| `s` | Cycle sort mode (recency / size / name) |
| `n` | Rename session |
| `a` | Archive session |
| `x` | Delete session |
| `Space` | Multi-select |
| `Shift+A` | Archive all selected |
| `Shift+X` | Delete all selected |
| `e` | Expand all groups |
| `Shift+E` | Collapse all groups |
| `h/j/k/l` | Vi navigation |
| `g` / `G` | Jump to top / bottom |
| `Ctrl-U/D` | Page up / down |
| `Ctrl-P` | Command palette |
| `q` / `Esc` | Quit |

## Config

Preferences live in `~/.config/cc-sessions/`:

- `prefs.json` - theme, skip-permissions toggle
- `session-names.json` - your custom session names

Archived sessions are moved to `~/.claude/archived-sessions/`.

Session names set via Claude's `/rename` command are auto-detected from `~/.claude/history.jsonl`. Local names in `session-names.json` take priority when both exist.

## Uninstall

```bash
rm ~/.local/bin/cc-sessions-tui
rm ~/.local/bin/cc-sessions.sh
rm ~/.config/fish/functions/cc-sessions.fish
rm -rf ~/.local/share/cc-sessions-venv
rm -rf ~/.config/cc-sessions
```

Remove the `source` line from `~/.bashrc` and/or `~/.zshrc` if present.

## Contributing

Issues and PRs welcome. No formal build, tests, or release automation yet; just run `./install.sh` locally to try your changes.

## License

[MIT](LICENSE)
