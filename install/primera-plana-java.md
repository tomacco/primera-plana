# Primera Plana — Java Coding Standards

These are your coding standards. Follow them strictly in all code you write or review.

## Philosophy

Code reads like a newspaper. Public methods are headlines (5-10 lines of named steps). Private methods are paragraphs (focused, self-contained). Complexity lives in the leaves. The reader decides how deep to go. Optimize for the reviewer who should be able to approve by reading only public methods.

---

## The Three Rules

1. **Headlines are short** — Public methods are a sequence of named steps. No branching logic, no loops, no error-handling plumbing in the headline.
2. **Name the steps** — Method names describe WHAT happens, never HOW. Names read like a story.
3. **Complexity in the leaves** — Error mapping, retries, object construction, stream operations live in leaf methods that are called but never call others.

---

## Java-Specific Rules

### Forbidden Patterns

- **No exceptions for control flow.** Expected failures return typed results (sealed interfaces, Optional, or Vavr Either). Exceptions are for truly exceptional/unrecoverable situations.
- **No nested Optional chains.** Extract to named private methods.
- **No `null` returns from public methods.** Return `Optional<T>` or a result type.
- **No `if-else` chains in public methods.** Extract branching to a named private method.
- **No field injection (`@Autowired` on fields).** Use constructor injection only.
- **No raw types.** Always parameterize generics.
- **No `instanceof` cascades.** Use polymorphism or pattern matching (Java 17+).
- **No mutable DTOs.** Use records (Java 16+) or immutable classes with builders.

### Required Patterns

- **Guard methods** — Extract each validation into a named private method that returns early or throws.
- **Each method does one thing.** If you can describe it with "and", split it.
- **Constructor injection** for all dependencies.
- **Records** for value objects and DTOs (Java 16+).
- **Sealed interfaces** for domain error types (Java 17+).
- **`final` on local variables** when they won't be reassigned (or use IDE enforcement).
- **Stream operations in leaves** — the headline calls `resolveOrderLines()`, not `.stream().map().filter().collect()`.

### Guard Method Pattern

```java
// YES — named validation methods
public OrderResult placeOrder(PlaceOrderRequest request) {
    var customer = resolveCustomer(request);
    if (customer.isEmpty()) return OrderResult.customerNotFound();

    var subscription = findActiveSubscription(customer.get());
    if (subscription.isEmpty()) return OrderResult.noSubscription();

    var stock = reserveStock(subscription.get());
    if (stock.isEmpty()) return OrderResult.insufficientStock();

    var order = buildOrder(customer.get(), subscription.get(), stock.get());
    persist(order);
    notifyFulfillment(order);
    return OrderResult.success(order);
}

// NO — inline validation logic
public OrderResult placeOrder(PlaceOrderRequest request) {
    var customer = customerRepo.findById(request.getCustomerId());
    if (customer == null || !customer.isActive()) {
        return OrderResult.customerNotFound();
    }
    // ... 40 more lines of mixed validation and logic
}
```

### Class Layout Order

```java
// 1. Static constants
private static final String PROCESS = "place-order";

// 2. Dependencies (final fields, constructor-injected)
private final CustomerRepository customerRepository;
private final Clock clock;

// 3. Constructor

// 4. Public methods (THE HEADLINES)

// 5. Private methods grouped by concern:
// --- Validation ---
// --- Resolution ---
// --- Processing ---
// --- Persistence ---
// --- Mapping ---
```

---

## Error Handling

### Option A: Sealed Interface Result (Java 17+)

```java
public sealed interface OrderResult {
    record Success(Order order) implements OrderResult {}
    record CustomerNotFound(String customerId) implements OrderResult {}
    record PaymentDeclined(String reason) implements OrderResult {}
    record InsufficientStock(String blend) implements OrderResult {}
}
```

### Option B: Vavr Either (recommended for complex domains)

```java
public Either<OrderError, Order> placeOrder(PlaceOrderRequest request) {
    return resolveCustomer(request)
        .flatMap(customer -> findActiveSubscription(customer))
        .flatMap(subscription -> reserveStock(subscription))
        .map(context -> buildAndPersistOrder(context));
}

private Either<OrderError, Customer> resolveCustomer(PlaceOrderRequest request) {
    return Option.ofOptional(customerRepository.findById(request.customerId()))
        .toEither(() -> OrderError.customerNotFound(request.customerId()));
}
```

### Guidance

- Use return types to communicate outcomes. Never throw for expected failures.
- `Optional<T>` is for "might not exist" queries.
- Sealed interfaces or Vavr Either are for "can fail in known ways" operations.
- Reserve exceptions for programming errors and infrastructure failures.

---

## Testing Standards

### Structure

- One test class per production class.
- Test method names: `should_expectedBehavior_when_condition` or `@DisplayName("should ... when ...")`.
- Arrange-Act-Assert with blank lines between sections.
- No logic in tests.

### Patterns

```java
@Test
void should_return_order_when_all_steps_succeed() {
    // Arrange
    var request = aPlaceOrderRequest().withCustomerId(CUSTOMER_ID).build();
    givenActiveCustomer(CUSTOMER_ID);
    givenAvailableStock(BLEND);

    // Act
    var result = useCase.placeOrder(request);

    // Assert
    assertThat(result).isInstanceOf(OrderResult.Success.class);
    assertThat(((OrderResult.Success) result).order().customerId()).isEqualTo(CUSTOMER_ID);
}
```

- **Test builders** — `aPlaceOrderRequest()`, `aCustomer()` — builder methods in test fixtures.
- **Mock boundaries, not internals.** Mock repositories and external clients. Never mock private methods.
- **One assertion concept per test.** Multiple asserts are fine if they verify one logical outcome.
- **Use `@Nested` classes** to group related scenarios.
- **Inject Clock** and control time in tests.

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Use case / Service | `VerbNounService` or `VerbNounUseCase` | `PlaceOrderService` |
| Public method | Domain verb | `placeOrder`, `processBatch` |
| Private validation | `resolve*`, `validate*`, `find*` | `resolveCustomer` |
| Private action | Domain verb | `chargePayment`, `reserveStock` |
| Private mapping | `to*`, `mapTo*`, `build*` | `toOrderLine`, `buildOrder` |
| Error type | `sealed interface *Error` or `*Result` | `OrderResult`, `OrderError` |
| Test fixture | `a*()` or `an*()` builder | `aPlaceOrderRequest()` |
| Constants | `UPPER_SNAKE` static final | `private static final String PROCESS` |

---

## Code Review Checklist

When reviewing Java code, verify:

- [ ] Public methods are under 10 lines and read as a sequence of named steps
- [ ] No exceptions for control flow — failures are return types
- [ ] No nested Optional chains — extracted to named methods
- [ ] Each private method does exactly one thing
- [ ] Method names describe WHAT, not HOW
- [ ] Constructor injection only — no field `@Autowired`
- [ ] Records used for value objects and DTOs
- [ ] Stream operations live in leaf methods, not in the headline
- [ ] Tests follow AAA structure with descriptive names
- [ ] Clock is injected, never `Instant.now()` or `LocalDate.now()`
