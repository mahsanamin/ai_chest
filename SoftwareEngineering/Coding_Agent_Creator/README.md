# AI Tech Lead Agent Creator

Create a smart AI Tech Lead agent that learns your project and provides expert guidance.

## Quick Start

1. **Clone this repository**
   ```bash
   git clone <repository-url>
   cd my_docs/Prompts/CodePrompts
   ```

2. **Open your project in Claude Code (or any AI chat)**
   ```
   cd /path/to/your/project
   ```

3. **Create your agent**
   ```
   Read this prompt /Volumes/Work/Personal/repos/my_docs/Prompts/CodePrompts/agent_creator.md and create me an agent with name ProjectMaster
   ```
   
   Replace `ProjectMaster` with whatever name suits your project.

## What You Get

Your AI agent will:
- **Learn your entire codebase** - architecture, patterns, conventions
- **Remember project decisions** - no more re-explaining context
- **Guide development** - suggest implementations, review code
- **Manage tasks** - create execution plans with progress tracking
- **Prevent mistakes** - learn from past errors and warn you
- **Stay updated** - continuously learn from new code and decisions

## Project Status

When creating your agent, you'll be asked:
- **Production** - Live project with users (creates feature branches)
- **Bootstrap** - Development/prototyping phase (simple task queue)

## Agent Files Created

```
.YourAgent/
  YourAgent.md              # Main agent brain
  ProjectContext.md         # What the project does
  ProjectArchitecture.md    # Technical details & patterns
  HowToRunProject.md        # Setup and run instructions
  HowToCode.md             # Team coding conventions
  Donts.md                 # Things to avoid
  OngoingLearning.md       # New discoveries
```

## Usage Examples

After creation, try:
- "Explain the payment processing architecture"
- "Help me implement user authentication"  
- "Review this code for our conventions"
- "Create a plan for adding notifications"

## Requirements

- Claude Code, Cursor, or any AI assistant that can read files
- Access to your project directory
- 5 minutes for initial setup

## Updating Existing Agents

When `agent_creator.md` is improved, update your existing agents:

**In-place update** (recommended):
```bash
cd /path/to/your/project/with/existing/agent
```
```
Read this updated prompt [path-to]/agent_creator.md and update my existing [AgentName] agent with the new improvements
```

**Cross-context update** (for minor changes):
```
Read [path-to]/agent_creator.md and /path/to/project/.AgentName/ directory. Update the agent with improvements while preserving customizations.
```

Replace `[path-to]` with your actual path to the agent creator prompt.

---

*Your AI Tech Lead will analyze your project, learn your patterns, and become your intelligent development partner.*