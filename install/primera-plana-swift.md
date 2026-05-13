# Primera Plana — Swift Coding Standards

These are your coding standards. Follow them strictly in all code you write or review.

## Philosophy

Code reads like a newspaper. Public methods are headlines (5-10 lines of named steps). Private methods are paragraphs (focused, self-contained). Complexity lives in the leaves. The reader decides how deep to go. Optimize for the reviewer who should be able to approve by reading only public methods.

---

## The Three Rules

1. **Headlines are short** — Public methods are a sequence of named steps. No branching logic, no loops, no error-handling plumbing in the headline.
2. **Name the steps** — Method names describe WHAT happens, never HOW. Names read like a story.
3. **Complexity in the leaves** — Error mapping, retries, object construction, async details live in leaf methods that are called but never call others.

---

## Swift-Specific Rules

### Forbidden Patterns

- **No force unwrapping (`!`).** Ever. Use `guard let`, `if let`, `??`, or redesign optionality.
- **No `try!` or `as!`.** Use proper error handling or conditional casts.
- **No nested `if let` pyramids.** Use `guard let` with early return.
- **No massive `switch` blocks in public methods.** Extract to a named private method.
- **No God ViewModels.** Split by screen concern. Each ViewModel handles one view.
- **No business logic in Views.** Views call ViewModel methods; logic lives behind the boundary.
- **No implicit dependencies.** Inject via init, not singletons or global access.
- **No `Any` or `AnyObject` in domain code.** Type things properly.

### Required Patterns

- **`guard let` + early return** as the primary flow control in headlines.
- **`Result<Success, Failure>`** for operations that can fail in known ways.
- **Protocols** for all external boundaries (repositories, services, API clients).
- **Extensions** to physically separate headlines from leaves (see layout below).
- **`@Observable` (or `@ObservableObject`)** for ViewModels — never raw published properties scattered in views.
- **Structs** for value types (domain models, DTOs). Classes only when identity/reference semantics are needed.
- **Async/await** for sequential operations — reads top-to-bottom like a newspaper.
- **Enums with associated values** for domain errors — not string errors.

### Guard-Let as Headlines

```swift
func placeOrder(_ request: OrderRequest) async -> Result<Order, OrderError> {
    guard let customer = await resolveCustomer(request.customerId) else {
        return .failure(.customerNotFound(request.customerId))
    }
    guard let subscription = await findActiveSubscription(customer) else {
        return .failure(.noActiveSubscription(customer.id))
    }
    guard let reserved = await reserveStock(subscription) else {
        return .failure(.insufficientStock(subscription.blend))
    }

    let order = buildOrder(customer: customer, subscription: subscription, stock: reserved)
    await persist(order)
    await notifyFulfillment(order)
    return .success(order)
}
```

Each `guard let` is a headline sentence. The reader sees the full story without diving into leaves.

---

## File Layout

### Main file — Headlines

```swift
// PlaceOrderService.swift
final class PlaceOrderService {
    private let customerRepository: CustomerRepository
    private let subscriptionRepository: SubscriptionRepository
    private let inventoryService: InventoryService
    private let orderRepository: OrderRepository

    init(
        customerRepository: CustomerRepository,
        subscriptionRepository: SubscriptionRepository,
        inventoryService: InventoryService,
        orderRepository: OrderRepository
    ) {
        self.customerRepository = customerRepository
        self.subscriptionRepository = subscriptionRepository
        self.inventoryService = inventoryService
        self.orderRepository = orderRepository
    }

    // HEADLINE
    func execute(_ request: OrderRequest) async -> Result<Order, OrderError> {
        guard let customer = await resolveCustomer(request.customerId) else {
            return .failure(.customerNotFound(request.customerId))
        }
        guard let subscription = await findActiveSubscription(customer) else {
            return .failure(.noActiveSubscription(customer.id))
        }
        guard let reserved = await reserveStock(subscription) else {
            return .failure(.insufficientStock(subscription.blend))
        }

        let order = buildOrder(customer: customer, subscription: subscription, stock: reserved)
        await persist(order)
        return .success(order)
    }
}
```

### Extension file — Leaves

```swift
// PlaceOrderService+Leaves.swift
extension PlaceOrderService {
    func resolveCustomer(_ id: CustomerId) async -> Customer? { ... }
    func findActiveSubscription(_ customer: Customer) async -> Subscription? { ... }
    func reserveStock(_ subscription: Subscription) async -> ReservedStock? { ... }
    func buildOrder(customer: Customer, subscription: Subscription, stock: ReservedStock) -> Order { ... }
    func persist(_ order: Order) async { ... }
}
```

For smaller classes, keep everything in one file but maintain the visual separation (headlines at top, leaves below).

---

## Error Handling

### Domain Errors as Enums

```swift
enum OrderError: Error, Equatable {
    case customerNotFound(CustomerId)
    case noActiveSubscription(CustomerId)
    case insufficientStock(BlendName)
    case paymentDeclined(reason: String)
}
```

### Result Type Usage

- Return `Result<T, DomainError>` from service methods.
- Use `.map`, `.flatMap`, `.mapError` in leaves for transformation.
- In the headline, prefer `guard case .success(let value)` or switch at the call site.
- Never `try!` to unwrap Results.

### Async Error Boundaries

Push `do/catch` into the leaves. Headlines stay clean:

```swift
// LEAF — handles the error
private func resolveCustomer(_ id: CustomerId) async -> Customer? {
    do {
        let customer = try await customerRepository.find(id)
        guard customer.isActive else { return nil }
        return customer
    } catch {
        logger.error("Failed to resolve customer \(id): \(error)")
        return nil
    }
}
```

---

## Protocol-Oriented Boundaries

Define boundaries as protocols. This keeps the headline testable and decoupled:

```swift
protocol CustomerRepository {
    func find(_ id: CustomerId) async throws -> Customer?
}

protocol InventoryService {
    func checkAvailability(blend: BlendName, quantity: Grams) async -> Availability
    func reserve(blend: BlendName, quantity: Grams) async -> ReservedStock?
}
```

Mock these in tests. Never mock concrete classes.

---

## ViewModel Pattern

```swift
@Observable
final class OrderViewModel {
    private(set) var state: OrderState = .idle
    private let placeOrderService: PlaceOrderService

    init(placeOrderService: PlaceOrderService) {
        self.placeOrderService = placeOrderService
    }

    // HEADLINE
    func placeOrder(_ request: OrderRequest) async {
        state = .loading
        let result = await placeOrderService.execute(request)
        state = mapToViewState(result)
    }

    // LEAF
    private func mapToViewState(_ result: Result<Order, OrderError>) -> OrderState {
        switch result {
        case .success(let order): return .success(order.summary)
        case .failure(let error): return .error(error.userMessage)
        }
    }
}
```

---

## Testing Standards

### Structure

- One test class per production class.
- Test method names: `test_expectedBehavior_when_condition` or descriptive prose.
- Arrange-Act-Assert with blank line separation.
- No logic in tests.

### Patterns

```swift
@Test
func placeOrder_returnsSuccess_whenAllStepsSucceed() async {
    // Arrange
    let request = anOrderRequest(customerId: testCustomerId)
    stubActiveCustomer(testCustomerId)
    stubAvailableStock(testBlend)

    // Act
    let result = await sut.execute(request)

    // Assert
    guard case .success(let order) = result else {
        Issue.record("Expected success"); return
    }
    #expect(order.customerId == testCustomerId)
}
```

- **Protocol mocks** — create simple structs conforming to protocols for test doubles.
- **Factory methods** — `anOrderRequest()`, `aCustomer()` for test data.
- **One assertion concept per test.**

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Service class | `VerbNounService` | `PlaceOrderService` |
| ViewModel | `ScreenNameViewModel` | `OrderViewModel` |
| Public method | Domain verb or `execute` | `execute`, `placeOrder` |
| Private resolution | `resolve*`, `find*` | `resolveCustomer` |
| Private action | Domain verb | `chargePayment`, `reserveStock` |
| Private mapping | `mapTo*`, `build*` | `mapToViewState`, `buildOrder` |
| Error enum | `*Error` | `OrderError` |
| Protocol | Noun (role name) | `CustomerRepository`, `InventoryService` |

---

## Code Review Checklist

When reviewing Swift code, verify:

- [ ] Public methods are under 10 lines and read as a sequence of named steps
- [ ] No force unwrapping (`!`), no `try!`, no `as!`
- [ ] `guard let` used for early exits, not nested `if let`
- [ ] Method names describe WHAT, not HOW
- [ ] Errors are enums with associated values, not strings
- [ ] Protocols define boundaries — concrete dependencies are injected
- [ ] Extensions separate headlines from leaves (when file is large)
- [ ] ViewModels use `@Observable` and expose state, not scattered publishers
- [ ] Tests use protocol mocks and follow AAA structure
