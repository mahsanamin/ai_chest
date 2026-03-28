---
name: task-flow-remember
description: Use when Claude forgets context or hallucinates during the same session. Re-reads task-flow skill and task files to get back on track. Say "task-flow-remember" or "remember".
disable-model-invocation: true
---

# Task Flow Remember

Quick context recovery when Claude loses track during the same session.

## When to Use

**Use this skill when:**
- Claude forgets what task you're working on
- Claude hallucinates wrong phase or incorrect information
- Claude suggests actions that don't match the execution plan
- You need quick re-orientation in the same session

**Use task-flow-resume instead when:**
- You closed Claude and opened a new session
- You need full task state restoration

## How It Works

**Trigger:** User says "task-flow-remember" or "remember"

### Steps:

1. **Re-read task-flow skill first:**
   - Read `.claude/skills/task-flow/SKILL.md` to refresh on the workflow
   - Understand the phases and what each phase does

2. **Get task folder path:**
   - Check conversation for recent mentions of task folder
   - If not found, ask: "What's your current task folder path?"

3. **Read task files in priority order:**
   - `execution-summary.md` (MUST read - source of truth for current state)
   - `execution_plan.md` (SHOULD read - shows what we're building)
   - `prompt-understanding.md` (only if needed for clarity)

4. **Check git branch:**
   ```bash
   git branch --show-current
   ```

5. **Present brief summary:**
   ```
   ✅ Back on track.

   Task: {task folder name}
   Phase: {from execution-summary}
   Branch: {current branch}
   Last Action: {from execution-summary}
   Next: {from execution-summary or infer from phase}

   Ready to continue. What would you like me to do?
   ```

6. **Wait for user direction**

## Key Points

- ⚡ **Be fast** - Read only essential files (2-3 max)
- 📖 **Trust execution-summary.md** - It's the source of truth
- 🎯 **Don't explore codebase** - Just read task files
- 💬 **Be brief** - Short summary, not full execution plan
- ✅ **Correct mistakes** - If execution-summary shows you were wrong, accept it

## Related Skills

- **task-flow** - Start a NEW task
- **task-flow-resume** - Resume after closing Claude (new session)
- **task-flow-remember** - Quick refresh in same session
