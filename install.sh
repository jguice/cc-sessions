#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$HOME/.local/share/claude-sessions-venv"
BIN_DIR="$HOME/.local/bin"
FISH_FUNCTIONS="$HOME/.config/fish/functions"

echo "Installing claude-sessions..."

# Create virtual environment and install textual
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "Installing dependencies..."
"$VENV_DIR/bin/pip" install -q textual

# Update shebang to point to the venv python
PYTHON_PATH="$VENV_DIR/bin/python3"
sed "1s|#!.*|#!${PYTHON_PATH}|" "$SCRIPT_DIR/claude-sessions-tui" > "$BIN_DIR/claude-sessions-tui"
chmod +x "$BIN_DIR/claude-sessions-tui"

# Install fish function
mkdir -p "$FISH_FUNCTIONS"
# Update the python path in the fish function too
sed "s|~/.local/share/claude-sessions-venv/bin/python3|${PYTHON_PATH}|g" \
    "$SCRIPT_DIR/claude-sessions.fish" > "$FISH_FUNCTIONS/claude-sessions.fish"

echo ""
echo "Installed:"
echo "  $BIN_DIR/claude-sessions-tui"
echo "  $FISH_FUNCTIONS/claude-sessions.fish"
echo ""
echo "Run 'claude-sessions' to start."
