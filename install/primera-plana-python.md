# Primera Plana — Python Coding Standards

These are your coding standards. Follow them strictly in all code you write or review.

## Philosophy

Code reads like a newspaper. Public methods are headlines (5-10 lines of named steps). Private helpers are paragraphs (focused, self-contained). Complexity lives in the leaves. The reader decides how deep to go. Optimize for the reviewer who should be able to approve by reading only public methods.

---

## The Three Rules

1. **Headlines are short** — Public methods are a sequence of named steps. No branching logic, no loops, no error-handling plumbing in the headline.
2. **Name the steps** — Method names describe WHAT happens, never HOW. Names read like a story.
3. **Complexity in the leaves** — Error mapping, retries, object construction, comprehensions live in leaf methods that are called but never call others.

---

## Python-Specific Rules

### Forbidden Patterns

- **No bare `except`.** Always catch specific exceptions: `except ValueError as e:`.
- **No mutable default arguments.** Use `None` and create inside the function.
- **No `type: ignore` without explanation.** If you must suppress, add a comment explaining why.
- **No global mutable state.** Module-level constants are fine; module-level mutables are not.
- **No business logic in `__init__`.** Constructors assign dependencies, nothing else.
- **No nested `try/except` in public methods.** Push error handling to leaves.
- **No `isinstance` cascades in headlines.** Extract to a named method or use polymorphism.
- **No star imports (`from module import *`).** Import explicitly.
- **No print statements for logging.** Use the `logging` module.

### Required Patterns

- **Guard clauses + early return** as primary flow control in headlines.
- **Type hints everywhere** — all parameters, return types, and class attributes. Use `T | None` (3.10+) or `Optional[T]`.
- **Frozen dataclasses** for value objects: `@dataclass(frozen=True)`.
- **`_` prefix for private helpers** — every leaf method starts with underscore.
- **ABC (Abstract Base Class)** for interfaces/ports — external boundaries are abstract.
- **Dependency injection via `__init__`** — no module-level singletons for services.
- **Docstrings on public methods only** — private methods are self-documenting via names.
- **f-strings** for string formatting — never `.format()` or `%`.

### Guard Clause Headlines

```python
def execute(self, request: PlaceOrderRequest) -> OrderResult:
    customer = self._resolve_customer(request)
    if customer is None:
        return OrderResult.customer_not_found(request.customer_id)

    subscription = self._find_active_subscription(customer)
    if subscription is None:
        return OrderResult.no_subscription(customer.id)

    stock = self._reserve_stock(subscription)
    if stock is None:
        return OrderResult.insufficient_stock(subscription.blend)

    order = self._build_order(customer, subscription, stock)
    self._persist(order)
    self._notify_fulfillment(order)
    return OrderResult.success(order)
```

---

## Class Layout

```python
# 1. Module-level constants
PROCESS = "place-order"

# 2. Class definition with constructor injection
class PlaceOrderUseCase:
    def __init__(
        self,
        customer_repository: CustomerRepository,
        inventory_service: InventoryService,
        order_repository: OrderRepository,
        clock: Clock,
    ) -> None:
        self._customer_repository = customer_repository
        self._inventory_service = inventory_service
        self._order_repository = order_repository
        self._clock = clock

    # 3. Public methods (THE HEADLINES)
    def execute(self, request: PlaceOrderRequest) -> OrderResult:
        ...

    # 4. Private methods grouped by concern:
    # --- Validation ---
    def _resolve_customer(self, request: PlaceOrderRequest) -> Customer | None:
        ...

    # --- Resolution ---
    def _find_active_subscription(self, customer: Customer) -> Subscription | None:
        ...

    # --- Processing ---
    def _reserve_stock(self, subscription: Subscription) -> ReservedStock | None:
        ...

    # --- Persistence ---
    def _persist(self, order: Order) -> None:
        ...

    # --- Mapping ---
    def _build_order(self, customer: Customer, sub: Subscription, stock: ReservedStock) -> Order:
        ...
```

---

## Error Handling

### Option A: Return types (recommended)

```python
@dataclass(frozen=True)
class OrderResult:
    order: Order | None = None
    error: OrderError | None = None

    @staticmethod
    def success(order: Order) -> "OrderResult":
        return OrderResult(order=order)

    @staticmethod
    def customer_not_found(customer_id: str) -> "OrderResult":
        return OrderResult(error=OrderError.CUSTOMER_NOT_FOUND)
```

Or use an enum-based approach:

```python
class OrderError(Enum):
    CUSTOMER_NOT_FOUND = "customer_not_found"
    NO_SUBSCRIPTION = "no_subscription"
    INSUFFICIENT_STOCK = "insufficient_stock"
    PAYMENT_DECLINED = "payment_declined"
```

### Option B: dry-python/returns (recommended for complex domains)

```python
from returns.result import Result, Success, Failure
from returns.pipeline import flow
from returns.pointfree import bind

def execute(self, request: PlaceOrderRequest) -> Result[Order, OrderFailure]:
    return flow(
        request,
        self._resolve_customer,
        bind(self._find_active_subscription),
        bind(self._reserve_stock),
        bind(self._build_and_persist),
    )

def _resolve_customer(self, request: PlaceOrderRequest) -> Result[Customer, OrderFailure]:
    customer = self._customer_repository.find(request.customer_id)
    if customer is None:
        return Failure(OrderFailure.customer_not_found(request.customer_id))
    return Success(customer)
```

### Guidance

- Never raise exceptions for expected failures. Use return types.
- Reserve exceptions for programming errors and infrastructure failures.
- Push `try/except` into leaf methods that interact with external systems.
- Leaves return `T | None` or `Result[T, E]`. Headlines check and branch.

---

## Data Modeling

### Frozen Dataclasses for Domain Objects

```python
@dataclass(frozen=True)
class Order:
    id: OrderId
    customer_id: CustomerId
    blend: BlendName
    quantity: Grams
    status: OrderStatus
    placed_at: datetime
```

- Always `frozen=True` for domain objects.
- Use `@dataclass` for DTOs and value objects — no plain dicts.
- Slots (`slots=True`) for performance-sensitive objects (Python 3.10+).
- No `Optional` fields without explicit `None` default.

### ABC for Interfaces

```python
from abc import ABC, abstractmethod

class CustomerRepository(ABC):
    @abstractmethod
    def find(self, customer_id: CustomerId) -> Customer | None:
        ...

    @abstractmethod
    def save(self, customer: Customer) -> None:
        ...
```

---

## Testing Standards

### Structure

- One test module per production module.
- Test function names: `test_should_behavior_when_condition`.
- Arrange-Act-Assert with blank line separation.
- No logic in tests.

### Patterns

```python
def test_should_return_order_when_all_steps_succeed():
    # Arrange
    request = a_place_order_request(customer_id=TEST_CUSTOMER_ID)
    given_active_customer(TEST_CUSTOMER_ID)
    given_available_stock(TEST_BLEND)

    # Act
    result = use_case.execute(request)

    # Assert
    assert result.order is not None
    assert result.order.customer_id == TEST_CUSTOMER_ID
```

- **Factory functions** — `a_place_order_request()`, `a_customer()` for test data.
- **Mock boundaries** — mock repositories and external clients (use `unittest.mock` or `pytest-mock`).
- **Fixtures via `@pytest.fixture`** for shared setup.
- **One assertion concept per test.** Multiple asserts are fine if they verify one outcome.
- **No `monkeypatch` for internal methods** — inject dependencies properly.

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Use case class | `VerbNounUseCase` | `PlaceOrderUseCase` |
| Public method | `execute` or domain verb | `execute`, `process_batch` |
| Private validation | `_resolve_*`, `_validate_*` | `_resolve_customer` |
| Private action | `_` + domain verb | `_charge_payment`, `_reserve_stock` |
| Private mapping | `_build_*`, `_map_to_*` | `_build_order`, `_map_to_response` |
| Error type | `*Error` or `*Failure` enum/class | `OrderError`, `OrderFailure` |
| Domain object | `PascalCase` frozen dataclass | `Order`, `Subscription` |
| Factory (tests) | `a_*()` or `an_*()` | `a_place_order_request()` |
| Constants | `UPPER_SNAKE` at module top | `PROCESS = "place-order"` |
| Private attributes | `self._name` | `self._customer_repository` |

---

## Code Review Checklist

When reviewing Python code, verify:

- [ ] Public methods are under 10 lines and read as a sequence of named steps
- [ ] No bare `except` — specific exceptions only
- [ ] All functions have type hints (params + return)
- [ ] Private helpers use `_` prefix
- [ ] Dataclasses are frozen for domain objects
- [ ] Method names describe WHAT, not HOW
- [ ] No exceptions for expected failures — return types used
- [ ] Dependencies injected via `__init__`, not globals
- [ ] Tests follow AAA with factory functions
- [ ] No mutable default arguments
- [ ] ABCs used for external boundaries
