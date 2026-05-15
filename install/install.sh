#!/bin/bash
# Primera Plana — One-command installer for AI coding harnesses
# Usage: curl -fsSL https://raw.githubusercontent.com/tomacco/primera-plana/main/install/install.sh | bash -s -- [language]
# Languages: kotlin (default), java, swift, typescript, python

set -euo pipefail

LANG="${1:-kotlin}"
REPO="https://raw.githubusercontent.com/tomacco/primera-plana/main"
STANDARDS_URL="${REPO}/install/primera-plana-${LANG}.md"
SKILL_URL="${REPO}/install/skill/primera-plana.md"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Primera Plana — Code That Reads Like a Front Page${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Language: ${CYAN}${LANG}${NC}"
echo ""

# Detect which AI coding tool is in use
installed_for=""

# --- Claude Code ---
if [ -d "$HOME/.claude" ]; then
  echo -e "${GREEN}[Claude Code]${NC} Detected ~/.claude"

  # Install coding standards
  curl -fsSL "$STANDARDS_URL" -o "$HOME/.claude/coding-standards.md"
  echo -e "  ${GREEN}✓${NC} Installed coding standards → ~/.claude/coding-standards.md"

  # Install skill (slash command)
  mkdir -p "$HOME/.claude/commands"
  curl -fsSL "$SKILL_URL" -o "$HOME/.claude/commands/primera-plana.md"
  echo -e "  ${GREEN}✓${NC} Installed /primera-plana skill → ~/.claude/commands/primera-plana.md"

  # Check if CLAUDE.md already references it
  if [ -f "$HOME/.claude/CLAUDE.md" ]; then
    if ! grep -q "coding-standards.md" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
      echo ""
      echo -e "  ${YELLOW}⚠${NC}  Add this to your ~/.claude/CLAUDE.md:"
      echo -e "     ${CYAN}**Coding standards**: Follow \`~/.claude/coding-standards.md\` strictly for all code.${NC}"
    else
      echo -e "  ${GREEN}✓${NC} CLAUDE.md already references coding-standards.md"
    fi
  else
    echo ""
    echo -e "  ${YELLOW}⚠${NC}  Create ~/.claude/CLAUDE.md with:"
    echo -e "     ${CYAN}**Coding standards**: Follow \`~/.claude/coding-standards.md\` strictly for all code.${NC}"
  fi

  installed_for="Claude Code"
fi

# --- OpenAI Codex (project-level) ---
if [ -f "AGENTS.md" ]; then
  curl -fsSL "$STANDARDS_URL" -o "PRIMERA_PLANA.md"
  echo -e "${GREEN}[Codex]${NC} Installed → ./PRIMERA_PLANA.md"
  echo -e "  ${YELLOW}⚠${NC}  Add to AGENTS.md: ${CYAN}Follow \`PRIMERA_PLANA.md\` strictly for all code.${NC}"
  installed_for="${installed_for:+$installed_for, }Codex"
fi

# --- GitHub Copilot (project-level) ---
if [ -d ".github" ]; then
  curl -fsSL "$STANDARDS_URL" -o ".github/copilot-instructions.md"
  echo -e "${GREEN}[Copilot]${NC} Installed → .github/copilot-instructions.md"
  installed_for="${installed_for:+$installed_for, }Copilot"
fi

# --- Cursor ---
if [ -f ".cursorrules" ] || [ -d ".cursor" ]; then
  curl -fsSL "$STANDARDS_URL" -o ".cursorrules"
  echo -e "${GREEN}[Cursor]${NC} Installed → .cursorrules"
  installed_for="${installed_for:+$installed_for, }Cursor"
fi

# --- Windsurf ---
if [ -f ".windsurfrules" ]; then
  curl -fsSL "$STANDARDS_URL" -o ".windsurfrules"
  echo -e "${GREEN}[Windsurf]${NC} Installed → .windsurfrules"
  installed_for="${installed_for:+$installed_for, }Windsurf"
fi

# --- Cline ---
if [ -f ".clinerules" ]; then
  curl -fsSL "$STANDARDS_URL" -o ".clinerules"
  echo -e "${GREEN}[Cline]${NC} Installed → .clinerules"
  installed_for="${installed_for:+$installed_for, }Cline"
fi

# --- Fallback: nothing detected, install for Claude Code anyway ---
if [ -z "$installed_for" ]; then
  mkdir -p "$HOME/.claude/commands"
  curl -fsSL "$STANDARDS_URL" -o "$HOME/.claude/coding-standards.md"
  curl -fsSL "$SKILL_URL" -o "$HOME/.claude/commands/primera-plana.md"
  echo -e "${GREEN}[Default]${NC} Installed for Claude Code (no specific tool detected)"
  echo -e "  ${GREEN}✓${NC} ~/.claude/coding-standards.md"
  echo -e "  ${GREEN}✓${NC} ~/.claude/commands/primera-plana.md"
  installed_for="Claude Code (default)"
fi

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Done!${NC} Installed for: ${BOLD}${installed_for}${NC}"
echo ""
echo -e "  ${CYAN}Usage:${NC}"
echo -e "    /primera-plana refactor    — Refactor current code"
echo -e "    /primera-plana review      — Review for readability"
echo -e "    /primera-plana write <desc> — Write new code"
echo ""
echo -e "  ${CYAN}Philosophy:${NC} https://github.com/tomacco/primera-plana"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
