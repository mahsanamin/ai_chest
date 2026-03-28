# AI Prompts Collection

Collection of simple AI prompts designed to enhance productivity, learning, and software development workflows.

## 🎯 What This Repository Contains

This repository houses specialized AI prompts organized by domain and use case. Each prompt is crafted to maximize AI assistant effectiveness for specific tasks and scenarios.

## 📁 Repository Structure

```
AI_PROMPTS/
├── General_Prompts/
│   └── I_am_Dumb/
│       └── easy_understanding.md    # Simplify complex topics
│
└── SoftwareEngineering/
    ├── Coding_Agent_Creator/
    │   ├── agent_creator.md         # Create intelligent coding assistants
    │   └── README.md               # Agent creator documentation
    │
    └── Task_Flow/
        ├── skills/                  # 7 workflow skills for Claude Code
        ├── agents/                  # 6 background agents (review, test, docs)
        ├── templates/               # Commit and PR templates
        └── README.md               # Full documentation
```

## 🧠 Available Prompts

### General Prompts

#### Easy Understanding (`General_Prompts/I_am_Dumb/`)
**Purpose**: Transform complex topics into simple, digestible explanations
- Breaks down complex ideas into accessible language
- Uses real-world examples and analogies
- Structured learning approach with validation
- Perfect for learning new technologies or concepts

**Use Case**: When you need to understand something complicated quickly and thoroughly.

### Software Engineering Prompts

#### AI Tech Lead Agent Creator (`SoftwareEngineering/Coding_Agent_Creator/`)
**Purpose**: Create intelligent AI coding assistants that learn your project
- Analyzes your codebase architecture and patterns
- Learns coding conventions from your team's PRs
- Provides intelligent code guidance and reviews
- Manages development tasks with detailed execution plans
- Prevents common mistakes through learned patterns

**Features**:
- 🏗️ **Architecture Analysis**: Deep understanding of your tech stack and patterns
- 📝 **Convention Learning**: Extracts coding standards from actual code
- 🎯 **Task Management**: Production vs Bootstrap modes for different project stages
- 🛡️ **Mistake Prevention**: Builds a knowledge base of what not to do
- 🔄 **Continuous Learning**: Updates knowledge as your project evolves

**Use Case**: When you want an AI assistant that truly understands your specific project and can provide contextual guidance.

#### Task Flow (`SoftwareEngineering/Task_Flow/`)
**Purpose**: Complete structured development workflow for Claude Code — from raw task to merged PR
- 5-phase workflow: Understand → Plan → Code → Document → PR
- Session recovery across Claude sessions
- Parallel background agents for testing, review, and documentation
- Safety rails: never commits to main, never auto-pushes, never fabricates
- Built-in task tracking for weekly reports
- Jira integration via Atlassian MCP

**Features**:
- 🔄 **Full Lifecycle**: Raw prompt to merged PR in one structured flow
- 🤖 **6 Background Agents**: Code reviewer, test runner, doc writer, commit writer, PR writer, plan verifier
- 🛡️ **Safety First**: Branch protection, explicit approvals, fabrication prevention
- 📋 **Task Tracking**: Weekly summaries and task history logging
- 🔌 **Stack Agnostic**: Works with any language — Java, TypeScript, Python, Go, Rust

**Use Case**: When you want a consistent, repeatable AI development workflow that enforces quality and tracks progress.

## 🚀 Quick Start

### Using the Easy Understanding Prompt
1. Copy the content from `General_Prompts/I_am_Dumb/easy_understanding.md`
2. Paste into your AI assistant
3. Replace `[Insert your topic, URL, or text here]` with what you want to understand
4. Get a clear, simple explanation

### Creating an AI Tech Lead Agent
1. Navigate to your project directory
2. Copy the agent creator prompt: `SoftwareEngineering/Coding_Agent_Creator/agent_creator.md`
3. Tell your AI assistant: "Read this prompt and create me an agent named [YourAgentName]"
4. Follow the setup process (takes ~5 minutes)
5. Your AI will analyze your project and become a specialized coding assistant

### Using Task Flow
1. Copy the `SoftwareEngineering/Task_Flow/` directory into your project
2. Follow the setup instructions in `Task_Flow/README.md`
3. In Claude Code, say `task-flow` to start your first structured task
4. See the [Task Flow README](SoftwareEngineering/Task_Flow/README.md) for full documentation

## 🎯 Who This Is For

- **Developers** who want AI assistants that understand their specific projects
- **Learners** who need complex topics explained simply
- **Teams** who want to standardize AI-assisted development workflows
- **Technical Leaders** who want AI help with architecture and code review

## 🔧 Requirements

- Any AI assistant (Claude, ChatGPT, Gemini, etc.)
- Access to copy/paste prompts
- For coding agents: file system access to your project

## 📈 Benefits

### For Learning
- Transform any complex topic into understandable explanations
- Structured learning with examples and validation
- Builds on existing knowledge

### For Development
- AI assistants that understand your specific codebase
- Consistent code review and guidance
- Automated task planning and progress tracking
- Prevention of repeated mistakes
- Continuous learning from your project evolution

## 🤝 Contributing

This is a growing collection of AI prompts. Contributions are welcome:

1. **New Prompts**: Add prompts that solve specific problems
2. **Improvements**: Enhance existing prompts based on usage experience
3. **Documentation**: Improve explanations and use cases
4. **Examples**: Add real-world usage examples

### Guidelines for New Prompts
- Focus on specific, actionable outcomes
- Include clear instructions and examples
- Test prompts with multiple AI assistants
- Provide context on when and why to use them

## 📝 License

This project is open source. Feel free to use, modify, and share these prompts.

## 🏷️ Tags

`ai-prompts` `productivity` `software-development` `learning` `automation` `coding-assistant` `documentation` `project-management`