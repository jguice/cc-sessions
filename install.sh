#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$HOME/.local/share/cc-sessions-venv"
BIN_DIR="$HOME/.local/bin"
FISH_FUNCTIONS="$HOME/.config/fish/functions"

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

# Install fish function
mkdir -p "$FISH_FUNCTIONS"
cp "$SCRIPT_DIR/cc-sessions.fish" "$FISH_FUNCTIONS/cc-sessions.fish"

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
echo "  $FISH_FUNCTIONS/cc-sessions.fish"
echo ""
echo "Run 'cc-sessions' to start."
