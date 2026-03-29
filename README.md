# AI Chest

A growing collection of AI tools, prompts, and workflows for productivity, learning, and software development.

## What's Inside

### General Prompts

#### Easy Understanding (`General_Prompts/I_am_Dumb/`)
Transform complex topics into simple, digestible explanations with real-world examples and analogies. Perfect for learning new technologies or concepts quickly.

### Software Engineering

#### AI Tech Lead Agent Creator (`SoftwareEngineering/Coding_Agent_Creator/`)
Create intelligent AI coding assistants that learn your project — architecture, conventions, patterns, and past mistakes. Works with Claude Code, Cursor, or any AI assistant with file access.

#### Task Flow (`SoftwareEngineering/Task_Flow/`)
Complete structured development workflow for [Claude Code](https://claude.ai/code): raw task to merged PR in 5 phases. Includes session recovery, parallel background agents, safety rails, and multi-tracker support (Jira, GitHub, Linear).

#### AI Rule Templates (`SoftwareEngineering/AIRuleTemplates/`)
Reusable coding rule templates for AI-assisted development. Stack-agnostic — covers universal rules, backend, Java/Spring Boot, React/TypeScript, and Next.js. Works with Claude Code, Cursor, GitHub Copilot, and Windsurf.

## Repository Structure

```
ai_chest/
├── General_Prompts/
│   └── I_am_Dumb/
│       └── easy_understanding.md
│
└── SoftwareEngineering/
    ├── Coding_Agent_Creator/
    │   ├── agent_creator.md
    │   └── README.md
    │
    ├── Task_Flow/
    │   ├── skills/
    │   ├── agents/
    │   ├── templates/
    │   └── README.md
    │
    └── AIRuleTemplates/
        ├── universal/
        ├── backend/
        ├── java-spring-boot/
        ├── react-typescript/
        ├── nextjs/
        └── README.md
```

## Quick Start

- **Learn something**: Copy `General_Prompts/I_am_Dumb/easy_understanding.md` into any AI chat
- **Create a coding agent**: See [Coding Agent Creator README](SoftwareEngineering/Coding_Agent_Creator/README.md)
- **Set up Task Flow**: See [Task Flow README](SoftwareEngineering/Task_Flow/README.md)
- **Add AI coding rules**: See [AI Rule Templates README](SoftwareEngineering/AIRuleTemplates/README.md)

## Who This Is For

- **Developers** wanting AI assistants that understand their projects
- **Learners** needing complex topics explained simply
- **Teams** standardizing AI-assisted development workflows

## Contributing

Contributions welcome — new tools, improved prompts, better docs, real-world examples.

## License

Open source. Use, modify, and share freely.

## Tags

`ai-tools` `ai-workflow` `productivity` `software-development` `learning` `automation` `coding-assistant` `task-management`
