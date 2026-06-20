# aa-worktree

Git worktree helper functions, installed globally by `aa-install-tools` and auto-sourced into the developer's shell-rc.

## What's bundled here

Four files, derived from [github.com/mahsanamin/my_setup](https://github.com/mahsanamin/my_setup/tree/main/workflows/terminal_setup):

| File in this directory | Upstream source | Role |
|---|---|---|
| `worktree.sh` | `sourced/worktree.sh` (adapted — see "Adaptations" below) | Wrapper sourced into your shell. Defines `aa_g_worktree_init / _remove / _review / _list / _switch / _conclude / _update / _main / _doctor / _prune`. |
| `aa_g_worktree_init` | `scripts/a_g_worktree_init` (renamed) | Companion helper, sourced by the wrapper. Creates a new worktree with auto-cd. |
| `aa_g_worktree_remove` | `scripts/a_g_worktree_remove` (renamed) | Companion helper, bash-executed by the wrapper. Removes a worktree with merge verification + protected-branches safeguard. |
| `aa_g_worktree_review` | `scripts/a_g_worktree_review` (renamed) | Companion helper, sourced by the wrapper. Creates a worktree from a remote branch or PR number for code review. |

## Commands at a glance

| Command | Purpose |
|---|---|
| `aa_g_worktree_init <branch>` | Start a new worktree for your own work. Picks a base from main/current/story/* via picker. |
| `aa_g_worktree_review <pr-or-branch>` | Create a `review-*` worktree from a teammate's branch or a PR number (resolves via `gh`). |
| `aa_g_worktree_remove <name>` | Remove a worktree by directory OR branch name. Verifies merge state when `--verify`. |
| `aa_g_worktree_conclude <name>` | Alias for `_remove --verify` — refuses to remove if branch isn't merged. |
| `aa_g_worktree_list` | List worktrees with branch, clean/dirty state, and ahead/behind vs upstream. |
| `aa_g_worktree_switch <name>` | `cd` to a worktree by feature name (or slash-to-dash form). |
| `aa_g_worktree_main` | `cd` back to the main repository from any worktree. |
| `aa_g_worktree_update` | Fetch + rebase current branch onto origin/main (auto-stash uncommitted work). |
| `aa_g_worktree_doctor` | Health check. Flags orphans, merged worktrees, dirty trees, branches with no upstream. Read-only. |
| `aa_g_worktree_prune` | Wrap `git worktree prune` with a dry-run preview and confirmation prompt. |

## Adaptations from upstream

Two intentional changes from the original:

1. **Function names use `aa_g_` prefix (not `a_g_`).** This lets the framework's copy coexist with a developer's manual install of the upstream repo without any function-name collision. A developer with both installs has `a_g_worktree_init` (their manual upstream install) and `aa_g_worktree_init` (the framework's copy) defined side by side — both work, no shadowing, no detection logic required.
2. **Companion-helper lookup uses `${AA_WORKTREE_DIR:-$HOME/.claude/scripts/aa-worktree}`** instead of the upstream's `$MY_WORKFLOW_DIR`. This lets the bundle work at the framework's default install location without depending on the upstream env var.

Everything else is byte-equivalent to the upstream snapshot at the time of bundling.

## What is NOT bundled

The upstream `terminal_setup/` repo has additional helpers the framework deliberately does not ship:

- `sourced/git.sh`, `sourced/doctor.sh`, `sourced/process.sh`
- `scripts/a_g_branch_cleanup`, `scripts/a_g_branch_delete`, `scripts/a_c_mcp_add`, `scripts/a_time_range.sh`, `scripts/a_uninstall_app.sh`

These are not shipped because (a) the worktree subset is what most workflows benefit from, and (b) the rest of the upstream repo is a personal-setup collection that may conflict with project-level policies.

If you want the rest, install the upstream repo manually alongside this — they don't conflict (see "Coexistence" below).

## Self-containedness

The three bundled files have no source/exec dependencies on anything outside this directory. Audit: `grep source` in any of them returns only the wrapper's own `source "$AA_WORKTREE_DIR/aa_g_worktree_init"`. Safe to install without the rest of the upstream repo.

## Coexistence with a manual upstream install

The `aa_g_` rename means no conflict. If you already source the upstream `terminal_setup/sourced/worktree.sh` from your shell-rc:

- Your `a_g_worktree_init` etc. continue to work, served by your manual install.
- The framework's `aa_g_worktree_init` etc. become available alongside, served by `~/.claude/scripts/aa-worktree/worktree.sh`.
- Both installs are independent. Removing one does not affect the other.

If you want to invoke the framework version explicitly: type `aa_g_worktree_init <branch>`. If you want the upstream version: type `a_g_worktree_init <branch>`. They behave the same; only the name distinguishes which install is responding.

## Upstream attribution

These scripts are authored by Ahsan Amin and maintained at [github.com/mahsanamin/my_setup](https://github.com/mahsanamin/my_setup). The framework's bundled copies are kept in sync manually — see the `scripts/manifest.json` entry for the current snapshot version.
