function claude-sessions --description "Browse and manage Claude Code sessions across all projects"
    # Run the TUI app and capture its output
    set -l output (~/.local/share/claude-sessions-venv/bin/python3 ~/.local/bin/claude-sessions-tui)

    # If user selected a session to resume, the app outputs: RESUME\tcwd\tsession_id
    if test -n "$output"
        set -l parts (string split \t $output)
        if test "$parts[1]" = "RESUME"
            set -l cwd $parts[2]
            set -l sid $parts[3]
            echo "Resuming session in $cwd..."
            cd $cwd
            claude --resume $sid
        end
    end
end
