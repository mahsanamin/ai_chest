#!/bin/bash
# Git Worktree Helper Functions
# Source this file in your .zshrc or .bashrc for enhanced worktree management.
# Installed by AI Awareness aa-install-tools; the framework appends a guarded
# source line to your shell-rc automatically.
#
# Helpers (aa_g_worktree_init, aa_g_worktree_remove) are looked up under
# $AA_WORKTREE_DIR (default: $HOME/.claude/scripts/aa-worktree).

: "${AA_WORKTREE_DIR:=$HOME/.claude/scripts/aa-worktree}"

# Enhanced worktree init with auto-cd
aa_g_worktree_init() {
    local script_path="$AA_WORKTREE_DIR/aa_g_worktree_init"

    if [ ! -f "$script_path" ]; then
        echo "Error: aa_g_worktree_init script not found at $script_path"
        echo "Is AA_WORKTREE_DIR set correctly? Current: $AA_WORKTREE_DIR"
        return 1
    fi

    # Validate branch name before sourcing (source runs in current shell,
    # so an exit in the script would kill the terminal)
    if [ -z "$1" ] || [[ "$1" == -* ]]; then
        echo "Usage: aa_g_worktree_init <branch-name> [-b|--base <branch>]"
        echo "Example: aa_g_worktree_init feature/setup-local-data-seeds"
        return 1
    fi

    # Source the script to allow directory change
    source "$script_path" "$@"
}

# Enhanced worktree remove with auto-context switching
aa_g_worktree_remove() {
    local script_path="$AA_WORKTREE_DIR/aa_g_worktree_remove"

    if [ ! -f "$script_path" ]; then
        echo "Error: aa_g_worktree_remove script not found at $script_path"
        echo "Is AA_WORKTREE_DIR set correctly? Current: $AA_WORKTREE_DIR"
        return 1
    fi

    # Execute the script (it handles context switching internally)
    bash "$script_path" "$@"
}

# Create a worktree from a remote branch or PR — for reviewing teammate work.
# Companion script handles the heavy lifting; sourced so the auto-cd works.
aa_g_worktree_review() {
    local script_path="$AA_WORKTREE_DIR/aa_g_worktree_review"

    if [ ! -f "$script_path" ]; then
        echo "Error: aa_g_worktree_review script not found at $script_path"
        echo "Is AA_WORKTREE_DIR set correctly? Current: $AA_WORKTREE_DIR"
        return 1
    fi

    # Block stray flag args here BUT let -h/--help through so the script can
    # print its full help (the script supports -r/--remote and other flags
    # that the brief usage below doesn't cover). Matches upstream convention.
    if [ -z "$1" ] || { [[ "$1" == -* ]] && [[ "$1" != "-h" && "$1" != "--help" ]]; }; then
        echo "Usage: aa_g_worktree_review <pr-number | branch-name> [-r|--remote <remote>]"
        echo "Example: aa_g_worktree_review 356"
        echo "Example: aa_g_worktree_review feature/teammate-branch"
        echo "(Use 'aa_g_worktree_review -h' for full help.)"
        return 1
    fi

    source "$script_path" "$@"
}

# List all worktrees as a box-drawing table with status, ahead/behind, dirty/clean,
# and last-commit age. Column widths are auto-computed from the actual data so long
# branch names and paths don't shift the layout. Pure read-only — no fetches.
aa_g_worktree_list() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "Usage: aa_g_worktree_list"
        echo ""
        echo "Renders a box-drawing table of every worktree in the current repo:"
        echo "  WORKTREE     — directory name (main worktree marked with '(main)')"
        echo "  BRANCH       — checked-out branch (or '(detached)')"
        echo "  STATE        — clean / dirty / missing  (colored)"
        echo "  vs UPSTREAM  — ↑ahead ↓behind, or 'in sync', or 'no upstream'"
        echo "  LAST COMMIT  — human-friendly age of HEAD"
        echo ""
        echo "Below the table:"
        echo "  Paths   — name → full filesystem path (tilde-shortened under \$HOME)"
        echo "  Switch  — quick-action hints (aa_g_worktree_switch / aa_g_worktree_main)"
        echo ""
        echo "Read-only. No fetches, no network. Ahead/behind reflects the last"
        echo "'git fetch' — re-run fetch if you want fresh numbers."
        return 0
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    local YELLOW='\033[1;33m'
    local GREEN='\033[0;32m'
    local RED='\033[0;31m'
    local NC='\033[0m'

    # zsh prints "var=" to stdout for any bare `local var` (no =value) unless
    # TYPESET_SILENT is set. LOCAL_OPTIONS scopes the change to this function only.
    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local main_worktree=""
    # Use --porcelain + substr extraction so worktree paths containing spaces
    # survive (the default `git worktree list` output is space-separated, so
    # awk '{print $1}' would truncate "/Users/me/My Repos/foo" at "/Users/me/My").
    main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}' | head -n 1)

    # Collect rows into a single TAB-delimited array (one row per worktree).
    # Pure element iteration (no ${!ARR[@]}, no ${ARR[$i]}) works in both bash
    # and zsh. No ANSI codes in the data — colors are applied only at print time,
    # otherwise width calculations would include escape bytes and alignment breaks.
    local TAB=$'\t'
    local -a rows=()
    local current_path="" current_branch=""

    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            current_path="${line#worktree }"
        elif [[ "$line" == "branch "* ]]; then
            current_branch="${line#branch }"
            current_branch="${current_branch#refs/heads/}"
        elif [[ "$line" == "detached"* ]]; then
            current_branch="(detached)"
        elif [[ -z "$line" && -n "$current_path" ]]; then
            # WORKTREE column: basename, plus "(main)" prefix for the main worktree.
            # Showing basename instead of the full path keeps the table readable;
            # the full path is rarely useful when scanning.
            local display_name=""
            if [ "$current_path" = "$main_worktree" ]; then
                display_name="(main) $(basename "$current_path")"
            else
                display_name="$(basename "$current_path")"
            fi

            local state="clean" upstream_info="-" last_commit="-"

            if [ ! -d "$current_path" ]; then
                state="missing"
            else
                if [ -n "$(git -C "$current_path" status --porcelain 2>/dev/null)" ]; then
                    state="dirty"
                fi
                if [ "$current_branch" != "(detached)" ]; then
                    local upstream=""
                    upstream=$(git -C "$current_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
                    if [ -n "$upstream" ]; then
                        local counts="" behind="" ahead=""
                        counts=$(git -C "$current_path" rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)
                        if [ -n "$counts" ]; then
                            behind=$(echo "$counts" | awk '{print $1}')
                            ahead=$(echo "$counts" | awk '{print $2}')
                            if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
                                upstream_info="in sync"
                            else
                                upstream_info="↑${ahead} ↓${behind}"
                            fi
                        fi
                    else
                        upstream_info="no upstream"
                    fi
                fi
                last_commit=$(git -C "$current_path" log -1 --format='%cr' 2>/dev/null)
                [ -z "$last_commit" ] && last_commit="-"
            fi

            # Pack the 6 fields into one TAB-delimited row. Pure element iteration
            # (below) avoids the bash-only ${!ARR[@]} and works in both bash and zsh.
            # TAB is safe — git refuses TABs in branch/path names.
            # 6th field (current_path) is shown in the "Paths" section below the table,
            # not in the table itself (keeps the table scannable on narrow terminals).
            rows+=("${display_name}${TAB}${current_branch}${TAB}${state}${TAB}${upstream_info}${TAB}${last_commit}${TAB}${current_path}")
            current_path=""; current_branch=""
        fi
    done < <(git worktree list --porcelain; echo)

    if [ "${#rows[@]}" -eq 0 ]; then
        echo "No worktrees found."
        return 0
    fi

    # Auto-size each column: max of header width and longest cell value.
    # ${#var} returns Unicode character count under a UTF-8 locale, so ↑ and ↓
    # count as one display column each — alignment stays correct.
    local h1="WORKTREE" h2="BRANCH" h3="STATE" h4="vs UPSTREAM" h5="LAST COMMIT"
    local w1=${#h1} w2=${#h2} w3=${#h3} w4=${#h4} w5=${#h5}
    local row="" name="" branch="" state_col="" upstream="" last_commit="" full_path="" rest=""
    for row in "${rows[@]}"; do
        name="${row%%${TAB}*}";        rest="${row#*${TAB}}"
        branch="${rest%%${TAB}*}";     rest="${rest#*${TAB}}"
        state_col="${rest%%${TAB}*}";  rest="${rest#*${TAB}}"
        upstream="${rest%%${TAB}*}";   rest="${rest#*${TAB}}"
        last_commit="${rest%%${TAB}*}"; rest="${rest#*${TAB}}"
        full_path="$rest"
        (( ${#name} > w1 ))        && w1=${#name}
        (( ${#branch} > w2 ))      && w2=${#branch}
        (( ${#state_col} > w3 ))   && w3=${#state_col}
        (( ${#upstream} > w4 ))    && w4=${#upstream}
        (( ${#last_commit} > w5 )) && w5=${#last_commit}
    done

    # Pre-build dash runs (one per column) so the three border lines can reuse them
    local d1 d2 d3 d4 d5
    d1=$(printf '%*s' "$w1" '' | tr ' ' '─')
    d2=$(printf '%*s' "$w2" '' | tr ' ' '─')
    d3=$(printf '%*s' "$w3" '' | tr ' ' '─')
    d4=$(printf '%*s' "$w4" '' | tr ' ' '─')
    d5=$(printf '%*s' "$w5" '' | tr ' ' '─')

    printf '┌─%s─┬─%s─┬─%s─┬─%s─┬─%s─┐\n' "$d1" "$d2" "$d3" "$d4" "$d5"
    printf '│ %-*s │ %-*s │ %-*s │ %-*s │ %-*s │\n' "$w1" "$h1" "$w2" "$h2" "$w3" "$h3" "$w4" "$h4" "$w5" "$h5"
    printf '├─%s─┼─%s─┼─%s─┼─%s─┼─%s─┤\n' "$d1" "$d2" "$d3" "$d4" "$d5"

    for row in "${rows[@]}"; do
        name="${row%%${TAB}*}";        rest="${row#*${TAB}}"
        branch="${rest%%${TAB}*}";     rest="${rest#*${TAB}}"
        state_col="${rest%%${TAB}*}";  rest="${rest#*${TAB}}"
        upstream="${rest%%${TAB}*}";   rest="${rest#*${TAB}}"
        last_commit="${rest%%${TAB}*}"; rest="${rest#*${TAB}}"
        full_path="$rest"
        local state_color="$NC"
        case "$state_col" in
            clean)   state_color="$GREEN" ;;
            dirty)   state_color="$YELLOW" ;;
            missing) state_color="$RED" ;;
        esac
        printf '│ %-*s │ %-*s │ '"$state_color"'%-*s'"$NC"' │ %-*s │ %-*s │\n' \
            "$w1" "$name" \
            "$w2" "$branch" \
            "$w3" "$state_col" \
            "$w4" "$upstream" \
            "$w5" "$last_commit"
    done

    printf '└─%s─┴─%s─┴─%s─┴─%s─┴─%s─┘\n' "$d1" "$d2" "$d3" "$d4" "$d5"

    # Paths section — name → full filesystem path. Useful when you need to
    # `cd` somewhere manually or share a path with a teammate. Tilde-shorten
    # under $HOME so home-rooted paths stay compact.
    echo ""
    echo "Paths:"
    local home_prefix="${HOME%/}"
    for row in "${rows[@]}"; do
        name="${row%%${TAB}*}";       rest="${row#*${TAB}}"
        branch="${rest%%${TAB}*}";    rest="${rest#*${TAB}}"
        state_col="${rest%%${TAB}*}"; rest="${rest#*${TAB}}"
        upstream="${rest%%${TAB}*}";  rest="${rest#*${TAB}}"
        last_commit="${rest%%${TAB}*}"; rest="${rest#*${TAB}}"
        full_path="$rest"
        # Replace leading $HOME with ~ for display
        case "$full_path" in
            "$home_prefix"|"$home_prefix"/*) full_path="~${full_path#$home_prefix}" ;;
        esac
        printf "  %-*s  %s\n" "$w1" "$name" "$full_path"
    done

    # Quick-action hints. Keeps users from having to remember the helper names.
    echo ""
    echo "Switch:"
    echo "  aa_g_worktree_switch <name>   # cd to a worktree by name (e.g. 'feature-PROJ-532-...')"
    echo "  aa_g_worktree_main            # cd back to the main repo"
}

# Quick switch to a worktree by feature name
aa_g_worktree_switch() {
    if [ -z "$1" ]; then
        echo "Usage: aa_g_worktree_switch <feature-name>"
        echo "Example: aa_g_worktree_switch my-feature"
        return 1
    fi

    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local feature_name="$1"
    local git_root="" main_worktree="" project_name="" worktree_path=""

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Use --porcelain + substr extraction so worktree paths containing spaces
    # survive (the default `git worktree list` output is space-separated, so
    # awk '{print $1}' would truncate "/Users/me/My Repos/foo" at "/Users/me/My").
    main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}' | head -n 1)
    project_name=$(basename "$main_worktree")
    worktree_path="$(dirname "$main_worktree")/WorkTrees/$project_name/$feature_name"

    # Try exact name first, then slash-to-dash conversion
    if [ ! -d "$worktree_path" ]; then
        local worktree_dir_name="${feature_name//\//-}"
        worktree_path="$(dirname "$main_worktree")/WorkTrees/$project_name/$worktree_dir_name"
    fi

    if [ -d "$worktree_path" ]; then
        cd "$worktree_path" || return 1
        echo "Switched to worktree: $feature_name"
    else
        echo "Error: Worktree not found"
        echo ""
        echo "Available worktrees:"
        aa_g_worktree_list
        return 1
    fi
}

# Conclude a merged worktree (alias to remove --verify)
aa_g_worktree_conclude() {
    aa_g_worktree_remove --verify "$@"
}

# Update current branch with latest main (fetch + rebase)
aa_g_worktree_update() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local main_branch="" current_branch="" has_changes=""

    # Determine main branch
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    else
        echo "Error: Neither 'main' nor 'master' branch found"
        return 1
    fi

    current_branch=$(git branch --show-current)

    if [ "$current_branch" = "$main_branch" ]; then
        echo "Already on $main_branch, just pulling..."
        git pull origin "$main_branch"
        return $?
    fi

    echo "Current branch: $current_branch"
    echo "Rebasing onto: $main_branch"
    echo ""

    # Check for uncommitted changes
    has_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        has_changes=true
        echo "Stashing uncommitted changes..."
        git stash push -m "aa_g_worktree_update: auto-stash before rebase"
    fi

    # Fetch and rebase
    echo "Fetching origin/$main_branch..."
    git fetch origin "$main_branch"

    echo "Rebasing..."
    if git rebase "origin/$main_branch"; then
        echo ""
        echo "Successfully rebased onto $main_branch"
    else
        echo ""
        echo "Rebase conflicts detected!"
        echo ""
        echo "Options:"
        echo "  1. Resolve conflicts, then: git rebase --continue"
        echo "  2. Abort rebase: git rebase --abort"
        if [ "$has_changes" = true ]; then
            echo ""
            echo "Note: Your uncommitted changes are stashed. Run 'git stash pop' after resolving."
        fi
        return 1
    fi

    # Restore stashed changes
    if [ "$has_changes" = true ]; then
        echo "Restoring stashed changes..."
        if git stash pop; then
            echo "Stashed changes restored"
        else
            echo "Conflict restoring stashed changes. Run 'git stash show' to see them."
        fi
    fi
}

# Note: framework freshness nudge now lives in scripts/aa-freshness/check.sh
# (sourced separately by the shell-rc block via manifest.json's `sourced` install
# type). That version is throttled to once per 24h and detects more states
# (pulled-but-not-installed, new global skills), so the inline check that used
# to live here would have been redundant noise.

# Return to main repository from any worktree
aa_g_worktree_main() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local main_worktree=""
    # Use --porcelain + substr extraction so worktree paths containing spaces
    # survive (the default `git worktree list` output is space-separated, so
    # awk '{print $1}' would truncate "/Users/me/My Repos/foo" at "/Users/me/My").
    main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}' | head -n 1)

    cd "$main_worktree" || return 1
    echo "Switched to main repository"
}

# Worktree health report: stale registrations, dirty trees, merged branches,
# branches with no upstream. Read-only; only reports, never acts.
aa_g_worktree_doctor() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "Usage: aa_g_worktree_doctor"
        echo ""
        echo "Read-only health audit. Flags four conditions:"
        echo "  • Stale registrations — git worktree list paths missing on disk (fix: aa_g_worktree_prune)"
        echo "  • Dirty trees         — uncommitted changes (removing would lose work)"
        echo "  • Merged branches     — already merged into main/master (fix: aa_g_worktree_conclude <name>)"
        echo "  • No upstream         — branch was never pushed (probably experimental local)"
        echo ""
        echo "Never modifies anything."
        return 0
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local main_branch=""
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    fi

    echo "Worktree health report"
    echo "──────────────────────"
    echo ""

    local issues=0

    # 1. Stale registrations
    local prune_out=""
    prune_out=$(git worktree prune --dry-run --verbose 2>&1)
    if [ -n "$prune_out" ]; then
        echo "⚠ Registered worktrees with missing directories:"
        echo "$prune_out" | sed 's/^/    /'
        echo "  Fix: aa_g_worktree_prune"
        echo ""
        issues=$((issues + 1))
    fi

    # Walk worktrees once, collecting buckets
    local -a dirty=() merged=() no_upstream=()
    local wt_path="" wt_branch=""
    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            wt_path="${line#worktree }"
            wt_branch=""
        elif [[ "$line" == "branch "* ]]; then
            wt_branch="${line#branch }"
            wt_branch="${wt_branch#refs/heads/}"
        elif [[ -z "$line" && -n "$wt_path" ]]; then
            if [ -d "$wt_path" ]; then
                if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
                    dirty+=("$wt_path [${wt_branch:-detached}]")
                fi
                if [ -n "$wt_branch" ] && [ "$wt_branch" != "$main_branch" ]; then
                    if [ -n "$main_branch" ] && git merge-base --is-ancestor "$wt_branch" "$main_branch" 2>/dev/null; then
                        merged+=("$wt_path [$wt_branch]")
                    fi
                    if ! git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
                        no_upstream+=("$wt_path [$wt_branch]")
                    fi
                fi
            fi
            wt_path=""
            wt_branch=""
        fi
    done < <(git worktree list --porcelain; echo)

    if [ ${#dirty[@]} -gt 0 ]; then
        echo "⚠ Dirty worktrees (uncommitted changes):"
        printf '    %s\n' "${dirty[@]}"
        echo ""
        issues=$((issues + 1))
    fi

    if [ ${#merged[@]} -gt 0 ]; then
        echo "ℹ Branches fully merged into $main_branch (safe to remove):"
        printf '    %s\n' "${merged[@]}"
        echo "  Fix: aa_g_worktree_conclude <name>"
        echo ""
        issues=$((issues + 1))
    fi

    if [ ${#no_upstream[@]} -gt 0 ]; then
        echo "ℹ Branches with no upstream (not pushed yet):"
        printf '    %s\n' "${no_upstream[@]}"
        echo ""
        issues=$((issues + 1))
    fi

    if [ $issues -eq 0 ]; then
        echo "✓ All worktrees healthy"
    else
        echo "Found $issues issue group(s) above."
    fi
}

# Prune stale worktree registrations + orphan directories under WorkTrees/.
# Two passes:
#   1. Stale registrations  — git tracks paths that no longer exist on disk
#   2. Orphan directories   — dirs exist under WorkTrees/{project}/ that git
#                             doesn't track (e.g., from a manual rm of the .git
#                             worktree linkfile, or a partially-failed init)
# Shows both lists, single Y/N confirmation, then prunes + removes orphans.
aa_g_worktree_prune() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "Usage: aa_g_worktree_prune"
        echo ""
        echo "Prunes stale worktree state in two passes, with one Y/N confirmation:"
        echo "  1. Registrations  — git worktree list paths that don't exist on disk"
        echo "  2. Orphans        — directories under WorkTrees/{project}/ that git doesn't track"
        echo ""
        echo "Both passes are dry-run by default. You see what would be removed before"
        echo "anything is touched. Run 'aa_g_worktree_doctor' first to inspect without"
        echo "any chance of a prompt firing."
        return 0
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    [ -n "${ZSH_VERSION:-}" ] && setopt LOCAL_OPTIONS TYPESET_SILENT

    local main_worktree="" project_name="" worktrees_root=""
    # Use --porcelain + substr extraction so worktree paths containing spaces
    # survive (the default `git worktree list` output is space-separated, so
    # awk '{print $1}' would truncate "/Users/me/My Repos/foo" at "/Users/me/My").
    main_worktree=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}' | head -n 1)
    project_name=$(basename "$main_worktree")
    worktrees_root="$(dirname "$main_worktree")/WorkTrees/$project_name"

    local dry=""
    dry=$(git worktree prune --dry-run --verbose 2>&1)
    echo "Stale worktree registrations (dir missing but git still tracks them):"
    if [ -z "$dry" ]; then
        echo "  (none)"
    else
        echo "$dry" | sed 's/^/  /'
    fi
    echo ""

    local -a orphans=()
    local registered_paths="" clean=""
    if [ -d "$worktrees_root" ]; then
        registered_paths=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}')
        for dir in "$worktrees_root"/*/; do
            [ -d "$dir" ] || continue
            clean="${dir%/}"
            if ! printf '%s\n' "$registered_paths" | grep -qxF "$clean"; then
                orphans+=("$clean")
            fi
        done
    fi

    echo "Orphan directories in $worktrees_root (not registered as worktrees):"
    if [ ${#orphans[@]} -eq 0 ]; then
        echo "  (none)"
    else
        printf '  %s\n' "${orphans[@]}"
    fi
    echo ""

    if [ -z "$dry" ] && [ ${#orphans[@]} -eq 0 ]; then
        echo "Nothing to prune."
        return 0
    fi

    printf "Run 'git worktree prune' and remove orphan dirs? [y/N] "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy] ]]; then
        echo "Cancelled."
        return 0
    fi

    git worktree prune --verbose
    for o in "${orphans[@]}"; do
        rm -rf "$o" && echo "Removed orphan: $o"
    done
    echo "Done."
}
