# cc-sessions

A terminal UI for browsing and managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions across all projects.

![Built with Textual](https://img.shields.io/badge/TUI-Textual-blue)

## Features

- Tree view of all sessions grouped by working directory
- Sort by recency, size, or folder name
- Search/filter sessions
- Preview first message and metadata
- Rename, archive, or delete sessions
- Resume sessions directly (with optional `--dangerously-skip-permissions`)
- Vi keybindings (h/j/k/l, g/G, ctrl-u/d)
- Command palette (ctrl-p)
- Theme support (via Textual)

## Requirements

- Python 3.10+
- Claude Code CLI installed

## Install

```bash
git clone <this-repo> cc-sessions
cd cc-sessions
./install.sh
```

The install script:
1. Creates a Python venv at `~/.local/share/cc-sessions-venv`
2. Installs the `textual` dependency
3. Copies the TUI to `~/.local/bin/cc-sessions-tui`
4. Detects your shell(s) and installs the appropriate wrapper:
   - **fish**: drops a function into `~/.config/fish/functions/`
   - **bash**: copies wrapper to `~/.local/bin/` and sources it from `~/.bashrc`
   - **zsh**: copies wrapper to `~/.local/bin/` and sources it from `~/.zshrc`

Restart your shell (or `source` your rc file), then run:

```bash
cc-sessions
```

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Resume selected session |
| `/` | Search/filter |
| `s` | Cycle sort mode |
| `n` | Rename session |
| `a` | Archive session |
| `x` | Delete session |
| `Space` | Multi-select |
| `Shift+A` | Archive all selected |
| `Shift+X` | Delete all selected |
| `e` | Expand all groups |
| `Shift+E` | Collapse all groups |
| `h/j/k/l` | Vi navigation |
| `g / G` | Jump to top/bottom |
| `Ctrl-U/D` | Page up/down |
| `Ctrl-P` | Command palette |
| `q / Esc` | Quit |

## Config

Preferences are stored in `~/.config/cc-sessions/`:
- `prefs.json` - theme, skip-permissions toggle
- `session-names.json` - custom session names

## Uninstall

```bash
rm ~/.local/bin/cc-sessions-tui
rm ~/.local/bin/cc-sessions.sh
rm ~/.config/fish/functions/cc-sessions.fish
rm -rf ~/.local/share/cc-sessions-venv
rm -rf ~/.config/cc-sessions
```

Remove the `source` line from `~/.bashrc` and/or `~/.zshrc` if present.
