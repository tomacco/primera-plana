# Primera Plana — C# Coding Standards

These are your coding standards. Follow them strictly in all code you write or review.

## Philosophy

Code reads like a newspaper. Public methods are headlines (5-10 lines of named steps). Private methods are paragraphs (focused, self-contained). Complexity lives in the leaves. The reader decides how deep to go. Optimize for the reviewer who should be able to approve by reading only public methods.

---

## The Three Rules

1. **Headlines are short** — Public methods, endpoint handlers and controller actions are a sequence of named steps. No branching logic, no loops, no `try/catch`, no LINQ chains in the headline.
2. **Name the steps** — Method names describe WHAT happens, never HOW. Names read like a story.
3. **Complexity in the leaves** — Queries, LINQ pipelines, error mapping, retries, logging and object construction live in private leaf methods that are called but never call others.

---

## C#-Specific Rules

### Forbidden Patterns

- **No exceptions for control flow.** Expected failures return typed results (`ErrorOr<T>`, a `Result<T>`, or a closed record hierarchy). Exceptions are for bugs and infrastructure failures.
- **No `try/catch` in headlines.** Infrastructure failures go to middleware (`IExceptionHandler`) or a leaf that translates them into a result.
- **No fat controller actions.** An action or Minimal API handler is a headline. EF Core queries, mapping and orchestration live in leaves or in a handler class.
- **No inline LINQ chains in headlines.** The headline calls `PickFreshestBottles(fridge)`, not `.Where().OrderBy().Take().Select()`.
- **No `DateTime.Now` / `DateTime.UtcNow`.** Inject `TimeProvider` (.NET 8+) and call `GetUtcNow()`.
- **No null-forgiving operator (`!`)** to silence the compiler. Enable `<Nullable>enable</Nullable>` and narrow with patterns.
- **No `async void`** outside event handlers. No `.Result` or `.Wait()` on tasks.
- **No `if/else` cascades or `switch` statements in headlines.** Extract a decision leaf that returns a switch expression.
- **No string-interpolated log messages.** Use message templates, or `[LoggerMessage]` source-generated methods in the leaves.
- **No mutable DTOs.** Use `record` / `record struct` with `init` properties.

### Required Patterns

- **Guard clauses with pattern matching** — `if (await FindFridge(id, ct) is not { } fridge) return ...;` One guard per line, early return.
- **Each method does one thing.** If you can describe it with "and", split it.
- **Primary constructors** (C# 12) or constructor injection for all dependencies. No service locator.
- **Records** for value objects, commands, queries and responses.
- **`CancellationToken ct`** as the last parameter of every async method, passed all the way down.
- **Expression-bodied members** for one-line leaves.
- **Switch expressions** for decisions, in leaves.
- **`TypedResults` + `Results<...>`** for Minimal API return types, so the possible outcomes are visible in the signature.

### Guard Clause Headline

```csharp
// YES — a reviewer reads six lines and knows every outcome
public async Task<Results<Ok<CourierRoute>, NoContent, NotFound, Conflict<string>>> Restock(
    Guid fridgeId, CancellationToken ct)
{
    if (await FindFridge(fridgeId, ct) is not { } fridge) return TypedResults.NotFound();
    if (IsOffline(fridge)) return TypedResults.Conflict("Fridge offline");

    var lines = await PickFreshestBottles(fridge, ct);
    if (lines.Count == 0) return TypedResults.NoContent();

    var route = await DispatchCourier(fridge, lines, ct);
    return TypedResults.Ok(route);
}

// NO — query, telemetry check, LINQ, logging and error handling in one action
public async Task<IActionResult> Restock(Guid fridgeId)
{
    var fridge = await _db.Fridges.Include(f => f.Slots).FirstOrDefaultAsync(f => f.Id == fridgeId);
    if (fridge == null)
    {
        _logger.LogWarning($"Fridge {fridgeId} not found");
        return NotFound();
    }
    // ... 35 more lines of mixed querying, looping and try/catch
}
```

### Class Layout Order

```csharp
public sealed partial class RestockFridgeHandler(
    ZumoDbContext db,                  // 1. Dependencies (primary constructor)
    ICourierClient couriers,
    TimeProvider clock,
    ILogger<RestockFridgeHandler> log)
{
    // 2. Constants
    private static readonly TimeSpan HeartbeatTimeout = TimeSpan.FromMinutes(15);

    // 3. Public methods (THE HEADLINES)

    // 4. Private methods grouped by concern:
    // --- Resolution ---
    // --- Decisions ---
    // --- Processing ---
    // --- Persistence ---
    // --- Mapping ---
    // --- Logging ([LoggerMessage] partials) ---
}
```

---

## Error Handling

### Option A: Closed result hierarchy (no library)

```csharp
public abstract record RestockOutcome
{
    private RestockOutcome() { }

    public sealed record Dispatched(CourierRoute Route) : RestockOutcome;
    public sealed record FridgeNotFound(Guid FridgeId) : RestockOutcome;
    public sealed record FridgeOffline(Guid FridgeId) : RestockOutcome;
    public sealed record NothingToRestock : RestockOutcome;
}
```

The private constructor closes the hierarchy. Map it to HTTP with a switch expression in one leaf.

### Option B: ErrorOr 2.1+ (recommended for complex domains)

```csharp
public Task<ErrorOr<CourierRoute>> Restock(Guid fridgeId, CancellationToken ct) =>
    FindFridge(fridgeId, ct)
        .FailIf(IsOffline, FridgeErrors.Offline(fridgeId))
        .ThenAsync(fridge => PlanRestock(fridge, ct))
        .ThenAsync(plan => DispatchCourier(plan, ct));

private async Task<ErrorOr<Fridge>> FindFridge(Guid id, CancellationToken ct) =>
    await db.Fridges.Include(f => f.Slots).FirstOrDefaultAsync(f => f.Id == id, ct)
        is { } fridge ? fridge : FridgeErrors.NotFound(id);
```

`CSharpFunctionalExtensions` (`Result<T>`, `Bind`, `Ensure`, `Tap`) and `LanguageExt` (`Either<L, R>`) give the same shape.

### Guidance

- Use return types to communicate outcomes. Never throw for expected failures.
- A nullable reference (`Fridge?`) is for "might not exist" queries.
- `ErrorOr<T>` or a closed record hierarchy is for "can fail in known ways" operations.
- Reserve exceptions for programming errors and infrastructure failures, and catch them in middleware.

---

## ASP.NET Core Patterns

### Endpoint Headlines

```csharp
app.MapPost("/fridges/{fridgeId:guid}/restock", (Guid fridgeId, RestockFridgeHandler handler, CancellationToken ct) =>
    handler.Restock(fridgeId, ct));
```

The endpoint is one line. Its headline lives in the handler. The route file reads like a table of contents.

### Logging in Leaves

```csharp
[LoggerMessage(Level = LogLevel.Warning, Message = "Fridge {FridgeId} has not reported since {LastHeartbeat}")]
private partial void LogFridgeOffline(Guid fridgeId, DateTimeOffset lastHeartbeat);
```

Source-generated, allocation-free, and out of the headline.

---

## Testing Standards

### Structure

- One test class per production class. xUnit (or NUnit) with one `[Fact]` per behavior.
- Test method names: `Restock_returns_conflict_when_fridge_is_offline`.
- Arrange-Act-Assert with blank lines between sections.
- No logic in tests.

### Patterns

```csharp
[Fact]
public async Task Restock_returns_conflict_when_fridge_is_offline()
{
    // Arrange
    var fridge = AFridge() with { LastHeartbeat = Now.AddMinutes(-20) };
    await GivenFridge(fridge);

    // Act
    var result = await handler.Restock(fridge.Id, CancellationToken.None);

    // Assert
    Assert.IsType<Conflict<string>>(result.Result);
}
```

- **Test builders** — `AFridge()`, `ABottle()` return a valid record; tests override with `with { ... }`.
- **Mock boundaries, not internals.** Fake `ICourierClient` and HTTP; use a real or in-memory database. Never mock private methods.
- **One assertion concept per test.**
- **`FakeTimeProvider`** (`Microsoft.Extensions.TimeProvider.Testing`) to control time.

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Handler / Service | `VerbNounHandler` or `VerbNounService` | `RestockFridgeHandler` |
| Public method | Domain verb, PascalCase | `Restock`, `StartPressRun` |
| Async method | No `Async` suffix on handler headlines; suffix on library-style APIs | `Restock`, `ScheduleAsync` |
| Private resolution | `Find*`, `Resolve*`, `Load*` | `FindFridge` |
| Private decision | `Is*`, `Has*`, `Decide*` | `IsOffline`, `DecideGrade` |
| Private mapping | `To*`, `Build*` | `ToRestockLine`, `BuildRoute` |
| Error type | `*Errors` static class or `*Outcome` record | `FridgeErrors`, `RestockOutcome` |
| Test fixture | `A*()` / `An*()` builder | `AFridge()` |
| Constants | PascalCase `static readonly` or `const` | `HeartbeatTimeout` |

---

## Code Review Checklist

When reviewing C# code, verify:

- [ ] Public methods and endpoint handlers are under 10 lines and read as a sequence of named steps
- [ ] No exceptions for control flow — failures are return types
- [ ] No `try/catch` and no LINQ chains in the headline
- [ ] Guard clauses use pattern matching (`is not { } x`) with early return
- [ ] Each private method does exactly one thing
- [ ] Method names describe WHAT, not HOW
- [ ] Constructor or primary-constructor injection only
- [ ] Records used for commands, value objects and DTOs
- [ ] `CancellationToken` flows through every async call
- [ ] `TimeProvider` is injected, never `DateTime.UtcNow`
- [ ] Logging uses templates or `[LoggerMessage]`, never string interpolation
- [ ] Tests follow AAA structure with descriptive names
