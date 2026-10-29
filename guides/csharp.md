# Primera Plana — C# Guide

Code reads like a newspaper. Public methods are headlines. Private methods are paragraphs. Complexity lives in the leaves. The reader decides how deep to go.

This guide shows how to write C# that follows Primera Plana in modern .NET (8+): ASP.NET Core, EF Core, Minimal APIs and handler classes. It works with plain guard clauses or with a result library such as ErrorOr.

---

## The Domain: Zumo

Zumo is a tech-run cold-pressed juice company.

- **Fruit lots** arrive from partner farms. Each lot is graded on Brix (sugar) and acidity.
- **Press runs** turn lots into bottles on IoT-connected presses, followed by a high-pressure processing (HPP) cycle that sets the best-before date.
- **Smart fridges** in offices and gyms report stock and a heartbeat every few minutes.
- **Restocks** pick the freshest bottles from the warehouse and dispatch a courier route.
- **Juice plans** are weekly subscriptions delivered to homes.

---

## The Philosophy in Five Rules

1. **Headlines are short** — public methods, controller actions and endpoint handlers are 5-10 lines of named steps
2. **Name the steps** — method names describe WHAT, not HOW
3. **Complexity in the leaves** — EF Core queries, LINQ, logging, error mapping and construction live in private methods
4. **The reader's time > the writer's time**
5. **The philosophy works with or without a result library** — guard clauses and `ErrorOr<T>` are equally valid

---

## C#'s Natural Strengths

Modern C# has most of the tools built in:

- **Pattern matching** (`is not { } fridge`) turns a lookup plus null check into a one-line guard
- **Switch expressions** make decisions into small, pure leaves
- **Records** with `with { }` give immutable commands, DTOs and test fixtures for free
- **Primary constructors** (C# 12) remove the field-and-constructor ceremony around dependencies
- **`TypedResults` + `Results<...>`** put every HTTP outcome in the method signature
- **`[LoggerMessage]`** source-generated logging lives naturally in the leaves
- **`TimeProvider`** (.NET 8) makes time an injected dependency

The one trap: C# makes it very easy to write a 60-line controller action with LINQ, EF Core and `try/catch` all in one place. That action is the "before" in every example below.

---

## Part 1: The Headline Pattern

### RestockFridge — Before

The shape every ASP.NET Core codebase has somewhere: a controller action that queries, checks, loops, calls out, saves, logs and catches.

```csharp
[ApiController]
[Route("fridges")]
public class FridgesController : ControllerBase
{
    private readonly ZumoDbContext _db;
    private readonly ICourierClient _couriers;
    private readonly ILogger<FridgesController> _logger;

    // constructor omitted

    [HttpPost("{fridgeId}/restock")]
    public async Task<IActionResult> Restock(Guid fridgeId)
    {
        var fridge = await _db.Fridges.Include(f => f.Slots)
            .FirstOrDefaultAsync(f => f.Id == fridgeId);
        if (fridge == null)
        {
            _logger.LogWarning($"Fridge {fridgeId} not found");
            return NotFound();
        }
        if (fridge.LastHeartbeat < DateTime.UtcNow.AddMinutes(-15))
        {
            _logger.LogWarning($"Fridge {fridgeId} offline since {fridge.LastHeartbeat}");
            return Conflict("Fridge offline");
        }

        var lines = new List<RestockLine>();
        foreach (var slot in fridge.Slots.Where(s => s.Count < s.Capacity))
        {
            var bottles = await _db.Bottles
                .Where(b => b.Sku == slot.Sku && b.Reserved == false)
                .Where(b => b.BestBefore > DateTime.UtcNow.AddDays(3))
                .OrderBy(b => b.BestBefore)
                .Take(slot.Capacity - slot.Count)
                .ToListAsync();
            if (bottles.Count == 0) continue;
            foreach (var b in bottles) b.Reserved = true;
            lines.Add(new RestockLine(slot.Id, bottles.Select(b => b.Id).ToList()));
        }
        if (!lines.Any()) return NoContent();

        try
        {
            var route = await _couriers.ScheduleAsync(fridge.Address, lines);
            _db.Restocks.Add(new Restock
            {
                FridgeId = fridgeId,
                RouteId = route.Id,
                Lines = lines,
                CreatedAt = DateTime.UtcNow
            });
            await _db.SaveChangesAsync();
            return Ok(route);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, $"Courier API failed for fridge {fridgeId}");
            return StatusCode(503);
        }
    }
}
```

To approve this, a reviewer has to read every line. The freshness rule (three days), the heartbeat rule (fifteen minutes), the reservation side effect and the courier failure path are all mixed together. There is no `CancellationToken`, time is untestable, and logs are string-interpolated.

### RestockFridge — After (Guard Clauses)

```csharp
app.MapPost("/fridges/{fridgeId:guid}/restock",
    (Guid fridgeId, RestockFridgeHandler handler, CancellationToken ct) => handler.Restock(fridgeId, ct));
```

```csharp
public sealed partial class RestockFridgeHandler(
    ZumoDbContext db,
    ICourierClient couriers,
    TimeProvider clock,
    ILogger<RestockFridgeHandler> log)
{
    private static readonly TimeSpan HeartbeatTimeout = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan MinimumShelfLife = TimeSpan.FromDays(3);

    public async Task<Results<Ok<CourierRoute>, NoContent, NotFound, Conflict<string>>> Restock(
        Guid fridgeId, CancellationToken ct)
    {
        if (await FindFridge(fridgeId, ct) is not { } fridge) return TypedResults.NotFound();
        if (IsOffline(fridge)) return TypedResults.Conflict("Fridge offline");

        var lines = await ReserveFreshestBottles(fridge, ct);
        if (lines.Count == 0) return TypedResults.NoContent();

        var route = await DispatchCourier(fridge, lines, ct);
        return TypedResults.Ok(route);
    }

    // --- Resolution ---

    private Task<Fridge?> FindFridge(Guid id, CancellationToken ct) =>
        db.Fridges.Include(f => f.Slots).FirstOrDefaultAsync(f => f.Id == id, ct);

    // --- Decisions ---

    private bool IsOffline(Fridge fridge)
    {
        var offline = fridge.LastHeartbeat < clock.GetUtcNow() - HeartbeatTimeout;
        if (offline) LogFridgeOffline(fridge.Id, fridge.LastHeartbeat);
        return offline;
    }

    // --- Processing ---

    private async Task<List<RestockLine>> ReserveFreshestBottles(Fridge fridge, CancellationToken ct)
    {
        var lines = new List<RestockLine>();
        foreach (var slot in fridge.Slots.Where(s => s.HasRoom))
        {
            var bottles = await FindFreshestBottles(slot, ct);
            if (bottles.Count > 0) lines.Add(Reserve(slot, bottles));
        }
        return lines;
    }

    private Task<List<Bottle>> FindFreshestBottles(FridgeSlot slot, CancellationToken ct) =>
        db.Bottles
            .Where(b => b.Sku == slot.Sku && !b.Reserved)
            .Where(b => b.BestBefore > clock.GetUtcNow() + MinimumShelfLife)
            .OrderBy(b => b.BestBefore)
            .Take(slot.FreeSpace)
            .ToListAsync(ct);

    private async Task<CourierRoute> DispatchCourier(Fridge fridge, List<RestockLine> lines, CancellationToken ct)
    {
        var route = await couriers.ScheduleAsync(fridge.Address, lines, ct);
        db.Restocks.Add(BuildRestock(fridge, route, lines));
        await db.SaveChangesAsync(ct);
        return route;
    }

    // --- Mapping ---

    private static RestockLine Reserve(FridgeSlot slot, List<Bottle> bottles)
    {
        bottles.ForEach(b => b.Reserved = true);
        return new RestockLine(slot.Id, bottles.ConvertAll(b => b.Id));
    }

    private Restock BuildRestock(Fridge fridge, CourierRoute route, List<RestockLine> lines) =>
        new(fridge.Id, route.Id, lines, clock.GetUtcNow());

    // --- Logging ---

    [LoggerMessage(Level = LogLevel.Warning, Message = "Fridge {FridgeId} has not reported since {LastHeartbeat}")]
    private partial void LogFridgeOffline(Guid fridgeId, DateTimeOffset lastHeartbeat);
}
```

Read only `Restock`: find the fridge, refuse if offline, reserve the freshest bottles, nothing to do if none, dispatch a courier. Every outcome is in the signature. The freshness rule lives in `FindFreshestBottles`, the heartbeat rule in `IsOffline`.

The courier `HttpRequestException` is gone from the handler. It is an infrastructure failure, so an `IExceptionHandler` turns it into a 503 for every endpoint in one place.

### RestockFridge — After (ErrorOr)

With [ErrorOr](https://github.com/amantinband/error-or) (2.1 or later), the headline becomes a pipeline. Each step returns `ErrorOr<T>`; the first error short-circuits the rest.

```csharp
public Task<ErrorOr<CourierRoute>> Restock(Guid fridgeId, CancellationToken ct) =>
    FindFridge(fridgeId, ct)
        .FailIf(IsOffline, FridgeErrors.Offline(fridgeId))
        .ThenAsync(fridge => PlanRestock(fridge, ct))
        .ThenAsync(plan => DispatchCourier(plan, ct));

private async Task<ErrorOr<Fridge>> FindFridge(Guid id, CancellationToken ct) =>
    await db.Fridges.Include(f => f.Slots).FirstOrDefaultAsync(f => f.Id == id, ct)
        is { } fridge ? fridge : FridgeErrors.NotFound(id);

private async Task<ErrorOr<RestockPlan>> PlanRestock(Fridge fridge, CancellationToken ct) =>
    await ReserveFreshestBottles(fridge, ct) is { Count: > 0 } lines
        ? new RestockPlan(fridge, lines)
        : FridgeErrors.NothingToRestock(fridge.Id);
```

```csharp
public static class FridgeErrors
{
    public static Error NotFound(Guid id) =>
        Error.NotFound("Fridge.NotFound", $"Fridge {id} does not exist");

    public static Error Offline(Guid id) =>
        Error.Conflict("Fridge.Offline", $"Fridge {id} stopped reporting");

    public static Error NothingToRestock(Guid id) =>
        Error.Custom(204, "Fridge.Full", $"Fridge {id} needs no bottles");
}
```

The endpoint maps the result in one line, with a single shared leaf for errors:

```csharp
app.MapPost("/fridges/{fridgeId:guid}/restock",
    async (Guid fridgeId, RestockFridgeHandler handler, CancellationToken ct) =>
        (await handler.Restock(fridgeId, ct)).Match(route => Results.Ok(route), ToProblem));
```

---

### StartPressRun — Before

Domain logic, no HTTP. A press run takes a fruit lot, checks its grade and the press, and schedules the HPP cycle.

```csharp
public async Task<PressRun> StartPressRun(Guid lotId, Guid pressId)
{
    var lot = await _lots.GetAsync(lotId);
    if (lot is null) throw new NotFoundException("lot");
    if (lot.Status != LotStatus.Received && lot.Status != LotStatus.Graded)
        throw new InvalidOperationException($"Lot {lotId} is {lot.Status}");

    var grade = lot.Brix >= 12.0m && lot.Acidity <= 0.8m ? "A"
        : lot.Brix >= 10.0m ? "B"
        : "C";
    if (grade == "C")
    {
        lot.Status = LotStatus.Rejected;
        await _lots.SaveAsync(lot);
        await _farms.NotifyRejectionAsync(lot.FarmId, lotId, lot.Brix);
        throw new QualityException($"Lot {lotId} rejected: Brix {lot.Brix}");
    }

    var press = (await _presses.ListAsync())
        .Where(p => p.Online && p.Sanitised && p.CurrentRunId == null)
        .OrderByDescending(p => p.Id == pressId)
        .ThenBy(p => p.HoursSinceService)
        .FirstOrDefault();
    if (press == null) throw new InvalidOperationException("No press available");

    var run = new PressRun
    {
        Id = Guid.NewGuid(), LotId = lotId, PressId = press.Id, Grade = grade,
        StartedAt = DateTime.Now,
        HppSlot = DateTime.Now.AddMinutes(press.Model == "XL" ? 90 : 45)
    };
    press.CurrentRunId = run.Id;
    lot.Status = LotStatus.Pressing;
    await _runs.SaveAsync(run);
    await _presses.SaveAsync(press);
    await _lots.SaveAsync(lot);
    return run;
}
```

Four exceptions for expected outcomes, a nested ternary for grading, a LINQ query choosing a press, a magic `"XL"`, and `DateTime.Now` twice.

### StartPressRun — After

```csharp
public sealed class StartPressRunHandler(
    ILotRepository lots,
    IPressRepository presses,
    IPressRunRepository runs,
    IFarmNotifier farms,
    TimeProvider clock)
{
    public async Task<ErrorOr<PressRun>> Start(StartPressRun command, CancellationToken ct)
    {
        if (await FindPressableLot(command.LotId, ct) is not { } lot) return PressErrors.LotNotPressable(command.LotId);
        if (DecideGrade(lot) is Grade.C) return await RejectLot(lot, ct);
        if (await FindAvailablePress(command.PreferredPressId, ct) is not { } press) return PressErrors.NoPressAvailable;

        var run = BuildRun(lot, press);
        await runs.Begin(run, lot, press, ct);
        return run;
    }

    // --- Resolution ---

    private async Task<FruitLot?> FindPressableLot(Guid lotId, CancellationToken ct) =>
        await lots.Find(lotId, ct) is { Status: LotStatus.Received or LotStatus.Graded } lot ? lot : null;

    private async Task<Press?> FindAvailablePress(Guid preferredId, CancellationToken ct) =>
        (await presses.ListIdle(ct))
            .OrderByDescending(p => p.Id == preferredId)
            .ThenBy(p => p.HoursSinceService)
            .FirstOrDefault();

    // --- Decisions ---

    private static Grade DecideGrade(FruitLot lot) => lot switch
    {
        { Brix: >= 12.0m, Acidity: <= 0.8m } => Grade.A,
        { Brix: >= 10.0m } => Grade.B,
        _ => Grade.C,
    };

    // --- Processing ---

    private async Task<Error> RejectLot(FruitLot lot, CancellationToken ct)
    {
        await lots.Save(lot with { Status = LotStatus.Rejected }, ct);
        await farms.NotifyRejection(lot.FarmId, lot.Id, lot.Brix, ct);
        return PressErrors.LotRejected(lot.Id, lot.Brix);
    }

    // --- Mapping ---

    private PressRun BuildRun(FruitLot lot, Press press)
    {
        var now = clock.GetUtcNow();
        return new PressRun(Guid.NewGuid(), lot.Id, press.Id, DecideGrade(lot), now, now + press.HppLeadTime);
    }
}
```

The headline tells the whole story: find a pressable lot, reject grade C, find a press, build the run, begin it. The grading table is a switch expression a quality engineer can read without knowing C#. "Is this press idle" moved into the repository query (`ListIdle`), and the HPP lead time is a property of the press, not a string comparison.

---

## Part 2: C#-Specific Rules

### 1. Guard clauses with `is not { } x`

The property pattern `{ }` matches any non-null value and declares a non-nullable variable. It is the C# equivalent of Kotlin's `?: return` and Swift's `guard let`.

```csharp
// NO
var lot = await lots.Find(lotId, ct);
if (lot == null)
{
    return PressErrors.LotNotFound(lotId);
}

// YES
if (await lots.Find(lotId, ct) is not { } lot) return PressErrors.LotNotFound(lotId);
```

Add properties to the pattern when the guard has a condition: `is not { Status: LotStatus.Received } lot`.

### 2. Decisions are switch expressions, in leaves

```csharp
// NO — in the headline
string label;
if (bottle.DaysLeft > 7) label = "fresh";
else if (bottle.DaysLeft > 2) label = "discount";
else label = "donate";

// YES — a named leaf
private static ShelfAction DecideShelfAction(Bottle bottle) => bottle.DaysLeft switch
{
    > 7 => ShelfAction.Sell,
    > 2 => ShelfAction.Discount,
    _ => ShelfAction.Donate,
};
```

### 3. LINQ lives in leaves, and gets a name

`.Where().OrderBy().Take()` tells the reader HOW. `FindFreshestBottles(slot)` tells them WHAT. Short single-predicate calls (`.Where(s => s.HasRoom)`) are fine anywhere.

### 4. Inject `TimeProvider`, never `DateTime.UtcNow`

```csharp
// NO
if (fridge.LastHeartbeat < DateTime.UtcNow.AddMinutes(-15))

// YES
private bool IsOffline(Fridge fridge) =>
    fridge.LastHeartbeat < clock.GetUtcNow() - HeartbeatTimeout;
```

Register `TimeProvider.System` in DI. In tests, use `FakeTimeProvider` and `Advance(...)`.

### 5. `CancellationToken` all the way down

Every async method takes `CancellationToken ct` as its last parameter and passes it on. A headline that drops the token makes every leaf below it uncancellable.

### 6. Exceptions are for infrastructure, and are caught once

```csharp
internal sealed class CourierOutageHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception ex, CancellationToken ct)
    {
        if (ex is not HttpRequestException) return false;
        await Results.Problem(statusCode: 503, title: "Courier service unavailable").ExecuteAsync(http);
        return true;
    }
}
```

No handler or action catches `HttpRequestException` itself.

### 7. Logging with `[LoggerMessage]`

```csharp
// NO — interpolation allocates and defeats structured logging
_logger.LogWarning($"Fridge {fridgeId} offline since {fridge.LastHeartbeat}");

// YES — a leaf, generated at compile time
[LoggerMessage(Level = LogLevel.Warning, Message = "Fridge {FridgeId} has not reported since {LastHeartbeat}")]
private partial void LogFridgeOffline(Guid fridgeId, DateTimeOffset lastHeartbeat);
```

The class must be `partial` and have an `ILogger` field or primary-constructor parameter.

### 8. Records for everything that is data

```csharp
public sealed record StartPressRun(Guid LotId, Guid PreferredPressId);
public sealed record RestockLine(Guid SlotId, IReadOnlyList<Guid> BottleIds);
```

`with { }` replaces mutation in domain code and in test fixtures.

### 9. No `!` to silence nullability

With `<Nullable>enable</Nullable>`, `fridge!.Slots` is a bug report waiting to happen. Narrow with a pattern or a guard instead.

### 10. MediatR and vertical slices

If you use MediatR or a vertical-slice layout, `Handle` is the headline and the same rules apply. The pattern does not need MediatR: a plain handler class injected into the endpoint, as above, is enough.

---

## Part 3: Class Layout

```csharp
public sealed partial class RestockFridgeHandler(   // 1. Dependencies
    ZumoDbContext db,
    ICourierClient couriers,
    TimeProvider clock,
    ILogger<RestockFridgeHandler> log)
{
    // 2. Constants
    private static readonly TimeSpan HeartbeatTimeout = TimeSpan.FromMinutes(15);

    // 3. Public methods (THE HEADLINES)
    public async Task<...> Restock(Guid fridgeId, CancellationToken ct) { ... }

    // 4. Private methods, grouped by concern, in the order the headline calls them
    // --- Resolution ---
    // --- Decisions ---
    // --- Processing ---
    // --- Persistence ---
    // --- Mapping ---
    // --- Logging ---
}
```

One public method per handler is the norm. A reader opening the file sees the headline within the first screen.

---

## Part 4: Testing

### Shared defaults with `with { }` overrides

```csharp
public static class Fixtures
{
    public static readonly DateTimeOffset Now = new(2026, 6, 1, 9, 0, 0, TimeSpan.Zero);

    public static Fridge AFridge() => new(
        Id: Guid.NewGuid(),
        Address: "Gym Norte, Planta 1",
        LastHeartbeat: Now.AddMinutes(-2),
        Slots: [new FridgeSlot(Guid.NewGuid(), Sku: "ORANGE-CARROT-330", Count: 2, Capacity: 12)]);

    public static Bottle ABottle(string sku) => new(Guid.NewGuid(), sku, BestBefore: Now.AddDays(10), Reserved: false);
}
```

```csharp
public class RestockFridgeHandlerTests
{
    private readonly FakeTimeProvider clock = new(Fixtures.Now);
    private readonly FakeCourierClient couriers = new();

    [Fact]
    public async Task Restock_returns_conflict_when_fridge_is_offline()
    {
        // Arrange
        var fridge = AFridge() with { LastHeartbeat = Now.AddMinutes(-20) };
        var handler = await GivenHandlerWith(fridge);

        // Act
        var result = await handler.Restock(fridge.Id, CancellationToken.None);

        // Assert
        Assert.IsType<Conflict<string>>(result.Result);
    }

    [Fact]
    public async Task Restock_skips_bottles_that_expire_within_three_days()
    {
        // Arrange
        var fridge = AFridge();
        var nearlyExpired = ABottle("ORANGE-CARROT-330") with { BestBefore = Now.AddDays(2) };
        var handler = await GivenHandlerWith(fridge, nearlyExpired);

        // Act
        var result = await handler.Restock(fridge.Id, CancellationToken.None);

        // Assert
        Assert.IsType<NoContent>(result.Result);
    }
}
```

### Testing rules

- Test names read as a sentence: `Method_outcome_when_condition`.
- Arrange-Act-Assert with blank lines between sections.
- Fake the boundaries (`ICourierClient`, HTTP, message bus). Use a real database (Testcontainers) or EF Core SQLite for the rest.
- Never mock a private method, and never make one `internal` just to test it. Test through the headline.
- Control time with `FakeTimeProvider`, never with `Thread.Sleep`.

---

## Part 5: Choosing an Error Style

| Style | Use when | Headline looks like |
|-------|----------|--------------------|
| Guard clauses + `TypedResults` | Endpoint handlers, simple flows | `if (... is not { } x) return TypedResults.NotFound();` |
| Closed record hierarchy | You want no dependency and exhaustive outcomes | `return new RestockOutcome.Dispatched(route);` |
| [ErrorOr](https://github.com/amantinband/error-or) | Multi-step domain flows, vertical slices | `.FailIf(...).ThenAsync(...).ThenAsync(...)` |
| [CSharpFunctionalExtensions](https://github.com/vkhorikov/CSharpFunctionalExtensions) | Teams already using `Result<T>`, `Maybe<T>` | `.Ensure(...).Bind(...).Tap(...)` |
| [LanguageExt](https://github.com/louthy/language-ext) | Teams committed to full FP | `from x in ... select ...` |

The philosophy is the constant. Pick one style per codebase and use it everywhere.

---

## Guiding Principles — C# Edition

| Principle | C# Implementation |
|-----------|-------------------|
| Headlines are short | Guard clauses with `is not { } x` + named calls |
| Name the steps | `FindFridge`, `IsOffline`, `ReserveFreshestBottles` |
| Complexity in the leaves | Private methods: EF Core, LINQ, mapping, `[LoggerMessage]` |
| Explicit outcomes | `Results<...>`, `ErrorOr<T>` or a closed record hierarchy |
| Exceptions are infrastructure | `IExceptionHandler` middleware, caught once |
| Data is immutable | `record` + `with { }` |
| Time is a dependency | `TimeProvider`, `FakeTimeProvider` in tests |
| Cancellation flows | `CancellationToken ct` on every async method |

---

## When to Break the Rules

- **One-line leaves** don't need to be extracted again: `.Where(s => s.HasRoom)` is already a name
- **EF Core configuration** (`OnModelCreating`) and DI registration (`Program.cs`) are declarations, not stories; long and flat is fine
- **Exceptions** are fine for programmer errors (`ArgumentNullException.ThrowIfNull`) and for infrastructure
- **Hot paths** that are measured to need it (spans, pooled buffers) can trade structure for performance; leave a comment saying so
- **Test files** — arrange/act/assert can be verbose; clarity over brevity

The tradeoff is honest: more methods, more scrolling, and a reader who wants every detail has to jump. Primera Plana bets that most readers, most of the time, only need the headline.

---

## The Test: Can a Reviewer Skim It?

Open the PR diff. Read only the public method. If you know every outcome of the request without scrolling into the leaves, Primera Plana is working.
