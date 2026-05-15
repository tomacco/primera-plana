---
name: primera-plana
description: "Apply the Primera Plana coding philosophy to refactor, review, or write code. Public methods are headlines (5-10 lines of named steps), complexity lives in the leaves. Use when: writing new features, refactoring existing code, or reviewing PRs for readability."
---

# Primera Plana — Code That Reads Like a Front Page

Apply the Primera Plana philosophy to the code at hand. Determine the action from `$ARGUMENTS`:

- **No arguments or "refactor"**: Refactor the current file or selection following Primera Plana principles
- **"review"**: Review the current file and suggest Primera Plana improvements (don't change code, just comment)
- **"write \<description\>"**: Write new code following Primera Plana from scratch

---

## The Three Rules

1. **Headlines are short** — Public methods are 5-10 lines. A sequence of named steps. No branching logic, no loops, no error-handling plumbing in the headline.
2. **Name the steps** — Method names describe WHAT happens, never HOW. Names read like a story: `validateOrder()`, `resolveCustomer()`, `processPayment()`.
3. **Complexity in the leaves** — Error mapping, retries, object construction, stream operations, logging — all in private leaf methods that are called but never call other private methods.

---

## Refactoring Procedure

When refactoring existing code:

### Step 1: Identify the headline

Find the public entry point. This will become the "front page" — a clean sequence of named steps.

### Step 2: Extract named steps

For each logical operation in the public method, extract it into a private method with a name that describes WHAT it does (not HOW).

**Before:**
```
fun execute(request: Request): Result {
    // 40 lines of validation, resolution, processing, mapping, logging...
}
```

**After:**
```
fun execute(request: Request): Result {
    val customer = resolveCustomer(request)
    val items = validateItems(request)
    val payment = processPayment(customer, items)
    return confirmOrder(customer, items, payment)
}
```

### Step 3: Push complexity to leaves

Each private method should either:
- Orchestrate (call other private methods) — making it a "paragraph"
- Do actual work (map, filter, construct, call external) — making it a "leaf"

Never both. If a private method both orchestrates AND does work, split it.

### Step 4: Apply language idioms

Use the language's native patterns:
- **Kotlin**: Extension functions, sealed classes, Either/Arrow, expression bodies
- **Swift**: Result types, guard statements, protocol extensions
- **TypeScript**: Discriminated unions, pipe operators, branded types
- **Python**: dataclasses, match statements, Result monads
- **Java**: sealed interfaces, records, Vavr Either

### Step 5: Verify the newspaper test

Read ONLY the public method aloud. Can a reviewer understand the full behavior without reading any private method? If not, rename or restructure until they can.

---

## Review Procedure

When reviewing code for Primera Plana compliance:

Rate each file on these axes (1-5):
1. **Headline clarity** — Can you understand the public method in <10 seconds?
2. **Step naming** — Do method names tell a story?
3. **Leaf isolation** — Is complexity pushed to the bottom?
4. **Depth choice** — Can a reader choose their depth without being forced deeper?

Provide specific suggestions with before/after snippets.

---

## Anti-Patterns to Fix

| Anti-Pattern | Fix |
|---|---|
| Public method > 10 lines | Extract named steps |
| `if/else` in public method | Extract to `private fun decideSomething()` |
| Inline lambda > 3 lines | Extract to named private method |
| Method named "handle" or "process" with no specificity | Rename to describe WHAT it does |
| Logging mixed with business logic | Extract logging to leaf method |
| Error mapping inline | Extract to `private fun mapToError()` |
| Constructor with complex initialization | Extract to factory or builder leaf |

---

## Output Format

When refactoring or writing, output:
1. The refactored/new code
2. A brief "Newspaper Test" summary: what a reviewer learns from reading ONLY the headlines

Do NOT add unnecessary comments, docstrings, or annotations. The method names ARE the documentation.
