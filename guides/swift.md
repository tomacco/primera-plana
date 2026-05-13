# Primera Plana — Swift Guide

Code reads like a newspaper. Public methods are headlines. Private methods are paragraphs. Complexity lives in the leaves. The reader decides how deep to go.

---

## The Philosophy in Five Rules

1. **Headlines are short** — public methods are 5-10 lines of well-named steps
2. **Name the steps** — method names describe WHAT, not HOW
3. **Complexity in the leaves** — error handling, object construction, logging live in private methods
4. **The reader's time > the writer's time**
5. **The philosophy works with or without `Result` types** — guard-let and early return are equally valid

---

## Swift's Natural Strengths

Swift was born for Primera Plana. The language _wants_ you to write clear, safe, top-down code:

- **`guard let`** naturally creates headline-style early exits
- **Enums with associated values** model domain errors without exceptions
- **Extensions** let you physically separate headlines from leaves
- **Protocols** define boundaries that keep the trunk clean
- **`async/await`** reads sequentially — perfect for newspaper-style flow
- **Access control** (`private`, `internal`, `public`) maps directly to headlines vs paragraphs

---

## Core Patterns

### Guard-Let as Headlines

`guard let` is your primary tool for keeping headlines flat:

```swift
func placeOrder(_ request: OrderRequest) async -> Result<Order, OrderError> {
    guard let customer = await resolveCustomer(request.customerId) else {
        return .failure(.customerNotFound(request.customerId))
    }
    guard let subscription = await findActiveSubscription(customer) else {
        return .failure(.noActiveSubscription(customer.id))
    }
    guard let roastBatch = await reserveFromBatch(subscription.blend, subscription.quantity) else {
        return .failure(.insufficientStock(subscription.blend))
    }

    let order = buildOrder(customer: customer, subscription: subscription, batch: roastBatch)
    await persist(order)
    await notifyFulfillment(order)
    return .success(order)
}
```

Each `guard let` is a headline sentence. The reader sees the story: resolve customer, find subscription, reserve stock, build order, persist, notify. Done.

### Result Type for Explicit Failures

Swift's built-in `Result<Success, Failure>` keeps error handling visible without polluting headlines:

```swift
enum OrderError: Error {
    case customerNotFound(CustomerId)
    case noActiveSubscription(CustomerId)
    case insufficientStock(BlendName)
    case paymentDeclined(reason: String)
    case shipmentSchedulingFailed(reason: String)
}
```

The headline returns `Result`. The leaves _produce_ the errors. The caller decides how to handle them.

### Async/Await — Sequential Headlines

Swift concurrency reads top-to-bottom, exactly how Primera Plana wants:

```swift
func processRoastBatch(_ batchId: BatchId) async -> Result<CompletedBatch, BatchError> {
    guard let batch = await fetchBatch(batchId) else {
        return .failure(.batchNotFound(batchId))
    }
    guard batch.status == .roasting else {
        return .failure(.invalidTransition(from: batch.status, to: .completed))
    }

    let qualityResult = await runQualityCheck(batch)
    guard case .success(let grade) = qualityResult else {
        return qualityResult.mapToFailure()
    }

    let completedBatch = finalizeBatch(batch, grade: grade)
    await persist(completedBatch)
    await notifyPartners(completedBatch)
    return .success(completedBatch)
}
```

### Extensions — Organize the Leaves

Keep headlines in one file, leaves in an extension. The reader sees the story first:

```swift
// PlaceSubscriptionOrderService.swift — THE HEADLINES
final class PlaceSubscriptionOrderService {
    private let customerRepository: CustomerRepository
    private let subscriptionRepository: SubscriptionRepository
    private let inventoryService: InventoryService
    private let orderRepository: OrderRepository
    private let fulfillmentNotifier: FulfillmentNotifier

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
        await notifyFulfillment(order)
        return .success(order)
    }
}
```

```swift
// PlaceSubscriptionOrderService+Leaves.swift — THE PARAGRAPHS
extension PlaceSubscriptionOrderService {
    private func resolveCustomer(_ id: CustomerId) async -> Customer? {
        do {
            let customer = try await customerRepository.find(id)
            guard customer.isActive else {
                logger.warning("Customer \(id) is inactive")
                return nil
            }
            return customer
        } catch {
            logger.error("Failed to resolve customer \(id): \(error)")
            return nil
        }
    }

    private func findActiveSubscription(_ customer: Customer) async -> Subscription? {
        let subscriptions = await subscriptionRepository.findByCustomer(customer.id)
        return subscriptions.first(where: { $0.isActive && $0.nextDeliveryDate <= .now.addingDays(7) })
    }

    private func reserveStock(_ subscription: Subscription) async -> ReservedStock? {
        let availability = await inventoryService.checkAvailability(
            blend: subscription.blend,
            quantity: subscription.quantity
        )
        guard availability.hasSufficient else { return nil }
        return await inventoryService.reserve(
            blend: subscription.blend,
            quantity: subscription.quantity,
            reason: .subscriptionOrder(subscription.id)
        )
    }

    private func buildOrder(customer: Customer, subscription: Subscription, stock: ReservedStock) -> Order {
        Order(
            id: OrderId.generate(),
            customerId: customer.id,
            subscriptionId: subscription.id,
            blend: subscription.blend,
            quantity: subscription.quantity,
            roastPreference: subscription.roastPreference,
            shippingAddress: customer.defaultAddress,
            reservationId: stock.reservationId,
            status: .placed,
            placedAt: .now
        )
    }

    private func persist(_ order: Order) async {
        do {
            try await orderRepository.save(order)
        } catch {
            logger.error("Failed to persist order \(order.id): \(error)")
        }
    }

    private func notifyFulfillment(_ order: Order) async {
        await fulfillmentNotifier.orderPlaced(order)
    }
}
```

### Protocols — Clean Boundaries

Protocols are your "ports." They define what the headline needs without revealing how the leaves work:

```swift
protocol InventoryService {
    func checkAvailability(blend: BlendName, quantity: Grams) async -> Availability
    func reserve(blend: BlendName, quantity: Grams, reason: ReservationReason) async -> ReservedStock?
}

protocol FulfillmentNotifier {
    func orderPlaced(_ order: Order) async
    func batchReady(_ batch: CompletedBatch) async
}
```

The headline depends on the protocol. The leaf (implementation) lives elsewhere. Readers don't need to know about HTTP clients or message queues to understand the story.

### Computed Properties — When Appropriate

Use computed properties when the result is _derived_ from existing state with no side effects:

```swift
// Good — simple derivation
struct Subscription {
    let startDate: Date
    let frequencyDays: Int
    let lastDeliveryDate: Date?

    var nextDeliveryDate: Date {
        (lastDeliveryDate ?? startDate).addingDays(frequencyDays)
    }

    var isActive: Bool {
        status == .active && !isPaused
    }
}
```

Extract a method when the logic is complex or has side effects:

```swift
// This should be a method, not a computed property
func calculateShippingCost(for address: Address) -> Decimal { ... }
```

### No Force Unwrapping

Force unwrapping (`!`) is banned for the same reason as Kotlin's `!!` — it crashes at runtime with no context. Always use `guard let`, `if let`, or `fatalError("context")` for truly impossible cases:

```swift
// NEVER
let customer = dictionary["customer"]!

// ALWAYS
guard let customer = dictionary["customer"] else {
    logger.error("Missing customer in dictionary — this indicates a data corruption bug")
    return .failure(.internalError)
}
```

---

## Full Example: Before and After

### PlaceSubscriptionOrderService — Before

```swift
class SubscriptionOrderService {
    func placeOrder(customerId: String, subscriptionId: String) async throws -> Order {
        let customerResult = try await APIClient.shared.request(
            url: URL(string: "https://api.tostado.com/customers/\(customerId)")!,
            method: .get
        )
        guard let customerData = customerResult.data else {
            throw NSError(domain: "OrderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Customer not found"])
        }
        let customer = try JSONDecoder().decode(Customer.self, from: customerData)
        if customer.status != "active" {
            throw NSError(domain: "OrderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Customer inactive"])
        }

        let subResult = try await APIClient.shared.request(
            url: URL(string: "https://api.tostado.com/subscriptions/\(subscriptionId)")!,
            method: .get
        )
        guard let subData = subResult.data else {
            throw NSError(domain: "OrderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Subscription not found"])
        }
        let subscription = try JSONDecoder().decode(Subscription.self, from: subData)
        if subscription.customerId != customerId {
            throw NSError(domain: "OrderError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Subscription doesn't belong to customer"])
        }
        if subscription.status != "active" {
            throw NSError(domain: "OrderError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Subscription inactive"])
        }
        if subscription.nextDeliveryDate > Date().addingTimeInterval(7 * 24 * 60 * 60) {
            throw NSError(domain: "OrderError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Too early for next delivery"])
        }

        let inventoryResult = try await APIClient.shared.request(
            url: URL(string: "https://api.tostado.com/inventory/check")!,
            method: .post,
            body: try JSONEncoder().encode(["blend": subscription.blend, "quantity": "\(subscription.quantity)"])
        )
        guard let invData = inventoryResult.data else {
            throw NSError(domain: "OrderError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Inventory check failed"])
        }
        let inventory = try JSONDecoder().decode(InventoryCheck.self, from: invData)
        if inventory.available < subscription.quantity {
            throw NSError(domain: "OrderError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Insufficient stock"])
        }

        let order = Order(
            id: UUID().uuidString,
            customerId: customer.id,
            subscriptionId: subscription.id,
            blend: subscription.blend,
            quantity: subscription.quantity,
            roastPreference: subscription.roastPreference,
            shippingAddress: customer.addresses.first!,
            status: "placed",
            placedAt: Date()
        )

        let orderData = try JSONEncoder().encode(order)
        try await APIClient.shared.request(
            url: URL(string: "https://api.tostado.com/orders")!,
            method: .post,
            body: orderData
        )

        try await APIClient.shared.request(
            url: URL(string: "https://api.tostado.com/notifications/fulfillment")!,
            method: .post,
            body: try JSONEncoder().encode(["orderId": order.id, "type": "new_order"])
        )

        return order
    }
}
```

**Problems:**
- 60+ lines in a single method — no skimming possible
- Force unwraps (`first!`, URL `!`)
- Raw strings for status checks
- No domain error types — NSError with magic codes
- HTTP details mixed with business logic
- Impossible to review in a PR

### PlaceSubscriptionOrderService — After

```swift
// PlaceSubscriptionOrderService.swift
final class PlaceSubscriptionOrderService {
    private let customers: CustomerRepository
    private let subscriptions: SubscriptionRepository
    private let inventory: InventoryService
    private let orders: OrderRepository
    private let fulfillment: FulfillmentNotifier

    init(
        customers: CustomerRepository,
        subscriptions: SubscriptionRepository,
        inventory: InventoryService,
        orders: OrderRepository,
        fulfillment: FulfillmentNotifier
    ) {
        self.customers = customers
        self.subscriptions = subscriptions
        self.inventory = inventory
        self.orders = orders
        self.fulfillment = fulfillment
    }

    func execute(_ request: PlaceOrderRequest) async -> Result<Order, OrderError> {
        guard let customer = await resolveActiveCustomer(request.customerId) else {
            return .failure(.customerNotFound(request.customerId))
        }
        guard let subscription = await findEligibleSubscription(request.subscriptionId, for: customer) else {
            return .failure(.subscriptionNotEligible(request.subscriptionId))
        }
        guard let stock = await reserveStock(for: subscription) else {
            return .failure(.insufficientStock(subscription.blend))
        }

        let order = buildOrder(customer: customer, subscription: subscription, stock: stock)
        await save(order)
        await notifyFulfillment(order)
        return .success(order)
    }
}
```

```swift
// PlaceSubscriptionOrderService+Leaves.swift
extension PlaceSubscriptionOrderService {
    private func resolveActiveCustomer(_ id: CustomerId) async -> Customer? {
        guard let customer = await customers.find(id) else {
            logger.warning("Customer \(id) not found")
            return nil
        }
        guard customer.isActive else {
            logger.info("Customer \(id) is not active, skipping order")
            return nil
        }
        return customer
    }

    private func findEligibleSubscription(_ id: SubscriptionId, for customer: Customer) async -> Subscription? {
        guard let subscription = await subscriptions.find(id) else { return nil }
        guard subscription.customerId == customer.id else {
            logger.warning("Subscription \(id) does not belong to customer \(customer.id)")
            return nil
        }
        guard subscription.isActive else { return nil }
        guard subscription.isEligibleForDelivery else { return nil }
        return subscription
    }

    private func reserveStock(for subscription: Subscription) async -> ReservedStock? {
        await inventory.reserve(
            blend: subscription.blend,
            quantity: subscription.quantity,
            reason: .subscriptionOrder(subscription.id)
        )
    }

    private func buildOrder(customer: Customer, subscription: Subscription, stock: ReservedStock) -> Order {
        Order(
            id: .generate(),
            customerId: customer.id,
            subscriptionId: subscription.id,
            blend: subscription.blend,
            quantity: subscription.quantity,
            roastPreference: subscription.roastPreference,
            shippingAddress: customer.defaultAddress,
            reservationId: stock.id,
            status: .placed,
            placedAt: .now
        )
    }

    private func save(_ order: Order) async {
        do {
            try await orders.save(order)
            logger.info("Order \(order.id) persisted")
        } catch {
            logger.error("Failed to persist order \(order.id): \(error)")
        }
    }

    private func notifyFulfillment(_ order: Order) async {
        await fulfillment.orderPlaced(order)
    }
}
```

**What changed:**
- The `execute` method is 10 lines — a reviewer reads it in seconds
- Each step has a name that explains itself
- Error handling lives in the leaves
- No force unwraps anywhere
- Domain errors are explicit enums
- Infrastructure details are behind protocols
- The extension physically separates headlines from paragraphs

---

### ProcessRoastBatchService — Before

```swift
class RoastBatchManager {
    func completeBatch(batchId: String) async throws -> RoastBatch {
        let batch = try await db.query("SELECT * FROM roast_batches WHERE id = ?", [batchId]).first!
        if batch["status"] as! String != "roasting" {
            throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "Batch not in roasting state"])
        }

        // Run quality checks
        let temperature = batch["final_temp"] as! Double
        let duration = batch["duration_minutes"] as! Int
        let moistureContent = batch["moisture_pct"] as! Double

        var grade: String
        if temperature >= 200 && temperature <= 230 && duration >= 12 && duration <= 18 && moistureContent < 12.0 {
            grade = "A"
        } else if temperature >= 190 && temperature <= 240 && duration >= 10 && duration <= 20 && moistureContent < 14.0 {
            grade = "B"
        } else {
            grade = "C"
        }

        if grade == "C" {
            // Notify quality team
            try await NotificationService.shared.send(
                to: "quality@tostado.com",
                subject: "Low grade batch \(batchId)",
                body: "Batch \(batchId) received grade C. Temp: \(temperature), Duration: \(duration), Moisture: \(moistureContent)"
            )
            try await db.execute("UPDATE roast_batches SET status = 'failed_qa', grade = ? WHERE id = ?", [grade, batchId])
            throw NSError(domain: "", code: 2, userInfo: [NSLocalizedDescriptionKey: "Batch failed QA"])
        }

        try await db.execute("UPDATE roast_batches SET status = 'completed', grade = ?, completed_at = ? WHERE id = ?", [grade, Date(), batchId])

        // Update farmer yield records
        let farmerId = batch["farmer_id"] as! String
        try await db.execute("UPDATE farmer_yields SET total_completed = total_completed + 1, last_batch_grade = ? WHERE farmer_id = ?", [grade, farmerId])

        // Notify logistics
        try await APIClient.shared.request(
            url: URL(string: "https://api.tostado.com/logistics/ready")!,
            method: .post,
            body: try JSONEncoder().encode(["batchId": batchId, "grade": grade])
        )

        let updated = try await db.query("SELECT * FROM roast_batches WHERE id = ?", [batchId]).first!
        return try JSONDecoder().decode(RoastBatch.self, from: JSONSerialization.data(withJSONObject: updated))
    }
}
```

### ProcessRoastBatchService — After

```swift
// ProcessRoastBatchService.swift
final class ProcessRoastBatchService {
    private let batches: RoastBatchRepository
    private let farmers: FarmerYieldRepository
    private let logistics: LogisticsNotifier
    private let qualityTeam: QualityTeamNotifier

    func execute(_ batchId: BatchId) async -> Result<CompletedBatch, BatchError> {
        guard let batch = await fetchBatch(batchId) else {
            return .failure(.notFound(batchId))
        }
        guard batch.isInRoastingState else {
            return .failure(.invalidTransition(from: batch.status, to: .completed))
        }

        let grade = assessQuality(batch.metrics)

        guard grade.passesMinimumThreshold else {
            await handleFailedQA(batch, grade: grade)
            return .failure(.failedQualityCheck(batchId, grade: grade))
        }

        let completed = finalizeBatch(batch, grade: grade)
        await persist(completed)
        await updateFarmerRecords(batch.farmerId, grade: grade)
        await notifyLogistics(completed)
        return .success(completed)
    }
}
```

```swift
// ProcessRoastBatchService+Leaves.swift
extension ProcessRoastBatchService {
    private func fetchBatch(_ id: BatchId) async -> RoastBatch? {
        await batches.find(id)
    }

    private func assessQuality(_ metrics: RoastMetrics) -> QualityGrade {
        switch (metrics.temperature, metrics.durationMinutes, metrics.moisturePercent) {
        case (200...230, 12...18, ..<12.0):
            return .gradeA
        case (190...240, 10...20, ..<14.0):
            return .gradeB
        default:
            return .gradeC
        }
    }

    private func handleFailedQA(_ batch: RoastBatch, grade: QualityGrade) async {
        await qualityTeam.reportFailedBatch(batch, grade: grade)
        await batches.updateStatus(batch.id, to: .failedQA)
        logger.warning("Batch \(batch.id) failed QA with grade \(grade)")
    }

    private func finalizeBatch(_ batch: RoastBatch, grade: QualityGrade) -> CompletedBatch {
        CompletedBatch(
            id: batch.id,
            farmerId: batch.farmerId,
            blend: batch.blend,
            quantity: batch.quantity,
            grade: grade,
            metrics: batch.metrics,
            completedAt: .now
        )
    }

    private func persist(_ batch: CompletedBatch) async {
        do {
            try await batches.save(batch)
        } catch {
            logger.error("Failed to persist completed batch \(batch.id): \(error)")
        }
    }

    private func updateFarmerRecords(_ farmerId: FarmerId, grade: QualityGrade) async {
        await farmers.recordCompletedBatch(farmerId, grade: grade)
    }

    private func notifyLogistics(_ batch: CompletedBatch) async {
        await logistics.batchReady(batch)
    }
}
```

---

### SwiftUI ViewModel — The Pattern Applies to UI Too

Primera Plana is not just for services. ViewModels benefit enormously:

#### Before

```swift
class SubscriptionViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var isLoading = false
    @Published var error: String?

    func loadSubscriptions() async {
        isLoading = true
        error = nil
        do {
            let response = try await URLSession.shared.data(from: URL(string: "https://api.tostado.com/me/subscriptions")!)
            let decoded = try JSONDecoder().decode([Subscription].self, from: response.0)
            await MainActor.run {
                self.subscriptions = decoded.filter { $0.status == "active" }.sorted { $0.nextDeliveryDate < $1.nextDeliveryDate }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to load subscriptions: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func pauseSubscription(_ id: String) async {
        do {
            var request = URLRequest(url: URL(string: "https://api.tostado.com/subscriptions/\(id)/pause")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let _ = try await URLSession.shared.data(for: request)
            await MainActor.run {
                if let index = self.subscriptions.firstIndex(where: { $0.id == id }) {
                    self.subscriptions[index].status = "paused"
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to pause subscription: \(error.localizedDescription)"
            }
        }
    }
}
```

#### After

```swift
// SubscriptionListViewModel.swift — HEADLINES
@MainActor
final class SubscriptionListViewModel: ObservableObject {
    @Published private(set) var state: ViewState<[ActiveSubscription]> = .idle
    private let subscriptionService: SubscriptionService

    func loadSubscriptions() async {
        state = .loading
        let result = await subscriptionService.fetchActiveSubscriptions()
        state = mapToViewState(result)
    }

    func pauseSubscription(_ id: SubscriptionId) async {
        let result = await subscriptionService.pause(id)
        handlePauseResult(result, id: id)
    }

    func resumeSubscription(_ id: SubscriptionId) async {
        let result = await subscriptionService.resume(id)
        handleResumeResult(result, id: id)
    }
}
```

```swift
// SubscriptionListViewModel+Leaves.swift — PARAGRAPHS
extension SubscriptionListViewModel {
    private func mapToViewState(_ result: Result<[ActiveSubscription], SubscriptionError>) -> ViewState<[ActiveSubscription]> {
        switch result {
        case .success(let subscriptions):
            return subscriptions.isEmpty ? .empty : .loaded(subscriptions)
        case .failure(let error):
            return .error(userFacingMessage(for: error))
        }
    }

    private func handlePauseResult(_ result: Result<Void, SubscriptionError>, id: SubscriptionId) {
        switch result {
        case .success:
            removeFromList(id)
        case .failure(let error):
            state = .error(userFacingMessage(for: error))
        }
    }

    private func handleResumeResult(_ result: Result<Void, SubscriptionError>, id: SubscriptionId) {
        switch result {
        case .success:
            Task { await loadSubscriptions() }
        case .failure(let error):
            state = .error(userFacingMessage(for: error))
        }
    }

    private func removeFromList(_ id: SubscriptionId) {
        if case .loaded(var subscriptions) = state {
            subscriptions.removeAll { $0.id == id }
            state = subscriptions.isEmpty ? .empty : .loaded(subscriptions)
        }
    }

    private func userFacingMessage(for error: SubscriptionError) -> String {
        switch error {
        case .networkUnavailable:
            return "Check your connection and try again."
        case .subscriptionNotFound:
            return "This subscription is no longer available."
        case .serverError:
            return "Something went wrong. Please try again later."
        }
    }
}
```

The ViewModel headline reads like a user story. The paragraphs handle the messy reality of state management.

---

## Supporting Types

Good Primera Plana code uses expressive types. Here are the domain types used in the examples above:

```swift
// MARK: - Value Types
struct CustomerId: Hashable, CustomStringConvertible {
    let value: String
    var description: String { value }
}

struct BatchId: Hashable, CustomStringConvertible {
    let value: String
    var description: String { value }
    static func generate() -> BatchId { BatchId(value: UUID().uuidString) }
}

// MARK: - Domain Enums
enum QualityGrade: String {
    case gradeA, gradeB, gradeC

    var passesMinimumThreshold: Bool {
        self != .gradeC
    }
}

enum OrderStatus {
    case placed, confirmed, roasting, shipped, delivered, cancelled
}

// MARK: - View State (generic for any screen)
enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case empty
    case error(String)
}
```

---

## Guiding Principles — Swift Edition

| Principle | Swift Implementation |
|-----------|---------------------|
| Headlines are short | `guard let` + named method calls |
| Name the steps | Method names are verb phrases: `resolveActiveCustomer`, `reserveStock` |
| Complexity in the leaves | Extensions physically separate leaves from headlines |
| No force unwrapping | `guard let` / `if let` / `Result` — never `!` |
| Explicit errors | Enums with associated values — never `NSError` with magic codes |
| Protocols as boundaries | The headline depends on _what_, not _how_ |
| Computed properties for derivation | Simple, side-effect-free derivations only |
| Access control tells the story | `public/internal` = headline, `private` = paragraph |

---

## When to Break the Rules

- **Truly trivial methods** (1-2 lines) don't need to be extracted
- **`fatalError("context")`** is acceptable for programmer errors that indicate bugs, never for user-facing conditions
- **Performance-critical code** may need different structure — but document why
- **SwiftUI body** properties can be longer than 10 lines when the view hierarchy is flat and readable

---

## The Test: Can a Reviewer Skim It?

Open a PR diff. Read only the headline method. If you understand what the code does without scrolling into the leaves, Primera Plana is working.

The reader's time is always more valuable than the writer's time. Write code that respects that.
