# cc-sessions

A terminal UI for browsing, resuming, and managing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions across all your projects.

![Built with Textual](https://img.shields.io/badge/TUI-Textual-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

Claude Code scatters session history across every project directory you've ever worked in. `cc-sessions` gives you one place to find, preview, and jump back into any of them.

## Features

- **Unified view**: All sessions grouped by project directory, across your whole machine, each showing the title Claude Code generated for it
- **Resume from anywhere**: Pick a session and `cd` into its working dir + resume automatically
- **Preview pane**: See where you left off (last prompt and reply), files recently edited, and how the session started
- **On-demand summaries**: Press `c` to generate a context summary for one session with Haiku, saved for next time
- **Search / filter**: Find sessions by message content, directory, or custom name
- **Rename, archive, delete**: Tidy up old sessions (individually or in bulk)
- **Vi keybindings**: `h/j/k/l`, `g/G`, `ctrl-u/d`
- **Command palette**: `ctrl-p` for everything
- **Sort modes**: recency, size, or folder name
- **Themes**: All Textual themes supported
- **Skip-permissions toggle**: Resume sessions with `--dangerously-skip-permissions` when you want

## Requirements

- Python 3.9+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and in your `PATH`
- Supported shells: fish, bash, or zsh

## Install

```bash
git clone https://github.com/liatrio-labs/cc-sessions.git
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
- Press `Enter` on a session to **resume it**, or click it once to preview and again to resume (cc-sessions will `cd` to the session's original working directory and run `claude --resume <id>`)
- Press `/` to search. The search bar stays visible while a filter is active, and the status bar shows how many matched. Press `esc` to clear it
- Press `s` to cycle sort modes, `n` to name a session
- Press `ctrl-p` for the full command palette

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Resume selected session |
| Click | First click previews, second click resumes |
| `/` | Search / filter |
| `Esc` | Clear an active filter (or quit) |
| `s` | Cycle sort mode (recency / size / name) |
| `n` | Rename session |
| `c` | Summarize session (Haiku) |
| `?` | Glyph legend and title precedence |
| `a` | Archive session |
| `x` | Delete session |
| `Space` | Multi-select |
| `Shift+A` | Archive all selected |
| `Shift+X` | Delete all selected |
| `e` | Expand all groups |
| `Shift+E` | Collapse all groups |
| `h/j/k/l` | Vi navigation |
| `g` / `G` | Jump to top / bottom |
| `Ctrl-U/D` (or `Ctrl-B/F`) | Page up / down |
| `Ctrl-P` | Command palette |
| `q` / `Esc` | Quit |

## Demo mode

```bash
cc-sessions --demo
```

Runs against a throwaway set of fictional sessions in a temp directory instead of `~/.claude/projects`, so you can record or present the tool without showing your own work. The header reads **DEMO DATA**.

Nothing is mocked. Demo mode only repoints the paths, so search, sort, rename, archive, delete, the preview and `c` all run their real code paths against real (fake) session files. Archive and delete only touch the temp copies, and demo renames and summaries go to a temp config dir rather than your own. `Enter` reports the session it would resume instead of resuming, since the directories are fictional.

The fixture covers every label source, folder grouping, a session with a saved summary, sessions with no title, and a range of sizes and ages.

## Config

Preferences live in `~/.config/cc-sessions/`:

- `prefs.json` - theme, skip-permissions toggle
- `session-names.json` - your custom session names
- `summaries.json` - summaries generated with `c`

Archived sessions are moved to `~/.claude/archived-sessions/`.

Session names set via Claude's `/rename` command are read from the session file itself. Local names in `session-names.json` take priority when both exist.

Row labels use the first available of these, and a glyph tells you which one you're looking at. Press `?` in the app for this legend.

| Glyph | Source |
|-------|--------|
| pencil | The name you set, or a `/rename` from inside Claude Code |
| magic wand | A summary you generated with `c` |
| lightbulb | The title Claude Code generated on its own |
| empty circle *(dimmed italic)* | No title yet; showing your last prompt, last message, or the session id |

A dimmed italic row means Claude Code never generated a title for that session, so you're reading raw transcript text rather than a summary. Press `c` to generate one.

The preview carries the same glyph on its heading, and when something other than Claude's title won the row it also shows Claude's own title underneath in italics.

A summary you generate outranks Claude's own title until Claude writes a new one, which happens when you resume the session.

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

Issues and PRs welcome. No formal build or release automation yet; just run `./install.sh` locally to try your changes.

Tests cover extraction, sanitizing, and label precedence:

```bash
~/.local/share/cc-sessions-venv/bin/pip install -r requirements-dev.txt
~/.local/share/cc-sessions-venv/bin/pytest tests/
```

## License

[MIT](LICENSE)
