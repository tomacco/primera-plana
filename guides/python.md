# Primera Plana — Python Guide

Code reads like a newspaper. Public methods are headlines. Private helpers are paragraphs. Complexity lives in the leaves. The reader decides how deep to go.

---

## Python's Natural Alignment

Python already values readability — "Beautiful is better than ugly. Explicit is better than implicit." Primera Plana takes this further. Python's readability tradition focuses on syntax. Primera Plana focuses on **structure**: how you organize logic so a reviewer can understand a 300-line module in seconds, not minutes.

Python's strengths for this philosophy:

- **Early returns** are idiomatic and flat — guard clauses keep the happy path linear
- **Type hints** make intent explicit without runtime overhead
- **Dataclasses** provide clean, typed domain objects with almost no boilerplate
- **`_` prefix convention** creates natural "private paragraphs" without access modifiers
- **Comprehensions** declare intent (transform, filter) without iteration mechanics
- **`@property`** hides computed values behind attribute access — keeps the headline clean
- **Walrus operator `:=`** lets you assign-and-test inline for compact guards

---

## Part 1: The Headline Pattern

The same use cases, two styles. The philosophy is identical — only the error plumbing changes.

### The Domain: Tostado

Tostado is a specialty coffee subscription service. Customers place recurring orders for roasted beans. The roastery processes batches. Shipments are matched to orders on delivery.

---

### create_subscription_order

#### Early Return Style (Pythonic)

```python
logger = structlog.get_logger(__name__)


class CreateSubscriptionOrderUseCase:
    def __init__(
        self,
        subscription_finder: SubscriptionFinder,
        inventory_checker: InventoryChecker,
        payment_processor: PaymentProcessor,
        order_repository: OrderRepository,
        clock: Clock,
    ) -> None:
        self._subscription_finder = subscription_finder
        self._inventory_checker = inventory_checker
        self._payment_processor = payment_processor
        self._order_repository = order_repository
        self._clock = clock

    def execute(self, request: PlaceOrderRequest) -> Optional[SubscriptionOrder]:
        subscription = self._resolve_subscription(request)
        if subscription is None:
            return None

        roast = self._resolve_available_roast(subscription)
        if roast is None:
            return None

        payment = self._process_payment(subscription, roast)
        if payment is None:
            return None

        return self._save_order(subscription, roast, payment)

    # --- Validation ---

    def _resolve_subscription(self, request: PlaceOrderRequest) -> Optional[Subscription]:
        subscription = self._subscription_finder.find_active(request.customer_id)
        if subscription is None:
            logger.info("Order skipped", customer_id=request.customer_id, reason="no active subscription")
            return None
        return subscription

    # --- Resolution ---

    def _resolve_available_roast(self, subscription: Subscription) -> Optional[Roast]:
        roast = self._inventory_checker.find_available_roast(
            subscription.preferred_origin,
            subscription.roast_level,
        )
        if roast is None:
            logger.info("Order skipped", customer_id=subscription.customer_id, reason="roast unavailable")
            return None
        return roast

    def _process_payment(self, subscription: Subscription, roast: Roast) -> Optional[PaymentConfirmation]:
        try:
            return self._payment_processor.charge(subscription.payment_method, roast.price)
        except PaymentError as e:
            logger.warning("Payment failed", customer_id=subscription.customer_id, error=str(e))
            return None

    # --- Persistence ---

    def _save_order(
        self,
        subscription: Subscription,
        roast: Roast,
        payment: PaymentConfirmation,
    ) -> SubscriptionOrder:
        order = SubscriptionOrder(
            id=OrderId.generate(),
            customer_id=subscription.customer_id,
            roast_id=roast.id,
            payment_id=payment.id,
            placed_at=self._clock.now(),
        )
        self._order_repository.save(order)
        return order
```

The headline (`execute`) is nine lines. A reviewer reads those nine lines and understands the entire flow. If payment logic is wrong, they scroll to `_process_payment`. The structure is self-navigating.

#### dry-python/returns Style

```python
from returns.result import Result, Success, Failure
from returns.pipeline import flow
from returns.pointfree import bind

logger = structlog.get_logger(__name__)


class CreateSubscriptionOrderUseCase:
    def __init__(
        self,
        subscription_finder: SubscriptionFinder,
        inventory_checker: InventoryChecker,
        payment_processor: PaymentProcessor,
        order_repository: OrderRepository,
        clock: Clock,
    ) -> None:
        self._subscription_finder = subscription_finder
        self._inventory_checker = inventory_checker
        self._payment_processor = payment_processor
        self._order_repository = order_repository
        self._clock = clock

    def execute(self, request: PlaceOrderRequest) -> Result[SubscriptionOrder, OrderFailure]:
        return flow(
            request,
            self._resolve_subscription,
            bind(self._resolve_available_roast),
            bind(self._process_payment),
            bind(self._save_order),
        )

    # --- Resolution ---

    def _resolve_subscription(self, request: PlaceOrderRequest) -> Result[Subscription, OrderFailure]:
        subscription = self._subscription_finder.find_active(request.customer_id)
        if subscription is None:
            return Failure(OrderFailure.no_active_subscription(request.customer_id))
        return Success(subscription)

    def _resolve_available_roast(self, subscription: Subscription) -> Result[RoastContext, OrderFailure]:
        roast = self._inventory_checker.find_available_roast(
            subscription.preferred_origin,
            subscription.roast_level,
        )
        if roast is None:
            return Failure(OrderFailure.roast_unavailable(subscription.preferred_origin))
        return Success(RoastContext(subscription=subscription, roast=roast))

    # --- Processing ---

    def _process_payment(self, context: RoastContext) -> Result[PaymentContext, OrderFailure]:
        try:
            payment = self._payment_processor.charge(
                context.subscription.payment_method,
                context.roast.price,
            )
            return Success(PaymentContext(
                subscription=context.subscription,
                roast=context.roast,
                payment=payment,
            ))
        except PaymentError as e:
            return Failure(OrderFailure.payment_failed(context.subscription.customer_id, str(e)))

    # --- Persistence ---

    def _save_order(self, context: PaymentContext) -> Result[SubscriptionOrder, OrderFailure]:
        order = SubscriptionOrder(
            id=OrderId.generate(),
            customer_id=context.subscription.customer_id,
            roast_id=context.roast.id,
            payment_id=context.payment.id,
            placed_at=self._clock.now(),
        )
        self._order_repository.save(order)
        return Success(order)
```

Same newspaper structure. The headline (`execute`) is a `flow()` pipeline of named steps. Each step is a private method. The reader controls their depth.

---

### process_roast_batch

#### Early Return Style

```python
logger = structlog.get_logger(__name__)


class ProcessRoastBatchUseCase:
    def __init__(
        self,
        batch_queue: BatchQueue,
        temperature_monitor: TemperatureMonitor,
        quality_grader: QualityGrader,
        batch_repository: BatchRepository,
        clock: Clock,
    ) -> None:
        self._batch_queue = batch_queue
        self._temperature_monitor = temperature_monitor
        self._quality_grader = quality_grader
        self._batch_repository = batch_repository
        self._clock = clock

    def execute(self, batch_id: BatchId) -> Optional[CompletedBatch]:
        batch = self._resolve_pending_batch(batch_id)
        if batch is None:
            return None

        profile = self._capture_temperature_profile(batch)
        if profile is None:
            return None

        grading = self._perform_quality_check(batch, profile)
        if grading is None:
            return None

        return self._complete_batch(batch, grading)

    # --- Validation ---

    def _resolve_pending_batch(self, batch_id: BatchId) -> Optional[RoastBatch]:
        batch = self._batch_queue.find_pending(batch_id)
        if batch is None:
            logger.warning("Batch skipped", batch_id=batch_id, reason="not found or already processed")
            return None
        return batch

    # --- Resolution ---

    def _capture_temperature_profile(self, batch: RoastBatch) -> Optional[RoastProfile]:
        profile = self._temperature_monitor.capture_profile(batch.id)
        if profile.peak_temperature not in batch.target_range:
            logger.warning("Batch skipped", batch_id=batch.id, reason="temperature outside target range")
            return None
        return profile

    def _perform_quality_check(self, batch: RoastBatch, profile: RoastProfile) -> Optional[QualityGrading]:
        grading = self._quality_grader.grade(batch.origin, profile)
        if grading.score < batch.minimum_grade:
            logger.warning("Batch skipped", batch_id=batch.id, reason="quality below threshold")
            return None
        return grading

    # --- Persistence ---

    def _complete_batch(self, batch: RoastBatch, grading: QualityGrading) -> CompletedBatch:
        completed = CompletedBatch(
            id=batch.id,
            origin=batch.origin,
            grade=grading.score,
            completed_at=self._clock.now(),
        )
        self._batch_repository.save(completed)
        return completed
```

#### dry-python/returns Style

```python
from returns.result import Result, Success, Failure
from returns.pipeline import flow
from returns.pointfree import bind

logger = structlog.get_logger(__name__)


class ProcessRoastBatchUseCase:
    def __init__(
        self,
        batch_queue: BatchQueue,
        temperature_monitor: TemperatureMonitor,
        quality_grader: QualityGrader,
        batch_repository: BatchRepository,
        clock: Clock,
    ) -> None:
        self._batch_queue = batch_queue
        self._temperature_monitor = temperature_monitor
        self._quality_grader = quality_grader
        self._batch_repository = batch_repository
        self._clock = clock

    def execute(self, batch_id: BatchId) -> Result[CompletedBatch, BatchFailure]:
        return flow(
            batch_id,
            self._resolve_pending_batch,
            bind(self._capture_temperature_profile),
            bind(self._perform_quality_check),
            bind(self._complete_batch),
        )

    # --- Validation ---

    def _resolve_pending_batch(self, batch_id: BatchId) -> Result[RoastBatch, BatchFailure]:
        batch = self._batch_queue.find_pending(batch_id)
        if batch is None:
            return Failure(BatchFailure.not_found(batch_id))
        return Success(batch)

    # --- Resolution ---

    def _capture_temperature_profile(self, batch: RoastBatch) -> Result[ProfileContext, BatchFailure]:
        profile = self._temperature_monitor.capture_profile(batch.id)
        if profile.peak_temperature not in batch.target_range:
            return Failure(BatchFailure.temperature_out_of_range(batch.id, profile.peak_temperature))
        return Success(ProfileContext(batch=batch, profile=profile))

    def _perform_quality_check(self, context: ProfileContext) -> Result[GradingContext, BatchFailure]:
        grading = self._quality_grader.grade(context.batch.origin, context.profile)
        if grading.score < context.batch.minimum_grade:
            return Failure(BatchFailure.quality_below_threshold(context.batch.id, grading.score))
        return Success(GradingContext(batch=context.batch, grading=grading))

    # --- Persistence ---

    def _complete_batch(self, context: GradingContext) -> Result[CompletedBatch, BatchFailure]:
        completed = CompletedBatch(
            id=context.batch.id,
            origin=context.batch.origin,
            grade=context.grading.score,
            completed_at=self._clock.now(),
        )
        self._batch_repository.save(completed)
        return Success(completed)
```

---

### ship_order

#### Early Return Style

```python
logger = structlog.get_logger(__name__)


class ShipOrderUseCase:
    def __init__(
        self,
        order_finder: OrderFinder,
        address_validator: AddressValidator,
        shipping_provider: ShippingProvider,
        shipment_repository: ShipmentRepository,
        notification_sender: NotificationSender,
        clock: Clock,
    ) -> None:
        self._order_finder = order_finder
        self._address_validator = address_validator
        self._shipping_provider = shipping_provider
        self._shipment_repository = shipment_repository
        self._notification_sender = notification_sender
        self._clock = clock

    def execute(self, order_id: OrderId) -> Optional[Shipment]:
        order = self._resolve_ready_order(order_id)
        if order is None:
            return None

        address = self._validate_delivery_address(order)
        if address is None:
            return None

        label = self._request_shipping_label(order, address)
        if label is None:
            return None

        shipment = self._record_shipment(order, label)
        self._notify_customer(shipment)
        return shipment

    # --- Validation ---

    def _resolve_ready_order(self, order_id: OrderId) -> Optional[SubscriptionOrder]:
        order = self._order_finder.find_ready_to_ship(order_id)
        if order is None:
            logger.info("Shipment skipped", order_id=order_id, reason="not ready to ship")
            return None
        return order

    def _validate_delivery_address(self, order: SubscriptionOrder) -> Optional[ValidatedAddress]:
        result = self._address_validator.validate(order.delivery_address)
        if not result.is_valid:
            logger.warning("Shipment skipped", order_id=order.id, reason=f"invalid address: {result.reason}")
            return None
        return result.validated_address

    # --- Resolution ---

    def _request_shipping_label(self, order: SubscriptionOrder, address: ValidatedAddress) -> Optional[ShippingLabel]:
        try:
            return self._shipping_provider.create_label(
                origin=order.warehouse_location,
                destination=address,
                weight=order.total_weight,
            )
        except ShippingProviderError as e:
            logger.error("Label generation failed", order_id=order.id, error=str(e))
            return None

    # --- Persistence ---

    def _record_shipment(self, order: SubscriptionOrder, label: ShippingLabel) -> Shipment:
        shipment = Shipment(
            id=ShipmentId.generate(),
            order_id=order.id,
            tracking_code=label.tracking_code,
            carrier=label.carrier,
            shipped_at=self._clock.now(),
        )
        self._shipment_repository.save(shipment)
        return shipment

    # --- Side effects ---

    def _notify_customer(self, shipment: Shipment) -> None:
        self._notification_sender.send_shipment_confirmation(shipment)
```

#### dry-python/returns Style

```python
from returns.result import Result, Success, Failure
from returns.pipeline import flow
from returns.pointfree import bind

logger = structlog.get_logger(__name__)


class ShipOrderUseCase:
    def __init__(
        self,
        order_finder: OrderFinder,
        address_validator: AddressValidator,
        shipping_provider: ShippingProvider,
        shipment_repository: ShipmentRepository,
        notification_sender: NotificationSender,
        clock: Clock,
    ) -> None:
        self._order_finder = order_finder
        self._address_validator = address_validator
        self._shipping_provider = shipping_provider
        self._shipment_repository = shipment_repository
        self._notification_sender = notification_sender
        self._clock = clock

    def execute(self, order_id: OrderId) -> Result[Shipment, ShipmentFailure]:
        return flow(
            order_id,
            self._resolve_ready_order,
            bind(self._validate_delivery_address),
            bind(self._request_shipping_label),
            bind(self._record_shipment),
            bind(self._notify_and_return),
        )

    # --- Validation ---

    def _resolve_ready_order(self, order_id: OrderId) -> Result[SubscriptionOrder, ShipmentFailure]:
        order = self._order_finder.find_ready_to_ship(order_id)
        if order is None:
            return Failure(ShipmentFailure.not_ready(order_id))
        return Success(order)

    def _validate_delivery_address(self, order: SubscriptionOrder) -> Result[AddressContext, ShipmentFailure]:
        result = self._address_validator.validate(order.delivery_address)
        if not result.is_valid:
            return Failure(ShipmentFailure.invalid_address(order.id, result.reason))
        return Success(AddressContext(order=order, address=result.validated_address))

    # --- Resolution ---

    def _request_shipping_label(self, context: AddressContext) -> Result[LabelContext, ShipmentFailure]:
        try:
            label = self._shipping_provider.create_label(
                origin=context.order.warehouse_location,
                destination=context.address,
                weight=context.order.total_weight,
            )
            return Success(LabelContext(order=context.order, label=label))
        except ShippingProviderError as e:
            return Failure(ShipmentFailure.label_creation_failed(context.order.id, str(e)))

    # --- Persistence ---

    def _record_shipment(self, context: LabelContext) -> Result[Shipment, ShipmentFailure]:
        shipment = Shipment(
            id=ShipmentId.generate(),
            order_id=context.order.id,
            tracking_code=context.label.tracking_code,
            carrier=context.label.carrier,
            shipped_at=self._clock.now(),
        )
        self._shipment_repository.save(shipment)
        return Success(shipment)

    # --- Side effects ---

    def _notify_and_return(self, shipment: Shipment) -> Result[Shipment, ShipmentFailure]:
        self._notification_sender.send_shipment_confirmation(shipment)
        return Success(shipment)
```

**The takeaway:** Whether you use `if x is None: return None` or `flow()` with `bind()`, the structure is identical. Short headline. Named steps. Complexity in the leaves. The philosophy is the constant — the error handling mechanism is a variable.

---

## Part 2: Python-Specific Rules

These rules make Python code follow Primera Plana. They work with Python's strengths rather than against them.

### 1. Guard clauses first

All validation and early exits live at the top of the function. The happy path flows linearly downward. No nested `else` blocks. No late returns buried in conditionals.

```python
# Primera Plana — guards at the top, happy path below
def execute(self, request: PlaceOrderRequest) -> Optional[SubscriptionOrder]:
    if request.customer_id is None:
        return None

    subscription = self._resolve_subscription(request)
    if subscription is None:
        return None

    if not subscription.is_eligible_for_order():
        return None

    roast = self._resolve_available_roast(subscription)
    if roast is None:
        return None

    return self._fulfill_order(subscription, roast)


# Banned — nested conditionals, late returns
def execute(self, request: PlaceOrderRequest) -> Optional[SubscriptionOrder]:
    if request.customer_id is not None:
        subscription = self._resolve_subscription(request)
        if subscription is not None:
            if subscription.is_eligible_for_order():
                roast = self._resolve_available_roast(subscription)
                if roast is not None:
                    return self._fulfill_order(subscription, roast)
    return None
```

The first version reads top-to-bottom. Each guard clause eliminates one failure case. The reader knows: if execution reaches line 15, all preconditions are met.

---

### 2. Extract named helpers

Private methods with `_` prefix are the paragraphs of your newspaper. Each one handles a single concern and has a name that describes WHAT it does, never HOW.

```python
# Primera Plana — named helpers describe intent
class ProcessRoastBatchUseCase:

    def execute(self, batch_id: BatchId) -> Optional[CompletedBatch]:
        batch = self._resolve_pending_batch(batch_id)
        if batch is None:
            return None

        profile = self._capture_temperature_profile(batch)
        if profile is None:
            return None

        return self._finalize_batch(batch, profile)

    def _resolve_pending_batch(self, batch_id: BatchId) -> Optional[RoastBatch]:
        ...

    def _capture_temperature_profile(self, batch: RoastBatch) -> Optional[RoastProfile]:
        ...

    def _finalize_batch(self, batch: RoastBatch, profile: RoastProfile) -> CompletedBatch:
        ...


# Banned — everything inlined, no named steps
class ProcessRoastBatchUseCase:

    def execute(self, batch_id: BatchId) -> Optional[CompletedBatch]:
        batch = self._batch_queue.find_pending(batch_id)
        if batch is None:
            logger.warning(f"Batch {batch_id} not found")
            return None
        profile = self._temperature_monitor.capture_profile(batch.id)
        if profile.peak_temperature not in batch.target_range:
            logger.warning(f"Temperature {profile.peak_temperature} outside range")
            return None
        completed = CompletedBatch(
            id=batch.id, origin=batch.origin, grade=..., completed_at=...
        )
        self._batch_repository.save(completed)
        return completed
```

---

### 3. No deep nesting

If you are three indentation levels deep inside a method body, extract a helper. Nested code forces the reader to maintain a mental stack. Flat code reads linearly.

```python
# Primera Plana — flat, each concern extracted
def _assign_batches_to_orders(self, orders: list[SubscriptionOrder]) -> list[Assignment]:
    eligible_orders = self._filter_eligible(orders)
    available_batches = self._find_available_batches(eligible_orders)
    return self._match_orders_to_batches(eligible_orders, available_batches)

def _filter_eligible(self, orders: list[SubscriptionOrder]) -> list[SubscriptionOrder]:
    return [order for order in orders if order.status == OrderStatus.PENDING]

def _find_available_batches(self, orders: list[SubscriptionOrder]) -> dict[Origin, list[RoastBatch]]:
    origins = {order.preferred_origin for order in orders}
    return {origin: self._batch_finder.find_available(origin) for origin in origins}

def _match_orders_to_batches(
    self,
    orders: list[SubscriptionOrder],
    batches: dict[Origin, list[RoastBatch]],
) -> list[Assignment]:
    return [
        Assignment(order=order, batch=batches[order.preferred_origin][0])
        for order in orders
        if batches.get(order.preferred_origin)
    ]


# Banned — three levels deep, reader loses track
def _assign_batches_to_orders(self, orders: list[SubscriptionOrder]) -> list[Assignment]:
    assignments = []
    for order in orders:
        if order.status == OrderStatus.PENDING:
            batches = self._batch_finder.find_available(order.preferred_origin)
            if batches:
                for batch in batches:
                    if batch.remaining_capacity >= order.quantity:
                        assignments.append(Assignment(order=order, batch=batch))
                        break
    return assignments
```

---

### 4. Type hints everywhere

Type annotations make the newspaper style explicit. `Optional[Order]` in a return type tells the reader "this can fail" without reading the body. Type hints are the headline's subtitle — they preview the shape of the story.

```python
# Primera Plana — types tell the story before you read the body
def _resolve_subscription(self, request: PlaceOrderRequest) -> Optional[Subscription]:
    ...

def _calculate_pricing(self, roast: Roast, quantity: int) -> PricingBreakdown:
    ...

def _process_payment(
    self,
    subscription: Subscription,
    pricing: PricingBreakdown,
) -> Optional[PaymentConfirmation]:
    ...

def execute(self, batch_id: BatchId) -> Result[CompletedBatch, BatchFailure]:
    ...
```

A reviewer scanning just the signatures knows: `_resolve_subscription` might fail (Optional), `_calculate_pricing` always succeeds (no Optional), and `_process_payment` might fail for payment-specific reasons.

---

### 5. No bare except

Bare `except:` swallows everything — including `KeyboardInterrupt` and `SystemExit`. It is the Python equivalent of Kotlin's `!!`: it hides information the debugger needs at 3 AM.

```python
# Primera Plana — explicit error types, meaningful handling
def _process_payment(self, subscription: Subscription, roast: Roast) -> Optional[PaymentConfirmation]:
    try:
        return self._payment_processor.charge(subscription.payment_method, roast.price)
    except PaymentDeclinedError as e:
        logger.warning("Payment declined", customer_id=subscription.customer_id, reason=e.reason)
        return None
    except PaymentProviderTimeoutError as e:
        logger.error("Payment timeout", customer_id=subscription.customer_id)
        raise  # Let the caller decide on retries


# Banned — bare except hides everything
def _process_payment(self, subscription: Subscription, roast: Roast) -> Optional[PaymentConfirmation]:
    try:
        return self._payment_processor.charge(subscription.payment_method, roast.price)
    except:
        return None
```

**The rule:** If you catch an exception, name it. If you cannot name it, you do not understand what you are catching.

---

### 6. Dataclasses for domain objects

Dataclasses give you typed, immutable (with `frozen=True`) domain objects with no ceremony. They make the domain vocabulary explicit and the data shapes scannable.

```python
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal


@dataclass(frozen=True)
class Roast:
    id: RoastId
    origin: Origin
    level: RoastLevel
    stock: int
    price: Decimal


@dataclass(frozen=True)
class SubscriptionOrder:
    id: OrderId
    customer_id: CustomerId
    roast_id: RoastId
    payment_id: PaymentId
    placed_at: datetime


@dataclass(frozen=True)
class QualityGrading:
    batch_id: BatchId
    score: float
    taster_notes: str
    graded_at: datetime
```

Use `frozen=True` by default. Immutable objects are safer to pass between methods — no spooky mutation at a distance. Create new instances with `dataclasses.replace()` when you need variations:

```python
completed = dataclasses.replace(
    batch,
    status=BatchStatus.COMPLETED,
    grade=grading.score,
    completed_at=self._clock.now(),
)
```

---

### 7. Walrus operator `:=` for inline assignment

The walrus operator lets you assign and test in one expression. It keeps guard clauses compact — especially useful when the assignment itself is the test.

```python
# Primera Plana — walrus keeps guards compact
def execute(self, request: PlaceOrderRequest) -> Optional[SubscriptionOrder]:
    if (subscription := self._resolve_subscription(request)) is None:
        return None

    if (roast := self._resolve_available_roast(subscription)) is None:
        return None

    if (payment := self._process_payment(subscription, roast)) is None:
        return None

    return self._save_order(subscription, roast, payment)
```

Use the walrus operator when:
- The assignment and the check are a single logical guard
- The variable is used immediately after the check
- It reduces visual noise without reducing clarity

Avoid when:
- The expression is complex — readability trumps brevity
- Nested walrus expressions — never stack them

---

### 8. No mutable default arguments

Mutable default arguments are shared across all calls — a classic Python trap that creates bugs invisible in code review. This is Python's version of Kotlin's fake-nullable dependencies: it looks right but silently corrupts state.

```python
# Primera Plana — None sentinel, create fresh in body
def _build_order(
    self,
    subscription: Subscription,
    roast: Roast,
    tags: Optional[list[str]] = None,
) -> SubscriptionOrder:
    resolved_tags = tags if tags is not None else []
    return SubscriptionOrder(
        id=OrderId.generate(),
        customer_id=subscription.customer_id,
        roast_id=roast.id,
        tags=resolved_tags,
        placed_at=self._clock.now(),
    )


# Banned — mutable default shared across invocations
def _build_order(
    self,
    subscription: Subscription,
    roast: Roast,
    tags: list[str] = [],  # This list is shared! Mutations persist!
) -> SubscriptionOrder:
    ...
```

---

### 9. Prefer comprehensions over manual loops

Comprehensions declare intent (transform, filter, aggregate) without exposing iteration mechanics. Like Kotlin's `.map` and `.filter`, they constrain what the reader needs to consider.

```python
# Primera Plana — intent is declared
eligible_beans = [bean for bean in beans if bean.harvest_date > cutoff_date]
roast_ids = {order.roast_id for order in pending_orders}
price_by_origin = {roast.origin: roast.price for roast in catalog}
total_weight = sum(bag.weight_grams for bag in shipment.bags)
first_available = next((roast for roast in inventory if roast.stock > 0), None)


# Banned — mechanism without intent
eligible_beans = []
for bean in beans:
    if bean.harvest_date > cutoff_date:
        eligible_beans.append(bean)
```

| Intent | Use |
|--------|-----|
| Transform each item | `[f(x) for x in items]` |
| Keep matching items | `[x for x in items if pred(x)]` |
| Find first match | `next((x for x in items if pred(x)), None)` |
| Unique values | `{x.attr for x in items}` |
| Build a lookup | `{x.key: x.value for x in items}` |
| Accumulate | `sum(x.amount for x in items)` |
| Check if any match | `any(pred(x) for x in items)` |
| Check if all match | `all(pred(x) for x in items)` |

When a comprehension gets complex (nested conditions, multiple transformations), extract a helper function. A comprehension should fit on one mental line.

---

### 10. @property for computed values

`@property` lets you expose computed values as attributes — keeping the headline clean by hiding the computation behind a simple access.

```python
@dataclass
class Subscription:
    customer_id: CustomerId
    preferred_origin: Origin
    roast_level: RoastLevel
    frequency_days: int
    last_order_date: Optional[datetime]
    status: SubscriptionStatus

    @property
    def is_due_for_order(self) -> bool:
        if self.last_order_date is None:
            return True
        days_since = (datetime.now() - self.last_order_date).days
        return days_since >= self.frequency_days

    @property
    def is_active(self) -> bool:
        return self.status == SubscriptionStatus.ACTIVE


# In the headline, it reads cleanly:
def _filter_due_subscriptions(self, subscriptions: list[Subscription]) -> list[Subscription]:
    return [sub for sub in subscriptions if sub.is_active and sub.is_due_for_order]
```

Properties are for cheap, synchronous, side-effect-free computations. If it hits the database or could raise, make it a method.

---

## Part 3: Class Layout

Python's version of the newspaper structure. Each layer is more detailed than the one above. The reader scrolls deeper only when they need to.

```python
# ===== 1. Module-level constants =====
logger = structlog.get_logger(__name__)
MAX_RETRY_ATTEMPTS = 3
ELIGIBLE_STATUSES = frozenset({SubscriptionStatus.ACTIVE, SubscriptionStatus.RESUMING})


# ===== 2. Class with __init__ (dependencies) =====
class FulfillSubscriptionUseCase:
    def __init__(
        self,
        subscription_finder: SubscriptionFinder,
        inventory_service: InventoryService,
        roast_scheduler: RoastScheduler,
        order_repository: OrderRepository,
        notification_sender: NotificationSender,
        feature_flags: FeatureFlags,
        clock: Clock,
    ) -> None:
        self._subscription_finder = subscription_finder
        self._inventory_service = inventory_service
        self._roast_scheduler = roast_scheduler
        self._order_repository = order_repository
        self._notification_sender = notification_sender
        self._feature_flags = feature_flags
        self._clock = clock

    # ===== 3. Public methods (the headlines) =====
    def execute(self, customer_id: CustomerId) -> Optional[SubscriptionOrder]:
        if not self._feature_flags.is_auto_fulfillment_enabled():
            return None

        subscription = self._resolve_eligible_subscription(customer_id)
        if subscription is None:
            return None

        roast = self._resolve_preferred_roast(subscription)
        if roast is None:
            return None

        scheduled_batch = self._schedule_roast(roast, subscription)
        if scheduled_batch is None:
            return None

        order = self._place_order(subscription, scheduled_batch)
        self._notify_customer(subscription, scheduled_batch)
        return order

    # ===== 4. Private validation helpers =====
    def _resolve_eligible_subscription(self, customer_id: CustomerId) -> Optional[Subscription]:
        subscription = self._subscription_finder.find_by_customer(customer_id)
        if subscription is None or subscription.status not in ELIGIBLE_STATUSES:
            logger.info("Fulfillment skipped", customer_id=customer_id, reason="no eligible subscription")
            return None
        return subscription

    # ===== 5. Private resolution helpers =====
    def _resolve_preferred_roast(self, subscription: Subscription) -> Optional[Roast]:
        roast = self._inventory_service.find_by_preferences(subscription.preferences)
        if roast is None:
            logger.info(
                "Fulfillment skipped", customer_id=subscription.customer_id, reason="preferred roast unavailable"
            )
            return None
        return roast

    def _schedule_roast(self, roast: Roast, subscription: Subscription) -> Optional[ScheduledBatch]:
        try:
            return self._roast_scheduler.schedule_for_subscription(
                roast.id,
                subscription.next_delivery_date,
            )
        except SchedulingError as e:
            logger.error("Schedule failed", customer_id=subscription.customer_id, error=str(e))
            return None

    # ===== 6. Private persistence helpers =====
    def _place_order(self, subscription: Subscription, batch: ScheduledBatch) -> SubscriptionOrder:
        order = SubscriptionOrder(
            id=OrderId.generate(),
            customer_id=subscription.customer_id,
            batch_id=batch.id,
            placed_at=self._clock.now(),
        )
        self._order_repository.save(order)
        return order

    # ===== 7. Private logging/notification helpers =====
    def _notify_customer(self, subscription: Subscription, batch: ScheduledBatch) -> None:
        self._notification_sender.send_roast_scheduled(
            subscription.customer_id,
            batch.expected_date,
        )
```

**Key principles:**

- Constants live at module level — visible at the top of the file
- The public method is the first thing after `__init__` — the headline
- Helper methods are ordered by abstraction level: validation > resolution > persistence > notification
- A reader never has to jump upward — everything referenced in a method is defined below it
- Type hints on every parameter and return value

---

## Part 4: Libraries for Typed Error Handling

Python does not have a built-in `Result` type. Several libraries fill this gap, each with different tradeoffs.

### dry-python/returns

The most feature-complete functional programming library for Python. Provides `Result`, `Maybe`, `IO`, `Future`, and composition tools.

```python
from returns.result import Result, Success, Failure, safe
from returns.pipeline import flow
from returns.pointfree import bind


# @safe wraps exceptions into Result automatically
@safe
def parse_roast_event(payload: bytes) -> RoastEvent:
    return RoastEvent.from_bytes(payload)  # Raises on invalid payload


# flow() composes functions into a pipeline
def execute(self, request: PlaceOrderRequest) -> Result[SubscriptionOrder, OrderFailure]:
    return flow(
        request,
        self._resolve_subscription,
        bind(self._resolve_roast),
        bind(self._process_payment),
        bind(self._save_order),
    )


# Each step returns Result — the pipeline short-circuits on Failure
def _resolve_subscription(self, request: PlaceOrderRequest) -> Result[Subscription, OrderFailure]:
    subscription = self._finder.find_active(request.customer_id)
    if subscription is None:
        return Failure(OrderFailure.no_subscription(request.customer_id))
    return Success(subscription)
```

**Key tools:**
- `Success(value)` / `Failure(error)` — construct results
- `flow(initial, fn1, fn2, ...)` — left-to-right composition
- `bind(fn)` — unwrap Success, pass to next function; short-circuit on Failure
- `@safe` — wraps a function that may raise into one that returns `Result`
- `.map(fn)` — transform the success value
- `.alt(fn)` — transform the failure value

**When to use:** Complex pipelines with many failure modes. Teams that want compiler-enforced error paths. Projects already using functional patterns.

---

### rustedpy/result

Lightweight, Rust-inspired. Just `Ok` and `Err` — no monadic composition, no IO wrapping. Minimal API surface.

```python
from result import Ok, Err, Result


def _resolve_subscription(self, request: PlaceOrderRequest) -> Result[Subscription, str]:
    subscription = self._finder.find_active(request.customer_id)
    if subscription is None:
        return Err(f"No active subscription for {request.customer_id}")
    return Ok(subscription)


# Usage — explicit unwrapping
def execute(self, request: PlaceOrderRequest) -> Result[SubscriptionOrder, str]:
    match self._resolve_subscription(request):
        case Err(e):
            return Err(e)
        case Ok(subscription):
            pass

    match self._resolve_roast(subscription):
        case Err(e):
            return Err(e)
        case Ok(roast):
            pass

    return self._save_order(subscription, roast)
```

**Key tools:**
- `Ok(value)` / `Err(error)` — construct results
- `result.is_ok()` / `result.is_err()` — check status
- `result.unwrap()` — get value or raise
- `result.unwrap_or(default)` — get value or use default
- Pattern matching with `match/case` (Python 3.10+)

**When to use:** Smaller projects. Teams coming from Rust. When you want explicit error handling without the weight of a full FP library.

---

### When to use each vs plain early returns

| Context | Recommended style |
|---------|-------------------|
| Simple use cases, scripts, CLI tools | Early returns + `Optional` |
| Use cases with 2-3 failure modes | Early returns + custom error enum |
| Complex orchestration, many failure types | `dry-python/returns` with `flow()` |
| Interop with Rust-style codebases | `rustedpy/result` with `match` |
| Data pipelines, ETL | `dry-python/returns` with `@safe` |
| FastAPI/Django handlers | Early returns (framework expects exceptions/HTTP responses) |

**The philosophy is the same regardless of library choice.** The headline is a sequence of named steps. Each step either succeeds and passes its result forward, or fails and short-circuits. The library only changes the plumbing — not the structure.

---

## Part 5: Testing in Primera Plana (Python)

Tests are prose, not scripts. A test should read as a sentence describing behavior. If your eyes glaze over identical setup lines before reaching the assertion, the test has failed as documentation.

### Fixtures as shared defaults

```python
import pytest
from unittest.mock import Mock, patch
from datetime import datetime, timezone
from dataclasses import replace


# --- Fixtures (shared defaults) ---

@pytest.fixture
def clock() -> Mock:
    clock = Mock(spec=Clock)
    clock.now.return_value = datetime(2024, 3, 1, 9, 0, tzinfo=timezone.utc)
    return clock


@pytest.fixture
def subscription_finder() -> Mock:
    return Mock(spec=SubscriptionFinder)


@pytest.fixture
def inventory_checker() -> Mock:
    return Mock(spec=InventoryChecker)


@pytest.fixture
def payment_processor() -> Mock:
    return Mock(spec=PaymentProcessor)


@pytest.fixture
def order_repository() -> Mock:
    return Mock(spec=OrderRepository)


@pytest.fixture
def use_case(
    subscription_finder: Mock,
    inventory_checker: Mock,
    payment_processor: Mock,
    order_repository: Mock,
    clock: Mock,
) -> CreateSubscriptionOrderUseCase:
    return CreateSubscriptionOrderUseCase(
        subscription_finder=subscription_finder,
        inventory_checker=inventory_checker,
        payment_processor=payment_processor,
        order_repository=order_repository,
        clock=clock,
    )


@pytest.fixture
def default_subscription() -> Subscription:
    return Subscription(
        id=SubscriptionId.generate(),
        customer_id=CustomerId.generate(),
        preferred_origin=Origin.ETHIOPIA,
        roast_level=RoastLevel.MEDIUM,
        payment_method=PaymentMethod.CARD_ON_FILE,
        status=SubscriptionStatus.ACTIVE,
    )


@pytest.fixture
def default_roast() -> Roast:
    return Roast(
        id=RoastId.generate(),
        origin=Origin.ETHIOPIA,
        level=RoastLevel.MEDIUM,
        stock=50,
        price=Decimal("18.50"),
    )


@pytest.fixture
def default_payment(clock: Mock) -> PaymentConfirmation:
    return PaymentConfirmation(
        id=PaymentId.generate(),
        amount=Decimal("18.50"),
        processed_at=clock.now(),
    )
```

### Parametrize for variations

`@pytest.mark.parametrize` is Python's equivalent of Kotlin's `.copy()` pattern for test variations. Each row is a scenario — the reader sees what varies without scanning construction code.

```python
class TestSubscriptionValidation:

    @pytest.mark.parametrize("status", [
        SubscriptionStatus.PAUSED,
        SubscriptionStatus.CANCELLED,
        SubscriptionStatus.EXPIRED,
    ])
    def test_skips_order_when_subscription_not_active(
        self,
        use_case: CreateSubscriptionOrderUseCase,
        subscription_finder: Mock,
        payment_processor: Mock,
        default_subscription: Subscription,
        status: SubscriptionStatus,
    ):
        inactive_subscription = replace(default_subscription, status=status)
        subscription_finder.find_active.return_value = inactive_subscription

        result = use_case.execute(PlaceOrderRequest(customer_id=default_subscription.customer_id))

        assert result is None
        payment_processor.charge.assert_not_called()
```

### Helper functions with descriptive names

```python
class TestCreateSubscriptionOrder:
    """Tests for the happy path of subscription order creation."""

    def test_places_order_when_subscription_active_and_roast_available(
        self,
        use_case: CreateSubscriptionOrderUseCase,
        subscription_finder: Mock,
        inventory_checker: Mock,
        payment_processor: Mock,
        order_repository: Mock,
        default_subscription: Subscription,
        default_roast: Roast,
        default_payment: PaymentConfirmation,
    ):
        given_active_subscription(subscription_finder, default_subscription)
        given_roast_available(inventory_checker, default_roast)
        given_payment_succeeds(payment_processor, default_payment)

        result = use_case.execute(PlaceOrderRequest(customer_id=default_subscription.customer_id))

        assert result is not None
        assert result.customer_id == default_subscription.customer_id
        order_repository.save.assert_called_once()

    def test_does_not_save_order_when_payment_fails(
        self,
        use_case: CreateSubscriptionOrderUseCase,
        subscription_finder: Mock,
        inventory_checker: Mock,
        payment_processor: Mock,
        order_repository: Mock,
        default_subscription: Subscription,
        default_roast: Roast,
    ):
        given_active_subscription(subscription_finder, default_subscription)
        given_roast_available(inventory_checker, default_roast)
        given_payment_fails(payment_processor, PaymentDeclinedError("insufficient funds"))

        result = use_case.execute(PlaceOrderRequest(customer_id=default_subscription.customer_id))

        assert result is None
        order_repository.save.assert_not_called()


# --- Test helpers (module-level, reusable) ---

def given_active_subscription(finder: Mock, subscription: Subscription) -> None:
    finder.find_active.return_value = subscription


def given_no_subscription(finder: Mock) -> None:
    finder.find_active.return_value = None


def given_roast_available(checker: Mock, roast: Roast) -> None:
    checker.find_available_roast.return_value = roast


def given_payment_succeeds(processor: Mock, payment: PaymentConfirmation) -> None:
    processor.charge.return_value = payment


def given_payment_fails(processor: Mock, error: Exception) -> None:
    processor.charge.side_effect = error
```

### `dataclasses.replace()` for scenario variations

Just like Kotlin's `.copy()`, `replace()` creates a new instance with only the specified fields changed. Tests highlight only what matters for the scenario:

```python
def test_skips_when_roast_out_of_stock(
    self,
    use_case: CreateSubscriptionOrderUseCase,
    subscription_finder: Mock,
    inventory_checker: Mock,
    default_subscription: Subscription,
    default_roast: Roast,
):
    given_active_subscription(subscription_finder, default_subscription)
    out_of_stock_roast = replace(default_roast, stock=0)
    given_roast_available(inventory_checker, out_of_stock_roast)

    result = use_case.execute(PlaceOrderRequest(customer_id=default_subscription.customer_id))

    assert result is None
```

The reader sees one change: `stock=0`. Everything else is the "boring default." The test documents exactly what condition triggers this behavior.

### Testing rules

1. **Fixtures over repeated construction** — define the "boring default" once. Each test overrides only what matters for its scenario.

2. **`given_*` helpers for setup** — `given_active_subscription(finder, subscription)` reads like prose. It separates test infrastructure from the assertion.

3. **`replace()` for variations** — create variants of the default fixture with one meaningful change. The reader sees what varies without scanning identical construction.

4. **`@pytest.mark.parametrize` for combinatorics** — when the same behavior applies across multiple inputs, parametrize rather than duplicate. Each row is a scenario name.

5. **Test names are sentences** — `test_skips_order_when_subscription_not_active`. No abbreviations. No `test_1`. The test name IS the specification.

6. **Verify behavior, not implementation** — assert on the outcome (`order_repository.save.assert_called_once()`) not on intermediate steps (`subscription_finder.find_active` was called with these exact params).

7. **One assertion focus per test** — a test may have multiple `assert` lines, but they should all verify one logical behavior. If you are testing two behaviors, write two tests.

8. **Class grouping by concern** — group tests by the scenario they validate: `TestHappyPath`, `TestSubscriptionValidation`, `TestPaymentFailure`. Not by method name.

---

## Quick Reference

| Rule | Do | Don't |
|------|----|-------|
| Guards | `if x is None: return None` at the top | Nested `if/else` blocks |
| Helpers | `_resolve_order()`, `_validate_address()` | Everything inline |
| Nesting | Max 2 levels in method body | `for` inside `if` inside `try` |
| Types | `Optional[Order]`, `Result[Order, Failure]` | Untyped returns, bare `dict` |
| Exceptions | `except PaymentError as e:` | `except:` or `except Exception:` |
| Domain objects | `@dataclass(frozen=True)` | Plain dicts, mutable classes |
| Inline assign | `if (x := find()) is None:` | Complex nested walrus |
| Defaults | `tags: Optional[list] = None` | `tags: list = []` |
| Collections | `[x for x in items if pred(x)]` | `for` + `append` |
| Computed values | `@property` for cheap derivations | Method calls for attribute-like access |
| Constants | Module-level `MAX_RETRIES = 3` | Class-level or buried in methods |
| Public methods | 5-10 lines, named steps | Complex logic, logging, object construction |
| Private methods | Name describes WHAT, not HOW | `_do_stuff()`, `_handle_thing()`, `_process()` |
| Tests | Fixtures + `replace()` + `given_*` helpers | Full construction in every test |
| Test names | `test_skips_when_payment_fails` | `test_1`, `test_error_case` |
