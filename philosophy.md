# The Primera Plana Philosophy

## The Shift

For decades, the hard part of software was writing. Getting the logic right. Making it compile. Shipping it.

That era is over.

AI made writing code trivially fast. A developer with Copilot, Cursor, or Claude can produce 500 lines of working code in the time it used to take to write 50. The output quality is acceptable. The tests pass. The feature works.

But someone still has to **read** that code.

Someone has to review the PR. Someone has to debug it at 2am when it breaks. Someone has to modify it six months later when requirements change. And that someone's reading speed didn't improve at all.

**The bottleneck shifted from writing to reading.** And it's never shifting back.

Primera Plana is a philosophy built for this new reality. It optimizes for the reader — ruthlessly, unapologetically, and at the writer's expense if necessary.

---

## The Newspaper Analogy

In the 1860s, telegraph lines were unreliable. Journalists couldn't guarantee their full story would arrive, so they developed the **inverted pyramid**: put the most critical information first. If the line cut out after one paragraph, the reader still got the essential story.

This evolved into how newspapers are structured today:

- **The headline** tells you what happened in 8 words
- **The lead paragraph** gives you the full story in 30 seconds
- **The body** provides supporting detail for those who want depth
- **The background section** gives full context for specialists

The reader decides how deep to go. A busy executive reads headlines. A concerned citizen reads the lead. A domain expert reads everything. No reader is forced to wade through background to find the point.

**Code should work the same way.**

```
┌─────────────────────────────────────────────┐
│  PUBLIC METHOD — The Headline               │
│  "What does this code do?"                  │
│  Answer in 5-10 lines. Full story.          │
├─────────────────────────────────────────────┤
│  PRIVATE METHODS — The Paragraphs           │
│  "How does each step work?"                 │
│  One method per concern. Self-contained.    │
├─────────────────────────────────────────────┤
│  LEAVES — The Implementation Detail         │
│  "What are the exact mechanics?"            │
│  FlatMap chains. Error mapping. Builders.   │
│  Only read when debugging.                  │
└─────────────────────────────────────────────┘
```

A reviewer reading the headline knows the full behavior. A maintainer reading the paragraphs understands each step. Only a debugger — chasing a specific production issue — needs to reach the leaves.

---

## The Three Rules

### Rule 1: Headlines Are Short

The public method is a headline. It tells the full story in a sequence of named steps. No branching. No loops. No error handling plumbing. Just a clear, linear narrative.

#### Before: A wall of text

```kotlin
fun placeOrder(request: PlaceOrderRequest): OrderResult {
    val customer = customerRepository.findById(request.customerId)
        ?: return OrderResult.Failed("Customer not found")
    
    if (customer.subscription == null && request.isSubscription) {
        return OrderResult.Failed("Customer has no active subscription plan")
    }
    
    val items = request.items.map { item ->
        val product = productCatalog.findBySku(item.sku)
            ?: return OrderResult.Failed("Product ${item.sku} not found")
        if (product.availableStock < item.quantity) {
            return OrderResult.Failed("Insufficient stock for ${product.name}")
        }
        OrderLine(product, item.quantity, product.pricePerUnit * item.quantity)
    }
    
    val subtotal = items.sumOf { it.total }
    val shipping = if (subtotal > Money.of(50)) Money.ZERO 
                   else shippingCalculator.calculate(customer.address, items)
    val tax = taxService.calculate(subtotal, customer.address.region)
    val total = subtotal + shipping + tax
    
    if (customer.wallet.balance < total && customer.paymentMethod == null) {
        return OrderResult.Failed("No valid payment method")
    }
    
    val payment = paymentGateway.charge(customer.paymentMethod ?: customer.wallet, total)
    if (payment.failed) {
        return OrderResult.Failed("Payment failed: ${payment.errorMessage}")
    }
    
    val order = Order(
        id = OrderId.generate(),
        customer = customer,
        lines = items,
        subtotal = subtotal,
        shipping = shipping,
        tax = tax,
        total = total,
        payment = payment,
        status = OrderStatus.CONFIRMED,
        placedAt = Instant.now()
    )
    
    orderRepository.save(order)
    eventPublisher.publish(OrderPlaced(order))
    notificationService.sendConfirmation(customer, order)
    
    return OrderResult.Success(order)
}
```

This method does **everything**. To understand it, you must read every line. There's no way to skim. A reviewer must hold the entire flow in their head simultaneously.

#### After: A headline

```kotlin
fun placeOrder(request: PlaceOrderRequest): OrderResult {
    val customer = resolveCustomer(request) ?: return notFound("Customer")
    val items = resolveOrderLines(request) ?: return invalidItems()
    val pricing = calculatePricing(customer, items)
    val payment = chargeCustomer(customer, pricing.total) ?: return paymentFailed()
    val order = confirmOrder(customer, items, pricing, payment)
    publishOrderPlaced(order)
    return OrderResult.Success(order)
}
```

Seven lines. The full story. A reviewer reads this and knows exactly what `placeOrder` does — without reading a single implementation detail. They can approve the *behavior* in 10 seconds and only dive deeper if something looks wrong.

---

### Rule 2: Name the Steps

Method names describe **WHAT** happens, never **HOW**. The name is a contract with the reader: "this is what you'll find inside, no more, no less."

#### Before: Names that leak implementation

```kotlin
fun processRoastBatch(batchId: BatchId): BatchResult {
    val batch = loadBatchAndCheckNotAlreadyCompleted(batchId)
    val temps = readThermocoupleDataAndValidateRange(batch)
    val result = applyRoastCurveAlgorithmAndCalculateScore(batch, temps)
    updateDatabaseAndNotifyQualityTeam(batch, result)
    return result
}
```

These names tell you HOW the work is done (thermocouple, algorithm, database). That's implementation leaking into the headline. If the thermometer brand changes, the name becomes a lie.

#### After: Names that describe intent

```kotlin
fun completeRoastBatch(batchId: BatchId): BatchResult {
    val batch = findActiveBatch(batchId) ?: return BatchResult.NotFound
    val temperatures = recordTemperatureProfile(batch)
    val quality = assessRoastQuality(batch, temperatures)
    val result = finalizeBatch(batch, quality)
    notifyQualityTeam(result)
    return result
}
```

Each name answers "what happens at this step?" without revealing internals. `assessRoastQuality` might use an algorithm, a machine learning model, or a human taster — the headline doesn't care.

**Good names read like a story.** Read the method top to bottom and it narrates: "find the batch, record temperatures, assess quality, finalize it, notify the team." A new team member understands the domain flow without knowing any implementation.

---

### Rule 3: Complexity in the Leaves

The trunk (public + orchestrating private methods) stays clean. All mechanical complexity — error mapping, retries, object construction, stream operations — lives in leaf methods that are called but never call others.

#### Before: Complexity in the trunk

```kotlin
fun trackShipment(shipmentId: ShipmentId): ShipmentStatus {
    val shipment = shipmentRepository.findById(shipmentId)
        ?: throw ShipmentNotFoundException(shipmentId)
    
    val events = logisticsPartner.getTrackingEvents(shipment.trackingNumber)
        .filter { it.timestamp.isAfter(shipment.lastCheckedAt) }
        .sortedBy { it.timestamp }
        .map { event ->
            TrackingEvent(
                type = mapPartnerEventType(event.code),
                location = Location(
                    city = event.facility?.city ?: "Unknown",
                    country = event.facility?.country ?: shipment.origin.country,
                    coordinates = event.facility?.let { 
                        Coordinates(it.latitude, it.longitude) 
                    }
                ),
                timestamp = event.timestamp,
                description = translateEventDescription(event.code, event.details)
            )
        }
    
    if (events.any { it.type == EventType.EXCEPTION }) {
        alertService.raiseDeliveryException(shipment, events.filter { it.type == EventType.EXCEPTION })
    }
    
    val newStatus = events.lastOrNull()?.let { deriveStatus(it) } ?: shipment.currentStatus
    
    shipment.apply {
        this.currentStatus = newStatus
        this.trackingEvents.addAll(events)
        this.lastCheckedAt = Instant.now()
        this.estimatedDelivery = if (newStatus == ShipmentStatus.IN_TRANSIT) {
            estimateDeliveryDate(shipment.destination, events.last().location)
        } else shipment.estimatedDelivery
    }
    
    shipmentRepository.save(shipment)
    return newStatus
}
```

The trunk is doing leaf work: mapping objects, filtering streams, applying mutations. A reviewer has to parse every transformation to understand the flow.

#### After: Clean trunk, complex leaves

```kotlin
fun trackShipment(shipmentId: ShipmentId): ShipmentStatus {
    val shipment = findShipment(shipmentId)
    val newEvents = fetchNewTrackingEvents(shipment)
    handleExceptions(shipment, newEvents)
    val status = updateShipmentProgress(shipment, newEvents)
    return status
}

private fun fetchNewTrackingEvents(shipment: Shipment): List<TrackingEvent> {
    val partnerEvents = logisticsPartner.getTrackingEvents(shipment.trackingNumber)
    return partnerEvents
        .filter { it.timestamp.isAfter(shipment.lastCheckedAt) }
        .sortedBy { it.timestamp }
        .map { toTrackingEvent(it, shipment) }
}

private fun toTrackingEvent(event: PartnerEvent, shipment: Shipment): TrackingEvent {
    return TrackingEvent(
        type = mapPartnerEventType(event.code),
        location = resolveLocation(event.facility, shipment.origin),
        timestamp = event.timestamp,
        description = translateEventDescription(event.code, event.details)
    )
}

private fun resolveLocation(facility: Facility?, fallbackOrigin: Location): Location {
    return Location(
        city = facility?.city ?: "Unknown",
        country = facility?.country ?: fallbackOrigin.country,
        coordinates = facility?.let { Coordinates(it.latitude, it.longitude) }
    )
}
```

The trunk is 5 lines. Each private method handles exactly one concern. The leaf methods (`toTrackingEvent`, `resolveLocation`) contain the mechanical complexity — and they're small enough to verify at a glance.

---

## The Foundation Principle

> **The reader's time is more expensive than the writer's.**

Writing is a one-time cost. You write the method once. But it gets read:
- By the reviewer (at least once, often multiple times)
- By the next developer who touches adjacent code
- By the on-call engineer at 3am trying to find the bug
- By the AI assistant asked to modify it
- By future-you who forgot what past-you was thinking

Every reader pays the cost of complexity. The writer pays it once. **Optimize for the recurring cost.**

This means:
- More methods is better than fewer (if each is self-contained)
- More lines is better than fewer (if each carries one idea)
- More indirection is acceptable (if each layer has a clear purpose)
- Longer names are better than shorter (if they eliminate the need to read the body)

---

## The Relationship to Either/Arrow/Result Types

Primera Plana works **with or without** functional error handling. The philosophy is about structure, not about type systems. But it's worth showing how both approaches achieve the same shape.

### With early returns (nullable/imperative style)

```kotlin
fun placeOrder(request: PlaceOrderRequest): OrderResult {
    val customer = resolveCustomer(request) ?: return OrderResult.CustomerNotFound
    val items = resolveOrderLines(request) ?: return OrderResult.InvalidItems
    val pricing = calculatePricing(customer, items)
    val payment = chargeCustomer(customer, pricing.total) ?: return OrderResult.PaymentFailed
    val order = confirmOrder(customer, items, pricing, payment)
    return OrderResult.Success(order)
}
```

### With Either/Arrow (functional style)

```kotlin
fun placeOrder(request: PlaceOrderRequest): Either<OrderError, Order> = either {
    val customer = resolveCustomer(request).bind()
    val items = resolveOrderLines(request).bind()
    val pricing = calculatePricing(customer, items)
    val payment = chargeCustomer(customer, pricing.total).bind()
    confirmOrder(customer, items, pricing, payment)
}
```

### The key insight

**The headline reads the same way regardless of error handling strategy.**

Both versions are a sequence of named steps. Both push complexity into the leaves. Both allow a reviewer to understand the full flow in seconds. The error handling mechanism is an implementation choice — the philosophy is independent of it.

Arrow/Either enforces the philosophy at the type level: you *cannot* accidentally put complex logic in the happy path because the types won't let you. Early returns achieve the same shape through discipline rather than enforcement. Both are valid. Choose based on your team's preferences and ecosystem.

What matters is this: **the public method is a headline, no matter what tools you use to write it.**

---

## What This Is NOT

**Not a linter.** Though linters can help enforce it (method length checks, cyclomatic complexity thresholds). Primera Plana is a design philosophy — it guides decisions that no linter can make, like *what to name* a method or *where to draw* the boundary between headline and paragraph.

**Not language-specific.** The examples here use Kotlin-like pseudocode, but the philosophy applies to Swift, TypeScript, Python, Go, Rust — any language where you can extract methods and name them. Each language has its own idioms for achieving the newspaper shape.

**Not about reducing lines of code.** Primera Plana often *increases* total line count. That's fine. The goal isn't fewer lines — it's fewer lines *per cognitive unit*. A 200-line class with 15 small methods is easier to review than a 120-line class with 2 large methods.

**Not about dogma.** Some methods genuinely should be 20 lines because extracting would create meaningless fragments. The philosophy is a strong default, not a law. Break it when breaking it makes the code *more* readable — never when it makes it more clever.

---

## The Tradeoffs (Honesty Section)

Primera Plana has costs. Pretending otherwise would be dishonest.

**More methods means more navigation.** A reader sometimes needs to jump between methods to trace a flow. Modern IDEs mitigate this (Cmd+Click, peek definition), but it's real friction.

**More indirection can obscure.** If a "paragraph" method is only called once and is 3 lines long, extracting it might hurt more than it helps. Use judgment.

**Naming is hard.** The philosophy demands good names. Bad names (`doStep1`, `processData`, `handleStuff`) make the newspaper *less* readable than inline code. If you can't name it clearly, that's a signal the abstraction is wrong — not that you should inline it.

**Teams must agree.** One developer writing newspaper-style in a codebase that doesn't follow it creates inconsistency. The philosophy works best when adopted as a team standard.

These are real costs. We believe the benefits — faster reviews, easier debugging, better onboarding, AI-friendly structure — outweigh them decisively. But you should decide that for your team, not take our word for it.

---

## Summary

```
Primera Plana in one sentence:
    "Write code so a reviewer can approve it by reading only the public methods."

In three rules:
    1. Headlines are short (the public method is a sequence of steps)
    2. Name the steps (WHAT, not HOW)
    3. Complexity in the leaves (trunk stays clean)

The foundation:
    The reader's time is more expensive than the writer's.
```

The world changed. AI made writing nearly free. Reading is still expensive. Primera Plana is how we adapt: we write for readers first, writers second, and trust that the structure will serve both.

---

*Next: Read the language-specific guides for idiomatic implementations in [Kotlin](guides/kotlin.md), [Swift](guides/swift.md), and [TypeScript](guides/typescript.md).*
