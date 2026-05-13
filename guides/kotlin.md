# Primera Plana — Kotlin Guide

Code reads like a newspaper. The headline tells you what happened. The first paragraph gives you context. The details live deeper — and you only read them if you care.

Public methods are headlines: 5-10 lines, each line a named step. Private methods are paragraphs: focused, named, self-contained. Complexity lives in the leaves. The reader decides how deep to go.

This guide shows how to write Kotlin that follows Primera Plana — regardless of whether you use Arrow, nullable types, or plain exceptions.

---

## Part 1: The Headline Pattern

The same use case, two styles. The philosophy is identical — only the error plumbing changes.

### The Domain: Tostado

Tostado is a specialty coffee subscription service. Customers place recurring orders for roasted beans. The roastery processes batches. Shipments are matched to orders on delivery.

---

### PlaceSubscriptionOrderUseCase

#### Nullable Style (no Arrow)

```kotlin
private const val PROCESS = "place-subscription-order"

class PlaceSubscriptionOrderUseCase(
    private val subscriptionFinder: SubscriptionFinder,
    private val inventoryChecker: InventoryChecker,
    private val paymentProcessor: PaymentProcessor,
    private val orderRepository: OrderRepository,
    private val clock: Clock,
) {
    fun execute(request: PlaceOrderRequest) {
        val subscription = resolveSubscription(request) ?: return
        val roast = resolveAvailableRoast(subscription) ?: return
        val payment = processPayment(subscription, roast) ?: return

        saveOrder(subscription, roast, payment)
    }

    // --- Validation ---

    private fun resolveSubscription(request: PlaceOrderRequest) =
        subscriptionFinder.findActive(request.customerId)
            ?: logSkippedAndReturnNull(request, "no active subscription")

    // --- Resolution ---

    private fun resolveAvailableRoast(subscription: Subscription) =
        inventoryChecker.findAvailableRoast(subscription.preferredOrigin, subscription.roastLevel)
            ?: logSkippedAndReturnNull(subscription, "roast unavailable")

    private fun processPayment(subscription: Subscription, roast: Roast) =
        runCatching { paymentProcessor.charge(subscription.paymentMethod, roast.price) }
            .onFailure { logPaymentFailed(subscription, it) }
            .getOrNull()

    // --- Persistence ---

    private fun saveOrder(subscription: Subscription, roast: Roast, payment: PaymentConfirmation) {
        val order = SubscriptionOrder(
            id = OrderId.generate(),
            customerId = subscription.customerId,
            roastId = roast.id,
            paymentId = payment.id,
            placedAt = clock.instant(),
        )
        orderRepository.save(order)
    }

    // --- Logging ---

    private fun logSkippedAndReturnNull(request: PlaceOrderRequest, reason: String): Nothing? {
        log.info(PROCESS, "ORDER_SKIPPED", "customerId" to request.customerId, "reason" to reason)
        return null
    }

    private fun logSkippedAndReturnNull(subscription: Subscription, reason: String): Nothing? {
        log.info(PROCESS, "ORDER_SKIPPED", "customerId" to subscription.customerId, "reason" to reason)
        return null
    }

    private fun logPaymentFailed(subscription: Subscription, error: Throwable) {
        log.warn(PROCESS, "PAYMENT_FAILED", "customerId" to subscription.customerId, "error" to error.message)
    }
}
```

The headline (`execute`) is five lines. A reviewer reads those five lines and understands the entire flow. If the payment logic is wrong, they scroll to `processPayment`. The structure is self-navigating.

#### Either/Arrow Style

```kotlin
private const val PROCESS = "place-subscription-order"

class PlaceSubscriptionOrderUseCase(
    private val subscriptionFinder: SubscriptionFinder,
    private val inventoryChecker: InventoryChecker,
    private val paymentProcessor: PaymentProcessor,
    private val orderRepository: OrderRepository,
    private val clock: Clock,
) {
    fun execute(request: PlaceOrderRequest): Either<OrderFailure, SubscriptionOrder> =
        resolveSubscription(request)
            .flatMap { subscription -> resolveAvailableRoast(subscription) }
            .flatMap { (subscription, roast) -> processPayment(subscription, roast) }
            .map { (subscription, roast, payment) -> saveOrder(subscription, roast, payment) }

    // --- Resolution ---

    private fun resolveSubscription(request: PlaceOrderRequest): Either<OrderFailure, Subscription> =
        subscriptionFinder.findActive(request.customerId)
            .toEither { OrderFailure.NoActiveSubscription(request.customerId) }

    private fun resolveAvailableRoast(subscription: Subscription): Either<OrderFailure, Pair<Subscription, Roast>> =
        inventoryChecker.findAvailableRoast(subscription.preferredOrigin, subscription.roastLevel)
            .toEither { OrderFailure.RoastUnavailable(subscription.preferredOrigin) }
            .map { roast -> subscription to roast }

    // --- Processing ---

    private fun processPayment(
        subscription: Subscription,
        roast: Roast,
    ): Either<OrderFailure, Triple<Subscription, Roast, PaymentConfirmation>> =
        Either.catch { paymentProcessor.charge(subscription.paymentMethod, roast.price) }
            .mapLeft { OrderFailure.PaymentFailed(subscription.customerId, it.message) }
            .map { payment -> Triple(subscription, roast, payment) }

    // --- Persistence ---

    private fun saveOrder(
        subscription: Subscription,
        roast: Roast,
        payment: PaymentConfirmation,
    ): SubscriptionOrder {
        val order = SubscriptionOrder(
            id = OrderId.generate(),
            customerId = subscription.customerId,
            roastId = roast.id,
            paymentId = payment.id,
            placedAt = clock.instant(),
        )
        orderRepository.save(order)
        return order
    }
}
```

Same newspaper structure. The headline (`execute`) is four lines — a chain of named steps. Each step is a private method. The reader controls their depth.

---

### ProcessRoastBatchUseCase

#### Nullable Style

```kotlin
private const val PROCESS = "process-roast-batch"

class ProcessRoastBatchUseCase(
    private val batchQueue: BatchQueue,
    private val temperatureMonitor: TemperatureMonitor,
    private val qualityGrader: QualityGrader,
    private val batchRepository: BatchRepository,
    private val clock: Clock,
) {
    fun execute(batchId: BatchId) {
        val batch = resolvePendingBatch(batchId) ?: return
        val profile = resolveRoastProfile(batch) ?: return
        val grading = performQualityCheck(batch, profile) ?: return

        completeBatch(batch, grading)
    }

    // --- Validation ---

    private fun resolvePendingBatch(batchId: BatchId) =
        batchQueue.findPending(batchId)
            ?: logAndReturnNull(batchId, "batch not found or already processed")

    // --- Resolution ---

    private fun resolveRoastProfile(batch: RoastBatch) =
        temperatureMonitor.captureProfile(batch.id)
            .takeIf { it.peakTemperature in batch.targetRange }
            ?: logAndReturnNull(batch.id, "temperature outside target range")

    private fun performQualityCheck(batch: RoastBatch, profile: RoastProfile) =
        qualityGrader.grade(batch.origin, profile)
            .takeIf { it.score >= batch.minimumGrade }
            ?: logAndReturnNull(batch.id, "quality below minimum threshold")

    // --- Persistence ---

    private fun completeBatch(batch: RoastBatch, grading: QualityGrading) {
        val completed = batch.copy(
            status = BatchStatus.COMPLETED,
            grade = grading.score,
            completedAt = clock.instant(),
        )
        batchRepository.save(completed)
    }

    // --- Logging ---

    private fun logAndReturnNull(batchId: BatchId, reason: String): Nothing? {
        log.warn(PROCESS, "BATCH_SKIPPED", "batchId" to batchId, "reason" to reason)
        return null
    }
}
```

#### Either/Arrow Style (with Raise context — Arrow 2.x)

```kotlin
private const val PROCESS = "process-roast-batch"

class ProcessRoastBatchUseCase(
    private val batchQueue: BatchQueue,
    private val temperatureMonitor: TemperatureMonitor,
    private val qualityGrader: QualityGrader,
    private val batchRepository: BatchRepository,
    private val clock: Clock,
) {
    context(Raise<BatchFailure>)
    fun execute(batchId: BatchId): CompletedBatch {
        val batch = resolvePendingBatch(batchId)
        val profile = resolveRoastProfile(batch)
        val grading = performQualityCheck(batch, profile)

        return completeBatch(batch, grading)
    }

    // --- Validation ---

    context(Raise<BatchFailure>)
    private fun resolvePendingBatch(batchId: BatchId): RoastBatch =
        batchQueue.findPending(batchId)
            ?: raise(BatchFailure.NotFound(batchId))

    // --- Resolution ---

    context(Raise<BatchFailure>)
    private fun resolveRoastProfile(batch: RoastBatch): RoastProfile {
        val profile = temperatureMonitor.captureProfile(batch.id)
        ensure(profile.peakTemperature in batch.targetRange) {
            BatchFailure.TemperatureOutOfRange(batch.id, profile.peakTemperature)
        }
        return profile
    }

    context(Raise<BatchFailure>)
    private fun performQualityCheck(batch: RoastBatch, profile: RoastProfile): QualityGrading {
        val grading = qualityGrader.grade(batch.origin, profile)
        ensure(grading.score >= batch.minimumGrade) {
            BatchFailure.QualityBelowThreshold(batch.id, grading.score)
        }
        return grading
    }

    // --- Persistence ---

    private fun completeBatch(batch: RoastBatch, grading: QualityGrading): CompletedBatch {
        val completed = batch.copy(
            status = BatchStatus.COMPLETED,
            grade = grading.score,
            completedAt = clock.instant(),
        )
        batchRepository.save(completed)
        return CompletedBatch(completed.id, grading.score)
    }
}
```

Notice how `Raise` context makes the headline even cleaner — no `?: return`, no `.flatMap`. The philosophy is the same: short headline, named steps, complexity in the leaves.

---

### ResolveShipmentUseCase

#### Nullable Style

```kotlin
private const val PROCESS = "resolve-shipment"

class ResolveShipmentUseCase(
    private val shipmentTracker: ShipmentTracker,
    private val orderMatcher: OrderMatcher,
    private val deliveryRepository: DeliveryRepository,
    private val notificationSender: NotificationSender,
    private val clock: Clock,
) {
    fun execute(trackingEvent: TrackingEvent) {
        val shipment = resolveShipment(trackingEvent) ?: return
        val order = matchToOrder(shipment) ?: return
        val delivery = recordDelivery(shipment, order) ?: return

        notifyCustomer(delivery)
    }

    // --- Validation ---

    private fun resolveShipment(event: TrackingEvent) =
        shipmentTracker.findByTrackingCode(event.trackingCode)
            ?.takeIf { it.status == ShipmentStatus.DELIVERED }
            ?: logAndReturnNull(event, "shipment not found or not delivered")

    // --- Resolution ---

    private fun matchToOrder(shipment: Shipment) =
        orderMatcher.findByShipmentId(shipment.id)
            ?: logAndReturnNull(shipment, "no matching order found")

    // --- Persistence ---

    private fun recordDelivery(shipment: Shipment, order: SubscriptionOrder): Delivery? {
        val delivery = Delivery(
            id = DeliveryId.generate(),
            orderId = order.id,
            shipmentId = shipment.id,
            deliveredAt = clock.instant(),
        )
        return runCatching { deliveryRepository.save(delivery) }
            .onFailure { logSaveFailed(shipment, it) }
            .getOrNull()
            ?.let { delivery }
    }

    // --- Side effects ---

    private fun notifyCustomer(delivery: Delivery) {
        notificationSender.sendDeliveryConfirmation(delivery)
    }

    // --- Logging ---

    private fun logAndReturnNull(event: TrackingEvent, reason: String): Nothing? {
        log.info(PROCESS, "SHIPMENT_SKIPPED", "trackingCode" to event.trackingCode, "reason" to reason)
        return null
    }

    private fun logAndReturnNull(shipment: Shipment, reason: String): Nothing? {
        log.warn(PROCESS, "SHIPMENT_UNMATCHED", "shipmentId" to shipment.id, "reason" to reason)
        return null
    }

    private fun logSaveFailed(shipment: Shipment, error: Throwable) {
        log.error(PROCESS, "DELIVERY_SAVE_FAILED", "shipmentId" to shipment.id, "error" to error.message)
    }
}
```

#### Either/Arrow Style

```kotlin
private const val PROCESS = "resolve-shipment"

class ResolveShipmentUseCase(
    private val shipmentTracker: ShipmentTracker,
    private val orderMatcher: OrderMatcher,
    private val deliveryRepository: DeliveryRepository,
    private val notificationSender: NotificationSender,
    private val clock: Clock,
) {
    fun execute(trackingEvent: TrackingEvent): Either<ShipmentFailure, Delivery> =
        resolveShipment(trackingEvent)
            .flatMap { shipment -> matchToOrder(shipment) }
            .flatMap { (shipment, order) -> recordDelivery(shipment, order) }
            .onRight { delivery -> notifyCustomer(delivery) }

    // --- Validation ---

    private fun resolveShipment(event: TrackingEvent): Either<ShipmentFailure, Shipment> =
        shipmentTracker.findByTrackingCode(event.trackingCode)
            ?.takeIf { it.status == ShipmentStatus.DELIVERED }
            .toEither { ShipmentFailure.NotDelivered(event.trackingCode) }

    // --- Resolution ---

    private fun matchToOrder(shipment: Shipment): Either<ShipmentFailure, Pair<Shipment, SubscriptionOrder>> =
        orderMatcher.findByShipmentId(shipment.id)
            .toEither { ShipmentFailure.NoMatchingOrder(shipment.id) }
            .map { order -> shipment to order }

    // --- Persistence ---

    private fun recordDelivery(
        shipment: Shipment,
        order: SubscriptionOrder,
    ): Either<ShipmentFailure, Delivery> =
        Either.catch {
            val delivery = Delivery(
                id = DeliveryId.generate(),
                orderId = order.id,
                shipmentId = shipment.id,
                deliveredAt = clock.instant(),
            )
            deliveryRepository.save(delivery)
            delivery
        }.mapLeft { ShipmentFailure.PersistenceFailed(shipment.id, it.message) }

    // --- Side effects ---

    private fun notifyCustomer(delivery: Delivery) {
        notificationSender.sendDeliveryConfirmation(delivery)
    }
}
```

**The takeaway:** Whether you use `?: return` or `.flatMap {}`, the structure is identical. Short headline. Named steps. Complexity in the leaves. The philosophy is the constant — the error handling mechanism is a variable.

---

## Part 2: Kotlin-Specific Rules

These rules make Kotlin code follow Primera Plana. They are non-negotiable.

### 1. No companion objects

Companion objects are Java's `static` wearing a Kotlin costume. They add indirection, break discoverability, and pollute the class body with infrastructure that belongs at file level.

```kotlin
// Primera Plana — file-level for primitives
private const val PROCESS = "roast-batch-processor"
private const val MAX_RETRIES = 3

class RoastBatchProcessor(
    private val batchQueue: BatchQueue,
    private val clock: Clock,
) {
    // Non-primitive computed values are class members
    private val supportedOrigins = listOf(Origin.ETHIOPIA, Origin.COLOMBIA, Origin.GUATEMALA)

    fun execute(batchId: BatchId) { /* ... */ }
}

// Banned — companion object
class RoastBatchProcessor(...) {
    companion object {
        private const val PROCESS = "roast-batch-processor"  // No.
        private val SUPPORTED_ORIGINS = listOf(...)          // No.
    }
}
```

**Why:** File-level constants are visible at the top of the file — the reader sees them immediately. Companion objects force scrolling to the bottom (convention) or create a block at the top that separates class params from class logic.

---

### 2. No force unwrap (`!!`)

`!!` produces crash messages like `get(...) must not be null` — useless for debugging at 3 AM. It means either your type model is wrong or you are too lazy to handle the null case.

```kotlin
// Primera Plana
val roast = roastCatalog.getValue(roastId)
val origin = bean.origin ?: error("Bean ${bean.id} has no origin — imported beans must have origin set")
val grindSize = requireNotNull(profile.grindSize) {
    "Grind size missing for profile ${profile.id} — subscription profiles must specify grind"
}

// Banned
val roast = roastCatalog[roastId]!!
val origin = bean.origin!!
val grindSize = profile.grindSize!!
```

**The rule:** If you reach for `!!`, ask yourself: "Is the type model wrong, or is the null case unhandled?" Fix the root cause.

---

### 3. No `for` loops — use stdlib intent functions

A `for` loop declares *mechanism* (iteration) without declaring *intent*. The reader must read the body to understand what the loop does. Kotlin's stdlib functions are constrained — each does exactly one thing. Constraints communicate intent.

```kotlin
// Primera Plana — intent is declared
val eligibleBeans = beans.filter { it.harvestDate.isAfter(cutoffDate) }
val firstAvailable = roasts.firstOrNull { it.stock > 0 }
val totalWeight = bags.sumOf { it.weightGrams }
val beansByOrigin = catalog.groupBy { it.origin }

val allBatches = generateSequence(fetchBatch(cursor = null)) { previousBatch ->
    previousBatch.nextCursor?.let { fetchBatch(it) }
}.flatten().toList()

// Banned — mechanism without intent
val eligibleBeans = mutableListOf<Bean>()
for (bean in beans) {
    if (bean.harvestDate.isAfter(cutoffDate)) {
        eligibleBeans.add(bean)
    }
}
```

| Intent | Use |
|--------|-----|
| Transform each item | `.map { }` |
| Keep matching items | `.filter { }` |
| Find first match | `.firstOrNull { }` |
| Find first non-null result | `.firstNotNullOfOrNull { }` |
| Check if any match | `.any { }` |
| Accumulate | `.fold()` / `.sumOf()` / `.groupBy()` |
| Paginated fetch | `generateSequence { }` |

---

### 4. Expression-body functions

When a function is a single expression, use `=`. No braces, no `return`. This signals "this function is a transformation" and keeps the class visually compact.

```kotlin
// Primera Plana
private fun resolveGrindLevel(subscription: Subscription) =
    subscription.preferences.grindSize ?: GrindLevel.MEDIUM

private fun isEligibleForFreeShipping(order: SubscriptionOrder) =
    order.totalWeight >= FREE_SHIPPING_THRESHOLD

private fun buildDeliveryLabel(order: SubscriptionOrder, address: Address) =
    DeliveryLabel(orderId = order.id, recipient = address.fullName, postalCode = address.postalCode)

// Avoid
private fun resolveGrindLevel(subscription: Subscription): GrindLevel {
    return subscription.preferences.grindSize ?: GrindLevel.MEDIUM
}
```

---

### 5. Inject time — never `Instant.now()`

Direct calls to `Instant.now()`, `LocalDate.now()`, or `UUID.randomUUID()` produce non-deterministic behavior. Tests become flaky or require `Thread.sleep`.

```kotlin
// Primera Plana — deterministic, testable
class ScheduleRoastUseCase(
    private val clock: Clock,
    private val batchRepository: BatchRepository,
) {
    fun execute(request: ScheduleRequest): RoastBatch {
        val batch = RoastBatch(
            id = request.batchId,
            scheduledAt = clock.instant(),
            origin = request.origin,
        )
        return batchRepository.save(batch)
    }
}

// In tests:
private val fixedClock = Clock.fixed(Instant.parse("2024-01-15T10:00:00Z"), ZoneOffset.UTC)
private val underTest = ScheduleRoastUseCase(fixedClock, batchRepository)

// Banned — untestable
val batch = RoastBatch(scheduledAt = Instant.now())
```

---

### 6. Feature flags: positive naming

Feature flag methods use the positive verb. Never use "disabled" — it creates double negation that adds cognitive load.

```kotlin
// Primera Plana — clear intent
if (!featureFlags.isNewRoastProfileEnabled()) return
if (featureFlags.isBatchAutoGradingEnabled()) gradeAutomatically(batch)

// Banned — double negation
if (!featureFlags.isAutoGradingDisabled()) gradeAutomatically(batch)  // What?
```

---

### 7. No explicit boolean comparisons

If a method returns `Boolean`, use it directly. Never compare against `true` or `false`.

```kotlin
// Primera Plana
if (subscription.isActive()) processOrder(subscription)
if (!roast.isAvailable()) return

// Banned
if (subscription.isActive() == true) processOrder(subscription)
if (roast.isAvailable() == false) return
```

---

### 8. Safe casts with `?: return`

Use `as?` with `?: return` over explicit type checks. This keeps the happy path linear and avoids nested branching.

```kotlin
// Primera Plana
fun handle(event: DomainEvent) {
    val roastEvent = event as? RoastCompletedEvent ?: return
    processBatchCompletion(roastEvent)
}

// Avoid
fun handle(event: DomainEvent) {
    if (event is RoastCompletedEvent) {
        processBatchCompletion(event)
    }
}
```

---

### 9. Scope functions where they improve readability

`also`, `let`, `apply`, `run` reduce temporary variables and signal intent — but only when they make the code clearer, not cleverer.

```kotlin
// Good — let avoids a temporary variable
subscriptionFinder.findById(subscriptionId)?.let { subscription ->
    DeliverySchedule(customerId = subscription.customerId, frequency = subscription.frequency)
}

// Good — also for side effects that don't change the value
batchRepository.save(completedBatch).also { logBatchCompleted(it) }

// Good — apply for object configuration
RoastProfile().apply {
    temperature = targetTemp
    duration = roastDuration
    fanSpeed = FanSpeed.HIGH
}

// Bad — scope function makes it harder to read
beans.filter { it.isOrganic }.let { organicBeans ->
    organicBeans.map { it.origin }  // just chain .map directly
}
```

---

### 10. `runCatching` over `try/catch`

`runCatching` is Kotlin's idiom for error boundaries. It integrates with the stdlib `Result` type and chains naturally.

```kotlin
// Primera Plana
private fun parseRoastEvent(payload: ByteArray) =
    runCatching { RoastEvent.parseFrom(payload) }
        .onFailure { log.warn(PROCESS, "PARSE_FAILED", "error" to it.message) }
        .getOrNull()

private fun fetchBeanPrice(origin: Origin) =
    runCatching { priceService.getCurrentPrice(origin) }
        .getOrDefault(Price.ZERO)

// Avoid — Java-style
private fun parseRoastEvent(payload: ByteArray): RoastEvent? {
    try {
        return RoastEvent.parseFrom(payload)
    } catch (e: InvalidProtocolBufferException) {
        log.warn(PROCESS, "PARSE_FAILED", "error" to e.message)
        return null
    }
}
```

---

## Part 3: Class Layout

The newspaper structure applied to a full class. Each layer is more detailed than the one above. The reader scrolls deeper only when they need to.

```kotlin
// ===== 1. File-level constants =====
private const val PROCESS = "fulfill-subscription"
private const val MAX_RETRY_ATTEMPTS = 3

// ===== 2. Class parameters (DI) =====
class FulfillSubscriptionUseCase(
    private val subscriptionFinder: SubscriptionFinder,
    private val inventoryService: InventoryService,
    private val roastScheduler: RoastScheduler,
    private val orderRepository: OrderRepository,
    private val notificationSender: NotificationSender,
    private val featureFlags: FeatureFlags,
    private val clock: Clock,
) {

    // ===== 3. Class members (vals) =====
    private val eligibleStatuses = listOf(SubscriptionStatus.ACTIVE, SubscriptionStatus.PAUSED_RESUMING)

    // ===== 4. Public API =====
    fun execute(customerId: CustomerId) {
        if (!featureFlags.isAutoFulfillmentEnabled()) return

        val subscription = resolveEligibleSubscription(customerId) ?: return
        val roast = resolvePreferredRoast(subscription) ?: return
        val scheduledBatch = scheduleRoast(roast, subscription) ?: return

        placeOrder(subscription, scheduledBatch)
        notifyCustomer(subscription, scheduledBatch)
    }

    // ===== 5. Validation helpers =====
    private fun resolveEligibleSubscription(customerId: CustomerId) =
        subscriptionFinder.findByCustomer(customerId)
            ?.takeIf { it.status in eligibleStatuses }
            ?: logSkippedAndReturnNull(customerId, "no eligible subscription")

    // ===== 6. Resolution/orchestration helpers =====
    private fun resolvePreferredRoast(subscription: Subscription) =
        inventoryService.findByPreferences(subscription.preferences)
            ?: logSkippedAndReturnNull(subscription.customerId, "preferred roast unavailable")

    private fun scheduleRoast(roast: Roast, subscription: Subscription) =
        runCatching { roastScheduler.scheduleForSubscription(roast.id, subscription.nextDeliveryDate) }
            .onFailure { logScheduleFailed(subscription, it) }
            .getOrNull()

    // ===== 7. Data access helpers =====
    // (In this case, resolution already covers data access — section can be empty)

    // ===== 8. Persistence helpers =====
    private fun placeOrder(subscription: Subscription, batch: ScheduledBatch) {
        val order = SubscriptionOrder(
            id = OrderId.generate(),
            customerId = subscription.customerId,
            batchId = batch.id,
            placedAt = clock.instant(),
        )
        orderRepository.save(order)
    }

    // ===== 9. Logging/error helpers =====
    private fun logSkippedAndReturnNull(customerId: CustomerId, reason: String): Nothing? {
        log.info(PROCESS, "FULFILLMENT_SKIPPED", "customerId" to customerId, "reason" to reason)
        return null
    }

    private fun logScheduleFailed(subscription: Subscription, error: Throwable) {
        log.error(PROCESS, "SCHEDULE_FAILED", "customerId" to subscription.customerId, "error" to error.message)
    }

    // ===== 10. Utility helpers =====
    private fun notifyCustomer(subscription: Subscription, batch: ScheduledBatch) {
        notificationSender.sendRoastScheduled(subscription.customerId, batch.expectedDate)
    }
}
```

**Key principles:**

- Constants live outside the class at file level
- The public method is the first thing after class members — the headline
- Helper methods are ordered by abstraction level: validation > resolution > data > persistence > logging > utility
- A reader never has to jump upward — everything referenced in a method is defined below it

---

## Part 4: Testing in Primera Plana

Tests are prose, not scripts. A test should read as a sentence describing behavior. If your eyes glaze over identical setup lines before reaching the assertion, the test has failed as documentation.

### Shared defaults with `.copy()` overrides

```kotlin
class PlaceSubscriptionOrderUseCaseTest {

    private val subscriptionFinder: SubscriptionFinder = mockk()
    private val inventoryChecker: InventoryChecker = mockk()
    private val paymentProcessor: PaymentProcessor = mockk()
    private val orderRepository: OrderRepository = mockk(relaxed = true)
    private val clock: Clock = Clock.fixed(Instant.parse("2024-03-01T09:00:00Z"), ZoneOffset.UTC)

    private val underTest = PlaceSubscriptionOrderUseCase(
        subscriptionFinder,
        inventoryChecker,
        paymentProcessor,
        orderRepository,
        clock,
    )

    // --- Shared defaults ---
    private val customerId = CustomerId(UUID.randomUUID())
    private val defaultSubscription = Subscription(
        id = SubscriptionId(UUID.randomUUID()),
        customerId = customerId,
        preferredOrigin = Origin.ETHIOPIA,
        roastLevel = RoastLevel.MEDIUM,
        paymentMethod = PaymentMethod.CARD_ON_FILE,
        status = SubscriptionStatus.ACTIVE,
    )
    private val defaultRoast = Roast(
        id = RoastId(UUID.randomUUID()),
        origin = Origin.ETHIOPIA,
        level = RoastLevel.MEDIUM,
        stock = 50,
        price = Price(BigDecimal("18.50"), Currency.EUR),
    )
    private val defaultPayment = PaymentConfirmation(
        id = PaymentId(UUID.randomUUID()),
        amount = defaultRoast.price,
        processedAt = clock.instant(),
    )

    @Nested
    inner class HappyPath {

        @Test
        fun `should place order when subscription is active and roast is available`() {
            `given active subscription exists`()
            `given roast is available`()
            `given payment succeeds`()

            underTest.execute(PlaceOrderRequest(customerId))

            verify { orderRepository.save(match { it.customerId == customerId }) }
        }
    }

    @Nested
    inner class SubscriptionValidation {

        @Test
        fun `should skip when customer has no active subscription`() {
            `given no subscription exists`()

            underTest.execute(PlaceOrderRequest(customerId))

            verify(exactly = 0) { paymentProcessor.charge(any(), any()) }
        }

        @Test
        fun `should skip when subscription is paused`() {
            val pausedSubscription = defaultSubscription.copy(status = SubscriptionStatus.PAUSED)
            `given subscription exists`(pausedSubscription)

            underTest.execute(PlaceOrderRequest(customerId))

            verify(exactly = 0) { inventoryChecker.findAvailableRoast(any(), any()) }
        }
    }

    @Nested
    inner class PaymentFailure {

        @Test
        fun `should not save order when payment fails`() {
            `given active subscription exists`()
            `given roast is available`()
            `given payment fails with`(PaymentDeclinedException("insufficient funds"))

            underTest.execute(PlaceOrderRequest(customerId))

            verify(exactly = 0) { orderRepository.save(any()) }
        }
    }

    // --- Test helpers (backtick names) ---

    private fun `given active subscription exists`() {
        every { subscriptionFinder.findActive(customerId) } returns defaultSubscription
    }

    private fun `given subscription exists`(subscription: Subscription) {
        every { subscriptionFinder.findActive(customerId) } returns subscription
    }

    private fun `given no subscription exists`() {
        every { subscriptionFinder.findActive(customerId) } returns null
    }

    private fun `given roast is available`() {
        every { inventoryChecker.findAvailableRoast(Origin.ETHIOPIA, RoastLevel.MEDIUM) } returns defaultRoast
    }

    private fun `given payment succeeds`() {
        every { paymentProcessor.charge(any(), any()) } returns defaultPayment
    }

    private fun `given payment fails with`(exception: Exception) {
        every { paymentProcessor.charge(any(), any()) } throws exception
    }
}
```

### Testing rules

1. **`mockk()` over `@MockK`** — explicit construction, no annotation magic, no `@InjectMockKs` gambling on parameter order.

2. **Backtick names for test helpers** — `given active subscription exists`() reads like prose. It clearly separates test infrastructure from production naming.

3. **`.copy()` for variations** — define the "boring default" once. Each test overrides only what matters for its scenario. The reader sees what varies without scanning identical construction.

4. **`@Nested` groups by concern** — not by method name. Group tests by the scenario they validate: "HappyPath", "SubscriptionValidation", "PaymentFailure".

5. **Test names are sentences** — `should place order when subscription is active and roast is available`. No abbreviations. No `test_1`. The test name IS the specification.

6. **Verify behavior, not implementation** — assert on the outcome (`orderRepository.save(...)`) not on intermediate steps (`subscriptionFinder` was called with these exact params).

---

## Part 5: Arrow/Either as an Accelerator

Arrow is not required for Primera Plana. The philosophy works perfectly with nullable types and `?: return`. But Arrow *enforces* the newspaper style at the type system level — the compiler won't let you skip a step.

### How Either enforces the pattern

With nullable style, a developer can forget to handle a failure case — they just don't call the helper, or they ignore the null. The code compiles. The bug hides.

With `Either<Failure, Success>`, the compiler forces you to handle both paths. You cannot access the success value without acknowledging the failure path exists.

```kotlin
// The type system enforces that every step handles failure
fun execute(request: PlaceOrderRequest): Either<OrderFailure, SubscriptionOrder> =
    resolveSubscription(request)
        .flatMap { subscription -> resolveAvailableRoast(subscription) }
        .flatMap { (subscription, roast) -> processPayment(subscription, roast) }
        .map { (subscription, roast, payment) -> saveOrder(subscription, roast, payment) }
```

Each `.flatMap` is a named step. If any step returns `Left`, the chain short-circuits. The "headline" is a linear pipeline of named operations — exactly what Primera Plana demands.

### `.flatMap {}` chains ARE the headline

The `.flatMap` chain is structurally identical to the `?: return` style:

| Nullable style | Either style |
|----------------|--------------|
| `val x = resolveX() ?: return` | `.flatMap { resolveX(it) }` |
| `val y = resolveY(x) ?: return` | `.flatMap { resolveY(it) }` |
| `save(x, y)` | `.map { save(it) }` |

Same philosophy. Same readability. Different plumbing.

### Arrow 2.x `Raise` context — the most aligned style

Arrow 2.x introduces `Raise` context receivers. This is the most Primera Plana-aligned style because it removes ALL ceremony from the headline:

```kotlin
context(Raise<OrderFailure>)
fun execute(request: PlaceOrderRequest): SubscriptionOrder {
    val subscription = resolveSubscription(request)
    val roast = resolveAvailableRoast(subscription)
    val payment = processPayment(subscription, roast)

    return saveOrder(subscription, roast, payment)
}
```

No `?: return`. No `.flatMap`. No `Either` in the signature of private helpers. The headline is pure sequential logic — exactly like imperative code, but with type-safe error handling via `raise()` and `ensure()`.

```kotlin
context(Raise<OrderFailure>)
private fun resolveSubscription(request: PlaceOrderRequest): Subscription =
    subscriptionFinder.findActive(request.customerId)
        ?: raise(OrderFailure.NoActiveSubscription(request.customerId))

context(Raise<OrderFailure>)
private fun resolveAvailableRoast(subscription: Subscription): Roast {
    val roast = inventoryChecker.findAvailableRoast(subscription.preferredOrigin, subscription.roastLevel)
        ?: raise(OrderFailure.RoastUnavailable(subscription.preferredOrigin))
    ensure(roast.stock > 0) { OrderFailure.OutOfStock(roast.id) }
    return roast
}
```

Key Arrow 2.x tools:
- `raise(failure)` — short-circuit with a typed error (replaces `?: return`)
- `ensure(condition) { failure }` — guard clause that raises on false
- `bind()` — extract value from `Either` inside a `Raise` block
- `recover { }` — handle errors at call boundaries

### When to use which

| Context | Recommended style |
|---------|-------------------|
| Simple use cases, event handlers | Nullable + `?: return` |
| Complex orchestration with many failure modes | `Either<Failure, Success>` |
| New codebases, teams comfortable with Arrow | `Raise` context (Arrow 2.x) |
| Mixed — adapting between layers | `Either` at boundaries, nullable internally |

### The philosophy is the constant

Arrow does not change the rules. It changes the enforcement mechanism:

- Without Arrow: discipline enforces the pattern. A developer must choose to extract steps, name them, and handle nulls.
- With Arrow: the type system enforces the pattern. The compiler rejects code that skips error handling or buries complexity in the headline.

Either way, the newspaper reads the same. Public methods are headlines. Private methods are paragraphs. Complexity lives in the leaves. The reader decides how deep to go.

---

## Quick Reference

| Rule | Do | Don't |
|------|----|-------|
| Constants | `private const val PROCESS = "..."` at file level | `companion object { }` |
| Null safety | `?: error("context")` / `requireNotNull { }` | `!!` |
| Iteration | `.map`, `.filter`, `.firstOrNull`, `generateSequence` | `for`, `while`, `do` |
| Single expressions | `fun x() = expr` | `fun x() { return expr }` |
| Time | Inject `Clock`, use `clock.instant()` | `Instant.now()` |
| Feature flags | `isFeatureEnabled()` | `isFeatureDisabled()` |
| Booleans | `if (active)` | `if (active == true)` |
| Type checks | `as? Type ?: return` | `if (x is Type)` |
| Error handling | `runCatching { }.getOrNull()` | `try { } catch { }` |
| Public methods | 5-10 lines, named steps | Complex logic, logging, object construction |
| Private methods | Name describes what, not how | `doX()`, `handleY()`, `processZ()` |
| Tests | `.copy()` overrides, backtick helpers | Full construction in every test |
