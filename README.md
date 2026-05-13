# Primera Plana

**A coding philosophy where public methods are headlines and complexity lives in the leaves.**

---

## The Problem

AI changed who writes code. It didn't change who reads it.

In 2024, teams began reviewing 300+ pull requests per month — 43% of them AI-assisted. Writing got 10x faster. Reading didn't get 1% faster. The bottleneck shifted permanently: **the reader became the constraint**.

Primera Plana ("Front Page" in Spanish) is a response to that shift. It's a philosophy for writing code that respects the reader's time above all else.

## The Insight

Since the 1860s, journalists have used the **inverted pyramid**: put the most important information first, then supporting details, then background. The reader decides how deep to go.

Code should work the same way:

```
┌─────────────────────────────────┐
│   PUBLIC METHOD (the headline)  │  ← Read this: you know the full story
├─────────────────────────────────┤
│   PRIVATE METHODS (paragraphs)  │  ← Read these: you understand each step
├─────────────────────────────────┤
│   LEAVES (implementation)       │  ← Read these: you see every detail
└─────────────────────────────────┘
```

A reviewer reading only the headline knows *what* happens. Reading paragraphs reveals *how*. Only when debugging do you reach the leaves. The reader chooses their depth — just like a newspaper reader.

## What's Here

| Document | Description |
|----------|-------------|
| [**philosophy.md**](philosophy.md) | The complete Primera Plana philosophy — principles, rules, and examples |
| `guides/kotlin.md` | Kotlin reference implementation *(coming soon)* |
| `guides/swift.md` | Swift guide *(coming soon)* |
| `guides/typescript.md` | TypeScript guide *(coming soon)* |

## The Three Rules

1. **Headlines are short** — Your public method is a sequence of named steps. 5-10 lines. No conditionals, no loops, no error handling plumbing.

2. **Name the steps** — Method names describe WHAT happens, not HOW. `validateInventory()` not `checkIfItemsExistInWarehouseAndAreNotReserved()`.

3. **Complexity in the leaves** — Push all implementation detail to private methods. The trunk stays clean. Flatmap chains, retry logic, object construction — all in the leaves.

## Language-Agnostic, Idiom-Specific

Primera Plana is a philosophy, not a library. It works in any language. But each language has its own idioms for achieving it:

- **Kotlin**: Extension functions, sealed classes, Arrow/Either
- **Swift**: Result types, protocol extensions, guard statements
- **TypeScript**: Discriminated unions, pipe operators, Effect-TS

The philosophy is universal. The implementation is native.

## Who This Is For

- **Reviewers** drowning in AI-generated PRs who need to understand code in seconds, not minutes
- **Teams** where reading speed is the actual bottleneck
- **Writers** (human or AI) who want their code reviewed faster and approved sooner
- **Anyone** who has ever opened a 200-line method and thought "where do I even start"

## The Foundation Principle

> **The reader's time is more expensive than the writer's.**

Every decision in Primera Plana flows from this. More methods? Yes — if it makes the headline clearer. More indirection? Yes — if each layer is self-contained. More lines of code? Yes — if each line carries exactly one idea.

Writing is a one-time cost. Reading is a recurring cost paid by every reviewer, every debugger, every future maintainer. Optimize for the recurring cost.

---

*Primera Plana is open source. Contributions welcome — especially language guides and real-world before/after examples.*
