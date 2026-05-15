# Installing Primera Plana

Primera Plana is a coding philosophy that optimizes for readers. It works as **always-on coding standards** that your AI agent follows automatically — no manual invocation, no slash commands needed. Every time the agent writes or reviews code, it applies Primera Plana.

## One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash
```

This auto-detects your AI coding tool (Claude Code, Codex, Copilot, Cursor, Windsurf, Cline) and installs accordingly.

**Choose a language:**

```bash
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- kotlin
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- typescript
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- python
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- swift
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- java
```

---

## How It Works

Primera Plana installs as **coding standards** — a file your AI agent reads at the start of every session and follows for all code it writes. This is NOT a slash command you invoke manually. It's always on.

| AI Tool | What gets installed | How the agent loads it |
|---------|--------------------|-----------------------|
| **Claude Code** | `~/.claude/coding-standards.md` | Referenced from `CLAUDE.md` — loaded every session |
| **OpenAI Codex** | `PRIMERA_PLANA.md` in project root | Referenced from `AGENTS.md` — loaded every session |
| **GitHub Copilot** | `.github/copilot-instructions.md` | Auto-loaded for all suggestions in that repo |
| **Cursor** | `.cursorrules` | Auto-loaded from project root |
| **Windsurf** | `.windsurfrules` | Auto-loaded from project root |
| **Cline** | `.clinerules` | Auto-loaded from project root |
| **Aider** | `PRIMERA_PLANA.md` + `.aider.conf.yml` | Loaded via `read:` config |

**The agent doesn't need to be told to use it. It just does.**

---

## Available Language Files

| File | Language | Ecosystem |
|------|----------|-----------|
| `primera-plana-kotlin.md` | Kotlin (+ Arrow/Either) | Backend, Android |
| `primera-plana-java.md` | Java (+ Vavr) | Enterprise, Spring |
| `primera-plana-swift.md` | Swift (+ Result) | iOS, macOS |
| `primera-plana-typescript.md` | TypeScript (+ neverthrow) | Full-stack, React |
| `primera-plana-python.md` | Python (+ dry-python/returns) | Backend, ML |

---

## Manual Install by Tool

If you prefer manual installation over the script:

### Claude Code

```bash
# Download coding standards (always-on)
curl -fsSL -o ~/.claude/coding-standards.md \
  https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Add to `~/.claude/CLAUDE.md`:
```markdown
**Coding standards**: Follow `~/.claude/coding-standards.md` strictly for all code.
The "Newspaper Style" is the core principle — public methods are headlines, complexity lives in the leaves.
```

That's it. Every Claude Code session now follows Primera Plana automatically.

### OpenAI Codex

```bash
curl -fsSL -o PRIMERA_PLANA.md \
  https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Add to `AGENTS.md`:
```markdown
**Coding standards**: Follow `PRIMERA_PLANA.md` strictly for all code.
The "Newspaper Style" is the core principle — public methods are headlines, complexity lives in the leaves.
```

### GitHub Copilot

```bash
mkdir -p .github
curl -fsSL -o .github/copilot-instructions.md \
  https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Copilot reads `.github/copilot-instructions.md` automatically for all suggestions in that repo.

### Cursor

```bash
curl -fsSL -o .cursorrules \
  https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

### Windsurf (Codeium)

```bash
curl -fsSL -o .windsurfrules \
  https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

### Cline

```bash
curl -fsSL -o .clinerules \
  https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

### Aider

```yaml
# .aider.conf.yml
read: PRIMERA_PLANA.md
```

### Any other agent

The files are plain markdown. If your tool reads a system prompt, instructions file, or rules file — just point it at the Primera Plana language file. The format works universally.

---

## Bonus: `/primera-plana` Skill (Optional)

The install script also places a Claude Code slash command at `~/.claude/commands/primera-plana.md`. This gives you an **explicit** refactoring tool:

```
/primera-plana refactor    — Refactor current code to Primera Plana style
/primera-plana review      — Review code for readability (suggestions only)
```

This is optional — the always-on standards handle new code. The skill is for explicitly refactoring legacy code.

---

## Multiple Languages

If your project uses multiple languages (e.g., Kotlin backend + TypeScript frontend):

```bash
# Run installer twice
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- kotlin
curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- typescript
```

Or manually combine files and reference both from your agent config.

---

## Verifying Installation

After installing, ask your AI agent to write a use case or service class. Check that:

1. The public method is 5-10 lines of named steps
2. Private methods each do one thing
3. Method names describe WHAT, not HOW
4. Complexity (mapping, error handling, construction) lives in leaf methods
5. No inline logging, no nested control flow, no unnamed lambdas in the main method

If the agent doesn't follow these patterns, check that your `CLAUDE.md` / `AGENTS.md` / config file references the coding standards file.
