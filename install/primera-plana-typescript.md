# Primera Plana — TypeScript Coding Standards

These are your coding standards. Follow them strictly in all code you write or review.

## Philosophy

Code reads like a newspaper. Exported functions are headlines (5-10 lines of named steps). Private helpers are paragraphs (focused, self-contained). Complexity lives in the leaves. The reader decides how deep to go. Optimize for the reviewer who should be able to approve by reading only exported/public functions.

---

## The Three Rules

1. **Headlines are short** — Exported/public functions are a sequence of named steps. No branching logic, no loops, no error-handling plumbing in the headline.
2. **Name the steps** — Function names describe WHAT happens, never HOW. Names read like a story.
3. **Complexity in the leaves** — Error mapping, object construction, validation, API parsing live in helper functions that are called but never call others.

---

## TypeScript-Specific Rules

### Forbidden Patterns

- **No `any`.** Ever. Use `unknown` and narrow, or define proper types.
- **No inline complex logic in headlines.** Extract to named helper functions.
- **No nested ternaries.** Extract to a named function or use early return.
- **No `try/catch` in headlines.** Push error boundaries into leaves.
- **No barrel files re-exporting everything.** Import from the source module.
- **No mutations of function parameters.** Return new objects.
- **No `else` after early returns.** The early return IS the else.
- **No type assertions (`as T`) unless absolutely necessary.** Prefer type guards.
- **No callback hell.** Use async/await.

### Required Patterns

- **Early return** as the primary flow control in headlines.
- **Discriminated unions** for domain error types (`type: 'error_name'`).
- **Named helper functions** — no anonymous logic blocks. Every non-trivial operation gets a name.
- **Type guards** for validation (leaves that narrow types).
- **`readonly` on interface fields** that shouldn't be mutated.
- **Explicit return types** on exported functions.
- **`const` always** — never `let` unless truly reassigned.

### Early Return Headlines

```typescript
export async function placeOrder(request: PlaceOrderRequest): Promise<Result<Order, OrderError>> {
  const customer = await resolveActiveCustomer(request.customerId);
  if (!customer) return failure(orderError.customerNotFound(request.customerId));

  const subscription = await findEligibleSubscription(request.subscriptionId, customer);
  if (!subscription) return failure(orderError.notEligible(request.subscriptionId));

  const reserved = await reserveStock(subscription);
  if (!reserved) return failure(orderError.insufficientStock(subscription.blend));

  const order = buildOrder(customer, subscription, reserved);
  await persistOrder(order);
  await notifyFulfillment(order);
  return success(order);
}
```

---

## Module Organization

### Option A: Module-level functions (preferred for services)

```typescript
// place-order.ts

// HEADLINE — exported
export async function placeOrder(request: PlaceOrderRequest): Promise<Result<Order, OrderError>> {
  // ... headline steps
}

// PARAGRAPHS — not exported
async function resolveActiveCustomer(id: string): Promise<Customer | null> { ... }
async function findEligibleSubscription(id: string, customer: Customer): Promise<Subscription | null> { ... }
async function reserveStock(subscription: Subscription): Promise<ReservedStock | null> { ... }
function buildOrder(customer: Customer, sub: Subscription, stock: ReservedStock): Order { ... }
```

### Option B: Class with private methods

```typescript
export class PlaceOrderService {
  constructor(private readonly deps: PlaceOrderDeps) {}

  // HEADLINE
  async execute(request: PlaceOrderRequest): Promise<Result<Order, OrderError>> { ... }

  // LEAVES
  private async resolveActiveCustomer(id: string): Promise<Customer | null> { ... }
  private async findEligibleSubscription(id: string, customer: Customer): Promise<Subscription | null> { ... }
}
```

Pick whichever fits your codebase. Do not mix within the same module.

---

## Error Handling

### Discriminated Unions

```typescript
type OrderError =
  | { type: 'customer_not_found'; customerId: string }
  | { type: 'not_eligible'; subscriptionId: string; reason: string }
  | { type: 'insufficient_stock'; blend: string }
  | { type: 'payment_declined'; reason: string };
```

### Lightweight Result Type (no library needed)

```typescript
type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

const success = <T>(value: T): Result<T, never> => ({ ok: true, value });
const failure = <E>(error: E): Result<never, E> => ({ ok: false, error });
```

### neverthrow (recommended for complex domains)

```typescript
import { ResultAsync, ok, err } from 'neverthrow';

function placeOrder(request: PlaceOrderRequest): ResultAsync<Order, OrderError> {
  return resolveActiveCustomer(request.customerId)
    .andThen((customer) => findEligibleSubscription(request.subscriptionId, customer))
    .andThen((subscription) => reserveStock(subscription))
    .map((reserved) => buildOrder(request, reserved))
    .andThen((order) => persistAndNotify(order));
}
```

### Guidance

- Never throw for expected failures. Use Result types.
- Reserve `throw` for programming errors only.
- Push `try/catch` (for external SDKs) into leaf functions that return `Result`.
- API boundaries (controllers, handlers) are where you map `Result` to HTTP responses.

---

## React Patterns

### Component Headlines

```typescript
export function OrderPage({ orderId }: OrderPageProps) {
  const order = useOrder(orderId);
  const { placeOrder, isLoading } = usePlaceOrder();

  if (!order) return <OrderSkeleton />;
  if (order.error) return <OrderError error={order.error} />;

  return <OrderDetails order={order.data} onReorder={placeOrder} isLoading={isLoading} />;
}
```

### Hook Rules

- **Custom hooks are headlines.** They orchestrate named operations.
- **`useCallback`** for handlers passed to children (to prevent re-renders).
- **`useRef`** for values that shouldn't trigger re-renders.
- **Cleanup functions** in `useEffect` — always clean up subscriptions, timers, listeners.
- **No `useEffect` for derived state.** Use `useMemo` or compute inline.

### Typed API Wrappers

```typescript
// api/orders.ts — LEAF
async function fetchOrder(id: string): Promise<Result<Order, ApiError>> {
  try {
    const response = await apiClient.get<OrderDTO>(`/orders/${id}`);
    return success(mapToOrder(response.data));
  } catch (error) {
    return failure(mapApiError(error));
  }
}
```

---

## Testing Standards

### Structure

- One test file per module/class.
- Test descriptions: `it('should [behavior] when [condition]')`.
- Arrange-Act-Assert with blank line separation.
- No logic in tests.

### Patterns

```typescript
describe('placeOrder', () => {
  it('should return success when all steps succeed', async () => {
    // Arrange
    const request = aPlaceOrderRequest({ customerId: TEST_CUSTOMER_ID });
    givenActiveCustomer(TEST_CUSTOMER_ID);
    givenAvailableStock(TEST_BLEND);

    // Act
    const result = await placeOrder(request);

    // Assert
    expect(result.ok).toBe(true);
    expect(result.value.customerId).toBe(TEST_CUSTOMER_ID);
  });
});
```

- **Factory functions** — `aPlaceOrderRequest()`, `aCustomer()` for test data.
- **Mock boundaries** — mock API clients and repositories, not internal functions.
- **One concept per test.** Multiple expects are fine if they verify one outcome.

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Service / Use case | `verbNoun` (function) or `VerbNounService` (class) | `placeOrder`, `PlaceOrderService` |
| Exported function | Domain verb | `placeOrder`, `processBatch` |
| Helper (resolution) | `resolve*`, `find*` | `resolveActiveCustomer` |
| Helper (action) | Domain verb | `chargePayment`, `reserveStock` |
| Helper (mapping) | `mapTo*`, `build*`, `to*` | `mapToOrder`, `buildOrder` |
| Error type | `*Error` union | `OrderError` |
| Result constructors | `success`, `failure` | `success(order)` |
| Factory (tests) | `a*()` or `an*()` | `aPlaceOrderRequest()` |
| Constants | `UPPER_SNAKE` | `const MAX_RETRY_COUNT = 3` |
| Types/Interfaces | `PascalCase` | `PlaceOrderRequest`, `OrderError` |

---

## Code Review Checklist

When reviewing TypeScript code, verify:

- [ ] Exported functions are under 10 lines and read as a sequence of named steps
- [ ] No `any` — everything is typed
- [ ] No inline complex logic — extracted to named helpers
- [ ] No `try/catch` in headlines — pushed to leaves
- [ ] Method names describe WHAT, not HOW
- [ ] Errors are discriminated unions, not thrown exceptions
- [ ] Early returns used — no `else` after return
- [ ] React hooks follow rules (cleanup, no effect for derived state, useCallback for handlers)
- [ ] Tests follow AAA structure with factory functions
- [ ] No mutations of parameters — new objects returned
