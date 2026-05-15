# Primera Plana — Kotlin Coding Standards

These are your coding standards. Follow them strictly in all code you write or review.

## Philosophy

Code reads like a newspaper. Public methods are headlines (5-10 lines of named steps). Private methods are paragraphs (focused, self-contained). Complexity lives in the leaves. The reader decides how deep to go. Optimize for the reviewer who should be able to approve by reading only public methods.

---

## The Three Rules

1. **Headlines are short** — Public methods are a sequence of named steps. No branching logic, no loops, no error-handling plumbing in the headline.
2. **Name the steps** — Method names describe WHAT happens, never HOW. Names read like a story.
3. **Complexity in the leaves** — Error mapping, retries, object construction, stream operations live in leaf methods that are called but never call others.

---

## Kotlin-Specific Rules

### Forbidden Patterns

- **No `companion object` for factory methods.** Use top-level functions or named constructors.
- **No `!!` (non-null assertion).** Ever. Use `?: return`, `?: throw`, or redesign the nullability.
- **No `for` loops.** Use `.map`, `.filter`, `.flatMap`, `.forEach`, `.fold`. Collections are declarative.
- **No `Instant.now()` or `Clock.System.now()` directly.** Inject `Clock` and call `clock.instant()`.
- **No `when` blocks in public methods.** Extract to a named private method.
- **No nested `?.let` chains.** Extract to a named method or use early return.
- **No `it` in multi-line lambdas.** Name the parameter.
- **No mutable state in data classes.** Use `val` only. Produce new instances via `.copy()`.

### Required Patterns

- **Expression bodies** for single-expression private methods: `private fun foo() = bar.baz()`
- **Trailing commas** in all parameter lists, constructor calls, and collection literals.
- **Named arguments** when calling functions with more than 2 parameters of the same type.
- **`private const val`** for string constants at file top, not inside classes.
- **Sealed classes/interfaces** for domain error types — never use exceptions for expected failures.
- **Inject dependencies via constructor** — no field injection, no service locators.

### Class Layout Order

```kotlin
// 1. File-level declarations
private val logger = KotlinLogging.logger {}
private const val MAX_RETRIES = 3

// 2. Class declaration with constructor injection
class MyUseCase(
    private val dependency: Dependency,
    private val clock: Clock,
) {
    // 3. Public methods (THE HEADLINES)
    fun execute(request: Request): Result { ... }

    // 4. Private methods grouped by concern with section comments:
    // --- Validation ---
    // --- Resolution ---
    // --- Processing ---
    // --- Persistence ---
    // --- Logging / Mapping ---
}
```

### Expression Body Preference

```kotlin
// YES
private fun resolveCustomer(id: CustomerId) =
    customerRepository.findById(id)

// NO
private fun resolveCustomer(id: CustomerId): Customer? {
    return customerRepository.findById(id)
}
```

---

## Error Handling

### Option A: Nullable + Early Return

```kotlin
fun execute(request: Request): OrderResult {
    val customer = resolveCustomer(request) ?: return OrderResult.NotFound
    val items = resolveItems(request) ?: return OrderResult.InvalidItems
    val payment = processPayment(customer, items) ?: return OrderResult.PaymentFailed
    return confirmOrder(customer, items, payment)
}
```

### Option B: Arrow Either (recommended for complex domains)

```kotlin
fun execute(request: Request): Either<OrderError, Order> = either {
    val customer = resolveCustomer(request).bind()
    val items = resolveItems(request).bind()
    val payment = processPayment(customer, items).bind()
    confirmOrder(customer, items, payment)
}
```

Both are valid. The headline shape is identical.

### Either/Arrow Guidance

- Use `Either<DomainError, T>` as return type for use cases.
- Use `.toEither { }` to convert nullable results.
- Use `Either.catch { }.mapLeft { }` for wrapping external calls.
- Use `.bind()` inside `either { }` blocks — never `.fold()` in the headline.
- Map errors in the leaves: `private fun resolveX(): Either<Error, X> = repo.find().toEither { Error.NotFound }`

---

## Testing Standards

### Structure

- One test class per production class.
- Test method names: `should [expected behavior] when [condition]`.
- Arrange-Act-Assert with blank lines separating each section.
- No logic in tests (no `if`, no loops, no helper methods that assert).

### Patterns

```kotlin
@Test
fun `should return order when all steps succeed`() {
    // Arrange
    val request = aPlaceOrderRequest(customerId = CUSTOMER_ID)
    givenActiveCustomer(CUSTOMER_ID)
    givenAvailableStock(BLEND)

    // Act
    val result = useCase.execute(request)

    // Assert
    result.shouldBeRight()
    result.value.customerId shouldBe CUSTOMER_ID
}
```

- **Use test fixtures** (`aPlaceOrderRequest()`, `aCustomer()`) — named builder functions at file bottom or in a shared `Fixtures.kt`.
- **Mock boundaries, not internals.** Mock repositories, external clients, clocks. Never mock private methods.
- **One assertion concept per test.** Multiple `shouldBe` calls are fine if they verify one logical thing.
- **No `@BeforeEach` logic beyond creating the subject under test.**

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Use case class | `VerbNounUseCase` | `PlaceOrderUseCase` |
| Public method | `execute` or domain verb | `execute`, `process`, `handle` |
| Private validation | `resolve*`, `validate*` | `resolveCustomer` |
| Private action | Domain verb | `chargePayment`, `reserveStock` |
| Private mapping | `to*`, `mapTo*` | `toOrderLine`, `mapToResponse` |
| Error type | `sealed interface *Error` | `sealed interface OrderError` |
| Test fixture | `a*()` or `an*()` | `aPlaceOrderRequest()` |
| Constants | `UPPER_SNAKE` at file top | `private const val MAX_RETRIES = 3` |

---

## Code Review Checklist

When reviewing Kotlin code, verify:

- [ ] Public methods are under 10 lines and read as a sequence of named steps
- [ ] No `!!`, no `companion object` factories, no `for` loops
- [ ] Method names describe WHAT, not HOW
- [ ] `Clock` is injected, never called statically
- [ ] Error types are sealed classes/interfaces, not exceptions
- [ ] Tests follow should/when naming and AAA structure
- [ ] Trailing commas present in multi-line declarations
