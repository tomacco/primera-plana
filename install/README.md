# Installing Primera Plana

Primera Plana is a coding philosophy that optimizes for readers. It works as a standalone instruction file that **any AI coding agent** follows when writing or reviewing code.

## Available Language Files

| File | Language | Ecosystem |
|------|----------|-----------|
| `primera-plana-kotlin.md` | Kotlin (+ Arrow/Either) | Backend, Android |
| `primera-plana-java.md` | Java (+ Vavr) | Enterprise, Spring |
| `primera-plana-swift.md` | Swift (+ Result) | iOS, macOS |
| `primera-plana-typescript.md` | TypeScript (+ neverthrow) | Full-stack, React |
| `primera-plana-python.md` | Python (+ dry-python/returns) | Backend, ML |

---

## Setup by AI Coding Harness

Primera Plana works with any AI coding tool. Here's how to install for each:

### Claude Code

```bash
# Global (all projects)
curl -o ~/.claude/coding-standards.md https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Add to `~/.claude/CLAUDE.md`:
```markdown
**Coding standards**: Follow `~/.claude/coding-standards.md` strictly for all code.
```

Or per-project — add the file to your repo root and reference it in your project's `CLAUDE.md`.

### OpenAI Codex

```bash
# Add to project root
curl -o PRIMERA_PLANA.md https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Reference in `AGENTS.md`:
```markdown
**Coding standards**: Follow `PRIMERA_PLANA.md` strictly for all code. The "Newspaper Style" is the core principle — public methods are headlines, complexity lives in the leaves.
```

### GitHub Copilot

```bash
mkdir -p .github
curl -o .github/copilot-instructions.md https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Copilot reads `.github/copilot-instructions.md` automatically for all suggestions in that repo.

### Cursor

```bash
curl -o .cursorrules https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Cursor reads `.cursorrules` from the project root automatically.

### Windsurf (Codeium)

```bash
curl -o .windsurfrules https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Windsurf reads `.windsurfrules` from the project root automatically.

### Cline

```bash
curl -o .clinerules https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
```

Cline reads `.clinerules` from the project root automatically.

### Aider

Add to your `.aider.conf.yml`:
```yaml
read: PRIMERA_PLANA.md
```

Then place the file in your project root.

### Any other agent

The files are plain markdown. If your tool reads a system prompt, instructions file, or rules file — just point it at the Primera Plana language file. The format works universally.

---

## Quick Install Script

For convenience, use this one-liner that detects your tool and installs appropriately:

```bash
# Replace LANG with: kotlin, java, swift, typescript, or python
LANG=kotlin

# Detect and install
FILE="https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-${LANG}.md"

if [ -d ".github" ]; then
  curl -o .github/copilot-instructions.md "$FILE"
  echo "Installed for GitHub Copilot"
elif [ -f ".cursorrules" ] || command -v cursor &>/dev/null; then
  curl -o .cursorrules "$FILE"
  echo "Installed for Cursor"
elif [ -f ".windsurfrules" ]; then
  curl -o .windsurfrules "$FILE"
  echo "Installed for Windsurf"
elif [ -f "AGENTS.md" ]; then
  curl -o PRIMERA_PLANA.md "$FILE"
  echo "Installed for Codex — add reference to AGENTS.md"
elif [ -d ".claude" ] || [ -f "CLAUDE.md" ]; then
  curl -o PRIMERA_PLANA.md "$FILE"
  echo "Installed for Claude Code — add reference to CLAUDE.md"
else
  curl -o PRIMERA_PLANA.md "$FILE"
  echo "Installed as PRIMERA_PLANA.md — point your AI tool at this file"
fi
```

---

## Multiple Languages

If your project uses multiple languages (e.g., Kotlin backend + TypeScript frontend), install both:

```bash
curl -o PRIMERA_PLANA_KOTLIN.md https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-kotlin.md
curl -o PRIMERA_PLANA_TS.md https://raw.githubusercontent.com/tomacco/primera-plana/main/install/primera-plana-typescript.md
```

Then reference both in your agent's instructions file.

---

## Verifying Installation

After installing, ask your AI agent to write a use case or service class. Check that:

1. The public method is 5-10 lines of named steps
2. Private methods each do one thing
3. Method names describe WHAT, not HOW
4. Complexity (mapping, error handling, construction) lives in leaf methods
5. No inline logging, no nested control flow, no unnamed lambdas in the main method
