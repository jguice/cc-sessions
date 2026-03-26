#!/bin/bash
# cc-sessions - Browse and manage Claude Code sessions across all projects
# Works in bash and zsh.

cc-sessions() {
    local venv_dir="$HOME/.local/share/cc-sessions-venv"
    local output
    output=$("$venv_dir/bin/python3" "$HOME/.local/bin/cc-sessions-tui")

    # Output format: RESUME\tcwd\tsession_id\tskip_perms
    if [ -n "$output" ]; then
        local action cwd sid skip_perms
        action=$(echo "$output" | cut -f1)
        cwd=$(echo "$output" | cut -f2)
        sid=$(echo "$output" | cut -f3)
        skip_perms=$(echo "$output" | cut -f4)

        if [ "$action" = "RESUME" ]; then
            echo "Resuming session in $cwd..."
            cd "$cwd" || return 1
            if [ "$skip_perms" = "1" ]; then
                claude --resume "$sid" --dangerously-skip-permissions
            else
                claude --resume "$sid"
            fi
        fi
    fi
}
