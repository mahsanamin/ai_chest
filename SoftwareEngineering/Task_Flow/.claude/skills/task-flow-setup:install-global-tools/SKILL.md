---
name: task-flow-setup:install-global-tools
description: Install or update Task Flow global tools (ai-optimizer, review-pr) to ~/.claude/skills/. Independent of any target project. Say "task-flow-setup:install-global-tools" or "install global tools".
disable-model-invocation: true
---

# Install Global Tools

Install Task Flow global tools to `~/.claude/skills/` so they are available across all projects. This is independent of any target project setup.

## When to Use

- First-time setup — user wants global tools before (or without) initializing any project
- After a framework update — to sync global tools to the latest version
- When global tools are missing or broken in `~/.claude/skills/`

## Prerequisites

- Working directory: Task Flow framework repo (this repo)

## Process

Run the installer script from the framework root:

```bash
bash {FRAMEWORK_PATH}/install-global-tools.sh
```

The script will:
1. Discover all `task-flow-tool:*` skills in the framework
2. Compare each against what's already in `~/.claude/skills/`
3. Install new tools and update changed ones
4. Skip tools that are already up to date
5. Report what was installed/updated

If the script is not available or the user prefers manual installation, fall back to copying each tool directly:

```bash
mkdir -p ~/.claude/skills/task-flow-tool:{name}
cp {FRAMEWORK_PATH}/skills/task-flow-tool:{name}/SKILL.md ~/.claude/skills/task-flow-tool:{name}/SKILL.md
```
