#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$HOME/.local/share/cc-sessions-venv"
BIN_DIR="$HOME/.local/bin"

echo "Installing cc-sessions..."

# Create virtual environment and install textual
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "Installing dependencies..."
"$VENV_DIR/bin/pip" install -q textual

# Install TUI binary with correct shebang
PYTHON_PATH="$VENV_DIR/bin/python3"
mkdir -p "$BIN_DIR"
sed "1s|#!.*|#!${PYTHON_PATH}|" "$SCRIPT_DIR/cc-sessions-tui" > "$BIN_DIR/cc-sessions-tui"
chmod +x "$BIN_DIR/cc-sessions-tui"

# Detect shell and install appropriate wrapper
INSTALLED_SHELLS=""

# Fish
if command -v fish >/dev/null 2>&1; then
    FISH_FUNCTIONS="$HOME/.config/fish/functions"
    mkdir -p "$FISH_FUNCTIONS"
    cp "$SCRIPT_DIR/cc-sessions.fish" "$FISH_FUNCTIONS/cc-sessions.fish"
    INSTALLED_SHELLS="$INSTALLED_SHELLS  fish: $FISH_FUNCTIONS/cc-sessions.fish\n"
fi

# Bash
BASHRC="$HOME/.bashrc"
BASH_SOURCE_LINE="source \"$BIN_DIR/cc-sessions.sh\""
if [ -n "$BASH_VERSION" ] || [ -f "$BASHRC" ]; then
    cp "$SCRIPT_DIR/cc-sessions.sh" "$BIN_DIR/cc-sessions.sh"
    if [ -f "$BASHRC" ] && ! grep -qF "cc-sessions.sh" "$BASHRC"; then
        echo "" >> "$BASHRC"
        echo "# cc-sessions: Claude Code session browser" >> "$BASHRC"
        echo "$BASH_SOURCE_LINE" >> "$BASHRC"
    fi
    INSTALLED_SHELLS="$INSTALLED_SHELLS  bash: source $BIN_DIR/cc-sessions.sh (added to ~/.bashrc)\n"
fi

# Zsh
ZSHRC="$HOME/.zshrc"
ZSH_SOURCE_LINE="source \"$BIN_DIR/cc-sessions.sh\""
if [ -n "$ZSH_VERSION" ] || [ -f "$ZSHRC" ]; then
    cp "$SCRIPT_DIR/cc-sessions.sh" "$BIN_DIR/cc-sessions.sh"
    if [ -f "$ZSHRC" ] && ! grep -qF "cc-sessions.sh" "$ZSHRC"; then
        echo "" >> "$ZSHRC"
        echo "# cc-sessions: Claude Code session browser" >> "$ZSHRC"
        echo "$ZSH_SOURCE_LINE" >> "$ZSHRC"
    fi
    INSTALLED_SHELLS="$INSTALLED_SHELLS  zsh: source $BIN_DIR/cc-sessions.sh (added to ~/.zshrc)\n"
fi

# Migrate config from old name if present
OLD_CONFIG="$HOME/.config/claude-sessions"
NEW_CONFIG="$HOME/.config/cc-sessions"
if [ -d "$OLD_CONFIG" ] && [ ! -d "$NEW_CONFIG" ]; then
    echo "Migrating config from $OLD_CONFIG to $NEW_CONFIG..."
    mv "$OLD_CONFIG" "$NEW_CONFIG"
fi

echo ""
echo "Installed:"
echo "  $BIN_DIR/cc-sessions-tui"
printf "$INSTALLED_SHELLS"
echo ""
echo "Run 'cc-sessions' to start."
echo "(You may need to restart your shell or source your rc file first.)"
