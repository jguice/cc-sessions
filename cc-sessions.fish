function cc-sessions --description "Browse and manage Claude Code sessions across all projects"
    # Run the TUI app and capture its output
    set -l venv_dir "$HOME/.local/share/cc-sessions-venv"
    set -l output ($venv_dir/bin/python3 ~/.local/bin/cc-sessions-tui)

    # Output format: RESUME\tcwd\tsession_id\tskip_perms
    if test -n "$output"
        set -l parts (string split \t $output)
        if test "$parts[1]" = "RESUME"
            set -l cwd $parts[2]
            set -l sid $parts[3]
            set -l skip_perms $parts[4]
            echo "Resuming session in $cwd..."
            cd $cwd
            if test "$skip_perms" = "1"
                claude --resume $sid --dangerously-skip-permissions
            else
                claude --resume $sid
            end
        end
    end
end
