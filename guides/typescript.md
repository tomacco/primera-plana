# Primera Plana — TypeScript Guide

Code reads like a newspaper. Public functions are headlines. Private helpers are paragraphs. Complexity lives in the leaves. The reader decides how deep to go.

---

## The Philosophy in Five Rules

1. **Headlines are short** — exported/public functions are 5-10 lines of well-named steps
2. **Name the steps** — function names describe WHAT, not HOW
3. **Complexity in the leaves** — error handling, object construction, logging live in private helpers
4. **The reader's time > the writer's time**
5. **The philosophy works with or without functional error handling** — early returns and Result types are equally valid

---

## TypeScript's Natural Strengths

TypeScript's type system and module system align well with Primera Plana:

- **Early returns** create flat, readable headlines
- **Discriminated unions** model domain errors without exceptions
- **Type narrowing** lets the compiler verify your validation leaves
- **Module-level functions** (not exported) are naturally "private paragraphs"
- **`async/await`** reads sequentially — perfect for newspaper-style flow
- **Zod / io-ts** push validation to the boundary, so the inside stays clean
- **Functional pipelines** (`.map().filter()`) read well when named

---

## Core Patterns

### Early Return as Headlines

The simplest Primera Plana pattern. No nesting, no else chains:

```typescript
async function placeSubscriptionOrder(request: PlaceOrderRequest): Promise<Result<Order, OrderError>> {
  const customer = await resolveActiveCustomer(request.customerId);
  if (!customer) return failure(orderError.customerNotFound(request.customerId));

  const subscription = await findEligibleSubscription(request.subscriptionId, customer);
  if (!subscription) return failure(orderError.subscriptionNotEligible(request.subscriptionId));

  const reserved = await reserveStock(subscription);
  if (!reserved) return failure(orderError.insufficientStock(subscription.blend));

  const order = buildOrder(customer, subscription, reserved);
  await persistOrder(order);
  await notifyFulfillment(order);
  return success(order);
}
```

The reader sees the story: resolve customer, find subscription, reserve stock, build order, persist, notify. Ten lines. Done.

### Result Pattern (No Library Needed)

A lightweight Result type that works without external dependencies:

```typescript
// result.ts — your entire "library"
type Success<T> = { ok: true; value: T };
type Failure<E> = { ok: false; error: E };
type Result<T, E> = Success<T> | Failure<E>;

function success<T>(value: T): Success<T> {
  return { ok: true, value };
}

function failure<E>(error: E): Failure<E> {
  return { ok: false, error };
}
```

This is enough. You don't need a library to write explicit error handling. The discriminated union (`ok: true | false`) gives you type narrowing for free:

```typescript
const result = await placeSubscriptionOrder(request);
if (!result.ok) {
  // TypeScript knows result.error exists here
  return mapToHttpResponse(result.error);
}
// TypeScript knows result.value is an Order here
return { status: 201, body: result.value };
```

### neverthrow / fp-ts — When You Want More

For teams that want chainable operations (the TypeScript equivalent of Arrow in Kotlin):

```typescript
import { ResultAsync, ok, err } from 'neverthrow';

function placeSubscriptionOrder(request: PlaceOrderRequest): ResultAsync<Order, OrderError> {
  return resolveActiveCustomer(request.customerId)
    .andThen((customer) => findEligibleSubscription(request.subscriptionId, customer))
    .andThen((subscription) => reserveStock(subscription))
    .map((reserved) => buildOrder(request, reserved))
    .andThen((order) => persistAndNotify(order));
}
```

Both styles — early-return and chained — are valid Primera Plana. The rule is the same: **name the steps, keep the headline short**.

### Discriminated Unions for Domain Errors

TypeScript's way to model explicit failures:

```typescript
type OrderError =
  | { type: 'customer_not_found'; customerId: string }
  | { type: 'subscription_not_eligible'; subscriptionId: string; reason: string }
  | { type: 'insufficient_stock'; blend: string; requested: number; available: number }
  | { type: 'payment_declined'; reason: string }
  | { type: 'shipment_scheduling_failed'; reason: string };

const orderError = {
  customerNotFound: (customerId: string): OrderError => ({
    type: 'customer_not_found', customerId
  }),
  subscriptionNotEligible: (subscriptionId: string, reason = 'unknown'): OrderError => ({
    type: 'subscription_not_eligible', subscriptionId, reason
  }),
  insufficientStock: (blend: string, requested = 0, available = 0): OrderError => ({
    type: 'insufficient_stock', blend, requested, available
  }),
};
```

### Type Narrowing — Validation as Leaves

Type guards are perfect "leaves" — they do the dirty work so the headline stays clean:

```typescript
function isActiveCustomer(customer: Customer | null): customer is ActiveCustomer {
  return customer !== null && customer.status === 'active' && !customer.isSuspended;
}

function isEligibleForDelivery(subscription: Subscription): boolean {
  const nextDelivery = subscription.nextDeliveryDate;
  const sevenDaysFromNow = addDays(new Date(), 7);
  return subscription.status === 'active' && nextDelivery <= sevenDaysFromNow;
}
```

### Module-Level Functions — Where to Put the Leaves

In TypeScript, you have two options for organizing leaves:

**Option A: Module-level (non-exported) functions** — for functional/service-style code:

```typescript
// place-subscription-order.ts

// HEADLINE — exported
export async function placeSubscriptionOrder(request: PlaceOrderRequest): Promise<Result<Order, OrderError>> {
  // ... headline code
}

// PARAGRAPHS — not exported, not visible outside this module
async function resolveActiveCustomer(customerId: string): Promise<Customer | null> { ... }
async function findEligibleSubscription(id: string, customer: Customer): Promise<Subscription | null> { ... }
async function reserveStock(subscription: Subscription): Promise<ReservedStock | null> { ... }
function buildOrder(customer: Customer, subscription: Subscription, stock: ReservedStock): Order { ... }
```

**Option B: Private methods in classes** — for OOP-style code:

```typescript
export class PlaceSubscriptionOrderService {
  // HEADLINE
  async execute(request: PlaceOrderRequest): Promise<Result<Order, OrderError>> { ... }

  // PARAGRAPHS
  private async resolveActiveCustomer(customerId: string): Promise<Customer | null> { ... }
  private async findEligibleSubscription(id: string, customer: Customer): Promise<Subscription | null> { ... }
  private async reserveStock(subscription: Subscription): Promise<ReservedStock | null> { ... }
  private buildOrder(customer: Customer, subscription: Subscription, stock: ReservedStock): Order { ... }
}
```

Both are valid. Pick whichever fits your codebase conventions.

### Async/Await with Error Boundaries

Push try/catch to the leaves. Headlines stay clean:

```typescript
// HEADLINE — no try/catch
async function processRoastBatch(batchId: string): Promise<Result<CompletedBatch, BatchError>> {
  const batch = await fetchBatch(batchId);
  if (!batch) return failure(batchError.notFound(batchId));
  if (!isInRoastingState(batch)) return failure(batchError.invalidTransition(batch.status));

  const grade = assessQuality(batch.metrics);
  if (!grade.passesMinimum) {
    await handleFailedQA(batch, grade);
    return failure(batchError.failedQualityCheck(batchId, grade));
  }

  const completed = finalizeBatch(batch, grade);
  await persistBatch(completed);
  await updateFarmerRecords(batch.farmerId, grade);
  await notifyLogistics(completed);
  return success(completed);
}

// LEAF — try/catch lives here
async function fetchBatch(batchId: string): Promise<RoastBatch | null> {
  try {
    return await batchRepository.findById(batchId);
  } catch (error) {
    logger.error('Failed to fetch batch', { batchId, error });
    return null;
  }
}
```

### Zod for Boundary Validation

Validate at the boundary. Trust the types inside:

```typescript
import { z } from 'zod';

// THE BOUNDARY — validate incoming data
const PlaceOrderRequestSchema = z.object({
  customerId: z.string().uuid(),
  subscriptionId: z.string().uuid(),
  overrideQuantity: z.number().positive().optional(),
});

type PlaceOrderRequest = z.infer<typeof PlaceOrderRequestSchema>;

// HEADLINE — handler validates at the door, then trusts
export async function handlePlaceOrder(rawBody: unknown): Promise<HttpResponse> {
  const parsed = parseRequest(rawBody);
  if (!parsed.ok) return badRequest(parsed.error);

  const result = await placeSubscriptionOrder(parsed.value);
  return mapToResponse(result);
}

// LEAF — validation lives here
function parseRequest(body: unknown): Result<PlaceOrderRequest, string> {
  const parsed = PlaceOrderRequestSchema.safeParse(body);
  if (!parsed.success) return failure(formatZodError(parsed.error));
  return success(parsed.data);
}
```

### No `any`

`any` is TypeScript's equivalent of force unwrapping — it disables the compiler's ability to help you:

```typescript
// NEVER
function processEvent(event: any) { ... }

// ALWAYS — be explicit about what you have
function processEvent(event: RoastCompletedEvent) { ... }

// If you truly don't know the shape, use unknown and narrow
function processEvent(event: unknown): Result<void, EventError> {
  const parsed = parseEvent(event); // leaf does the validation
  if (!parsed.ok) return parsed;
  return handleParsedEvent(parsed.value);
}
```

### Functional Pipelines — Named

Pipelines are readable when each step has a name:

```typescript
// Hard to review — what does this DO?
const result = orders
  .filter(o => o.status === 'placed' && o.subscription.isActive && daysSince(o.placedAt) < 7)
  .map(o => ({ ...o, priority: o.subscription.tier === 'premium' ? 1 : 2 }))
  .sort((a, b) => a.priority - b.priority || a.placedAt.getTime() - b.placedAt.getTime());

// Primera Plana — named steps
const result = orders
  .filter(isRecentActiveOrder)
  .map(attachPriority)
  .sort(byPriorityThenDate);
```

Extract the predicate and mapper into named functions. The pipeline becomes a headline.

---

## Full Example: Before and After

### placeSubscriptionOrder — Before (Functional Style)

```typescript
export async function placeOrder(customerId: string, subscriptionId: string) {
  const customerResponse = await fetch(`${API_URL}/customers/${customerId}`);
  if (!customerResponse.ok) {
    throw new Error(`Customer not found: ${customerId}`);
  }
  const customer = await customerResponse.json();
  if (customer.status !== 'active') {
    throw new Error(`Customer ${customerId} is not active`);
  }

  const subResponse = await fetch(`${API_URL}/subscriptions/${subscriptionId}`);
  if (!subResponse.ok) {
    throw new Error(`Subscription not found: ${subscriptionId}`);
  }
  const subscription = await subResponse.json();
  if (subscription.customerId !== customerId) {
    throw new Error('Subscription does not belong to customer');
  }
  if (subscription.status !== 'active') {
    throw new Error('Subscription is not active');
  }
  const nextDelivery = new Date(subscription.nextDeliveryDate);
  const sevenDays = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  if (nextDelivery > sevenDays) {
    throw new Error('Too early for next delivery');
  }

  const inventoryResponse = await fetch(`${API_URL}/inventory/check`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ blend: subscription.blend, quantity: subscription.quantity }),
  });
  const inventory = await inventoryResponse.json();
  if (inventory.available < subscription.quantity) {
    throw new Error(`Insufficient stock for ${subscription.blend}`);
  }

  const order = {
    id: crypto.randomUUID(),
    customerId,
    subscriptionId,
    blend: subscription.blend,
    quantity: subscription.quantity,
    roastPreference: subscription.roastPreference,
    shippingAddress: customer.addresses[0],
    status: 'placed',
    placedAt: new Date().toISOString(),
  };

  await fetch(`${API_URL}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(order),
  });

  await fetch(`${API_URL}/notifications/fulfillment`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId: order.id, type: 'new_order' }),
  });

  return order;
}
```

**Problems:**
- 50+ lines in a single function — no skimming possible
- Thrown errors with string messages — no type safety
- HTTP details mixed with business logic
- No domain types — raw strings and `any` from `.json()`
- Impossible to review in a PR

### placeSubscriptionOrder — After (Functional Style)

```typescript
// place-subscription-order.ts

export async function placeSubscriptionOrder(
  request: PlaceOrderRequest,
  deps: OrderDependencies,
): Promise<Result<Order, OrderError>> {
  const customer = await resolveActiveCustomer(request.customerId, deps);
  if (!customer) return failure(orderError.customerNotFound(request.customerId));

  const subscription = await findEligibleSubscription(request.subscriptionId, customer, deps);
  if (!subscription) return failure(orderError.subscriptionNotEligible(request.subscriptionId));

  const reserved = await reserveStock(subscription, deps);
  if (!reserved) return failure(orderError.insufficientStock(subscription.blend));

  const order = buildOrder(customer, subscription, reserved);
  await persistOrder(order, deps);
  await notifyFulfillment(order, deps);
  return success(order);
}

// --- Leaves (not exported) ---

async function resolveActiveCustomer(
  customerId: string,
  { customerRepo, logger }: OrderDependencies,
): Promise<ActiveCustomer | null> {
  try {
    const customer = await customerRepo.findById(customerId);
    if (!customer || !isActiveCustomer(customer)) {
      logger.info('Customer not found or inactive', { customerId });
      return null;
    }
    return customer;
  } catch (error) {
    logger.error('Failed to resolve customer', { customerId, error });
    return null;
  }
}

async function findEligibleSubscription(
  subscriptionId: string,
  customer: ActiveCustomer,
  { subscriptionRepo }: OrderDependencies,
): Promise<EligibleSubscription | null> {
  const subscription = await subscriptionRepo.findById(subscriptionId);
  if (!subscription) return null;
  if (subscription.customerId !== customer.id) return null;
  if (!isEligibleForDelivery(subscription)) return null;
  return subscription as EligibleSubscription;
}

async function reserveStock(
  subscription: EligibleSubscription,
  { inventoryService }: OrderDependencies,
): Promise<ReservedStock | null> {
  return inventoryService.reserve(subscription.blend, subscription.quantity);
}

function buildOrder(
  customer: ActiveCustomer,
  subscription: EligibleSubscription,
  stock: ReservedStock,
): Order {
  return {
    id: generateOrderId(),
    customerId: customer.id,
    subscriptionId: subscription.id,
    blend: subscription.blend,
    quantity: subscription.quantity,
    roastPreference: subscription.roastPreference,
    shippingAddress: customer.defaultAddress,
    reservationId: stock.id,
    status: 'placed',
    placedAt: new Date(),
  };
}

async function persistOrder(order: Order, { orderRepo, logger }: OrderDependencies): Promise<void> {
  try {
    await orderRepo.save(order);
    logger.info('Order persisted', { orderId: order.id });
  } catch (error) {
    logger.error('Failed to persist order', { orderId: order.id, error });
  }
}

async function notifyFulfillment(order: Order, { fulfillmentNotifier }: OrderDependencies): Promise<void> {
  await fulfillmentNotifier.orderPlaced(order);
}
```

**What changed:**
- The exported function is 10 lines — a reviewer reads it in seconds
- Each step has a name that explains itself
- Error handling lives in the leaves (try/catch pushed down)
- Domain errors are typed discriminated unions
- Infrastructure details are behind dependency interfaces
- Non-exported functions are naturally "private paragraphs"

---

### processRoastBatch — Before (Class-Based Style)

```typescript
export class RoastBatchManager {
  async completeBatch(batchId: string) {
    const batch = await this.db.query('SELECT * FROM roast_batches WHERE id = $1', [batchId]);
    if (!batch.rows[0]) throw new Error('Batch not found');
    if (batch.rows[0].status !== 'roasting') throw new Error('Batch not in roasting state');

    const { final_temp, duration_minutes, moisture_pct } = batch.rows[0];
    let grade: string;
    if (final_temp >= 200 && final_temp <= 230 && duration_minutes >= 12 && duration_minutes <= 18 && moisture_pct < 12) {
      grade = 'A';
    } else if (final_temp >= 190 && final_temp <= 240 && duration_minutes >= 10 && duration_minutes <= 20 && moisture_pct < 14) {
      grade = 'B';
    } else {
      grade = 'C';
    }

    if (grade === 'C') {
      await this.emailService.send({
        to: 'quality@tostado.com',
        subject: `Low grade batch ${batchId}`,
        body: `Batch ${batchId} received grade C. Temp: ${final_temp}, Duration: ${duration_minutes}, Moisture: ${moisture_pct}`,
      });
      await this.db.query('UPDATE roast_batches SET status = $1, grade = $2 WHERE id = $3', ['failed_qa', grade, batchId]);
      throw new Error('Batch failed QA');
    }

    await this.db.query('UPDATE roast_batches SET status = $1, grade = $2, completed_at = $3 WHERE id = $4', ['completed', grade, new Date(), batchId]);
    await this.db.query('UPDATE farmer_yields SET total_completed = total_completed + 1, last_batch_grade = $1 WHERE farmer_id = $2', [grade, batch.rows[0].farmer_id]);

    await fetch(`${LOGISTICS_URL}/ready`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ batchId, grade }),
    });

    return { ...batch.rows[0], status: 'completed', grade };
  }
}
```

### processRoastBatch — After (Class-Based Style)

```typescript
// process-roast-batch.service.ts

export class ProcessRoastBatchService {
  constructor(
    private readonly batches: RoastBatchRepository,
    private readonly farmers: FarmerYieldRepository,
    private readonly logistics: LogisticsNotifier,
    private readonly qualityTeam: QualityTeamNotifier,
    private readonly logger: Logger,
  ) {}

  async execute(batchId: string): Promise<Result<CompletedBatch, BatchError>> {
    const batch = await this.fetchBatch(batchId);
    if (!batch) return failure(batchError.notFound(batchId));
    if (!this.isInRoastingState(batch)) return failure(batchError.invalidTransition(batch.status));

    const grade = this.assessQuality(batch.metrics);

    if (!grade.passesMinimum) {
      await this.handleFailedQA(batch, grade);
      return failure(batchError.failedQualityCheck(batchId, grade));
    }

    const completed = this.finalizeBatch(batch, grade);
    await this.persistBatch(completed);
    await this.updateFarmerRecords(batch.farmerId, grade);
    await this.notifyLogistics(completed);
    return success(completed);
  }

  // --- Private methods: the paragraphs ---

  private async fetchBatch(batchId: string): Promise<RoastBatch | null> {
    try {
      return await this.batches.findById(batchId);
    } catch (error) {
      this.logger.error('Failed to fetch batch', { batchId, error });
      return null;
    }
  }

  private isInRoastingState(batch: RoastBatch): boolean {
    return batch.status === 'roasting';
  }

  private assessQuality(metrics: RoastMetrics): QualityGrade {
    if (this.isGradeA(metrics)) return { level: 'A', passesMinimum: true };
    if (this.isGradeB(metrics)) return { level: 'B', passesMinimum: true };
    return { level: 'C', passesMinimum: false };
  }

  private isGradeA(m: RoastMetrics): boolean {
    return m.temperature >= 200 && m.temperature <= 230
      && m.durationMinutes >= 12 && m.durationMinutes <= 18
      && m.moisturePercent < 12;
  }

  private isGradeB(m: RoastMetrics): boolean {
    return m.temperature >= 190 && m.temperature <= 240
      && m.durationMinutes >= 10 && m.durationMinutes <= 20
      && m.moisturePercent < 14;
  }

  private async handleFailedQA(batch: RoastBatch, grade: QualityGrade): Promise<void> {
    await this.qualityTeam.reportFailedBatch(batch, grade);
    await this.batches.updateStatus(batch.id, 'failed_qa');
    this.logger.warn('Batch failed QA', { batchId: batch.id, grade: grade.level });
  }

  private finalizeBatch(batch: RoastBatch, grade: QualityGrade): CompletedBatch {
    return {
      id: batch.id,
      farmerId: batch.farmerId,
      blend: batch.blend,
      quantity: batch.quantity,
      grade,
      metrics: batch.metrics,
      completedAt: new Date(),
    };
  }

  private async persistBatch(batch: CompletedBatch): Promise<void> {
    try {
      await this.batches.save(batch);
    } catch (error) {
      this.logger.error('Failed to persist completed batch', { batchId: batch.id, error });
    }
  }

  private async updateFarmerRecords(farmerId: string, grade: QualityGrade): Promise<void> {
    await this.farmers.recordCompletedBatch(farmerId, grade);
  }

  private async notifyLogistics(batch: CompletedBatch): Promise<void> {
    await this.logistics.batchReady(batch);
  }
}
```

---

### React Hook — The Pattern Applies to Frontend Too

Primera Plana is not just for backend services. React hooks benefit enormously:

#### Before

```typescript
function useSubscriptions() {
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/subscriptions');
      if (!response.ok) throw new Error('Failed to load');
      const data = await response.json();
      const active = data.filter((s: any) => s.status === 'active').sort((a: any, b: any) =>
        new Date(a.nextDeliveryDate).getTime() - new Date(b.nextDeliveryDate).getTime()
      );
      setSubscriptions(active);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, []);

  const pause = useCallback(async (id: string) => {
    try {
      const response = await fetch(`/api/subscriptions/${id}/pause`, { method: 'POST' });
      if (!response.ok) throw new Error('Failed to pause');
      setSubscriptions(prev => prev.filter(s => s.id !== id));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  return { subscriptions, loading, error, pause, reload: load };
}
```

#### After

```typescript
// use-subscriptions.ts — HEADLINES

export function useSubscriptions() {
  const [state, setState] = useState<SubscriptionListState>({ status: 'idle' });
  const api = useSubscriptionApi();

  const load = useCallback(async () => {
    setState({ status: 'loading' });
    const result = await api.fetchActiveSubscriptions();
    setState(mapToState(result));
  }, [api]);

  const pause = useCallback(async (id: string) => {
    const result = await api.pauseSubscription(id);
    handlePauseResult(result, id, setState);
  }, [api]);

  useEffect(() => { load(); }, [load]);

  return { state, pause, reload: load };
}

// --- Leaves (not exported) ---

type SubscriptionListState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'loaded'; subscriptions: ActiveSubscription[] }
  | { status: 'empty' }
  | { status: 'error'; message: string };

function mapToState(result: Result<ActiveSubscription[], SubscriptionError>): SubscriptionListState {
  if (!result.ok) return { status: 'error', message: userFacingMessage(result.error) };
  if (result.value.length === 0) return { status: 'empty' };
  return { status: 'loaded', subscriptions: result.value };
}

function handlePauseResult(
  result: Result<void, SubscriptionError>,
  id: string,
  setState: React.Dispatch<React.SetStateAction<SubscriptionListState>>,
): void {
  if (!result.ok) {
    setState({ status: 'error', message: userFacingMessage(result.error) });
    return;
  }
  setState((prev) => removeFromList(prev, id));
}

function removeFromList(state: SubscriptionListState, id: string): SubscriptionListState {
  if (state.status !== 'loaded') return state;
  const remaining = state.subscriptions.filter((s) => s.id !== id);
  return remaining.length === 0 ? { status: 'empty' } : { status: 'loaded', subscriptions: remaining };
}

function userFacingMessage(error: SubscriptionError): string {
  switch (error.type) {
    case 'network_unavailable': return 'Check your connection and try again.';
    case 'subscription_not_found': return 'This subscription is no longer available.';
    case 'server_error': return 'Something went wrong. Please try again later.';
  }
}
```

The hook's public API reads like a user story. The leaves handle the messy reality of state transitions.

---

## Supporting Types

Good Primera Plana TypeScript uses expressive types:

```typescript
// --- Domain Types ---

interface ActiveCustomer {
  id: string;
  name: string;
  email: string;
  status: 'active';
  defaultAddress: Address;
}

interface EligibleSubscription {
  id: string;
  customerId: string;
  blend: string;
  quantity: number;
  roastPreference: RoastLevel;
  nextDeliveryDate: Date;
  status: 'active';
}

interface RoastMetrics {
  temperature: number;
  durationMinutes: number;
  moisturePercent: number;
}

interface QualityGrade {
  level: 'A' | 'B' | 'C';
  passesMinimum: boolean;
}

// --- Error Types ---

type BatchError =
  | { type: 'batch_not_found'; batchId: string }
  | { type: 'invalid_transition'; currentStatus: string }
  | { type: 'failed_quality_check'; batchId: string; grade: QualityGrade };

// --- Dependency Interfaces ---

interface OrderDependencies {
  customerRepo: CustomerRepository;
  subscriptionRepo: SubscriptionRepository;
  inventoryService: InventoryService;
  orderRepo: OrderRepository;
  fulfillmentNotifier: FulfillmentNotifier;
  logger: Logger;
}
```

---

## Guiding Principles — TypeScript Edition

| Principle | TypeScript Implementation |
|-----------|--------------------------|
| Headlines are short | Early returns + named function calls |
| Name the steps | Function names are verb phrases: `resolveActiveCustomer`, `reserveStock` |
| Complexity in the leaves | Non-exported functions or private methods |
| No `any` | Use `unknown` + type narrowing, or explicit types |
| Explicit errors | Discriminated unions — never thrown strings |
| Interfaces as boundaries | Dependency injection via interfaces |
| Validate at the boundary | Zod/io-ts at the edge, trust types inside |
| Named pipelines | Extract predicates and mappers into named functions |
| `async/await` in headlines | try/catch pushed to the leaves |

---

## When to Break the Rules

- **Truly trivial helpers** (1-2 lines) don't need to be extracted
- **Thrown errors** are fine for truly exceptional cases (programmer bugs, not domain failures)
- **Inline arrow functions** are fine when short and obvious: `.filter(s => s.isActive)`
- **React component JSX** can be longer than 10 lines when the markup is flat and readable
- **Test files** — arrange/act/assert can be verbose; clarity over brevity

---

## The Test: Can a Reviewer Skim It?

Open a PR diff. Read only the exported function or public method. If you understand what the code does without scrolling into the leaves, Primera Plana is working.

The reader's time is always more valuable than the writer's time. Write code that respects that.
