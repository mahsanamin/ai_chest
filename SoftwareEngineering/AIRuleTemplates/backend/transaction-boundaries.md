---
description: Transaction boundary rules - keep transactions short and DB-only
alwaysApply: true
---

# Transaction Boundary Rules

> Examples use Java/Spring `@Transactional`, but the same principles apply to any framework with transaction management (Django `@transaction.atomic`, Rails `ActiveRecord::Base.transaction`, .NET `TransactionScope`, etc.).

---

## Core Rule

**@Transactional = database operations only.**

A transaction holds a database connection from start to finish. Anything slow or external inside that block keeps the connection locked, starving the connection pool under load.

---

## Never Do Inside a Transaction

| Operation | Why It's Dangerous |
|---|---|
| HTTP/API calls | Network latency (100ms-30s) holds the connection |
| Thread.sleep / polling | Connection held for entire wait duration |
| File I/O (read/write) | Disk latency is unpredictable |
| Message queue publish/consume | Network call + possible retry |
| Long computations | CPU work doesn't need a DB connection |
| Sending emails/notifications | External service call |
| Cache population from external source | May involve HTTP calls |

---

## The Safe Pattern

Separate orchestration from transactional work.

```java
// Orchestration method - NOT transactional
public OrderResult processOrder(Long orderId) {
    // Step 1: Read (quick transaction)
    Order order = readOrder(orderId);

    // Step 2: External call (no transaction)
    PaymentResult payment = paymentClient.charge(order.getTotal());

    // Step 3: Write (quick transaction)
    return saveOrderWithPayment(order.getId(), payment);
}

// Quick read - transactional
@Transactional(readOnly = true)
public Order readOrder(Long orderId) {
    return orderRepository.findById(orderId).orElseThrow();
}

// Quick write - transactional
@Transactional
public OrderResult saveOrderWithPayment(Long orderId, PaymentResult payment) {
    Order order = orderRepository.findById(orderId).orElseThrow();
    order.setPaymentId(payment.getId());
    order.setStatus(Status.PAID);
    orderRepository.save(order);
    return new OrderResult(order);
}
```

**Key points:**
- The orchestration method has no `@Transactional` annotation
- Each transactional method does one quick DB operation
- External calls happen between transactions, not inside them

---

## Before-Writing Checklist

Before adding `@Transactional` to any method, verify:

- [ ] The method contains ONLY database reads and writes
- [ ] No HTTP client calls anywhere in the call chain
- [ ] No file system operations
- [ ] No Thread.sleep or waiting
- [ ] No message queue operations
- [ ] No calls to methods that might hide any of the above
- [ ] The transaction will complete in milliseconds, not seconds
- [ ] `readOnly = true` is set if the method only reads data

---

## Common Patterns

### Polling Loop

```java
// BAD: Transaction open for entire polling duration
@Transactional
public void waitForResult(Long jobId) {
    while (true) {
        Job job = jobRepository.findById(jobId).orElseThrow();
        if (job.isComplete()) return;
        Thread.sleep(1000); // Connection held!
    }
}

// GOOD: Each check is a separate transaction
public void waitForResult(Long jobId) {
    while (true) {
        if (checkJobStatus(jobId)) return;
        Thread.sleep(1000); // No connection held
    }
}

@Transactional(readOnly = true)
public boolean checkJobStatus(Long jobId) {
    return jobRepository.findById(jobId)
        .map(Job::isComplete)
        .orElseThrow();
}
```

### Batch Processing

```java
// BAD: One enormous transaction
@Transactional
public void processAllOrders(List<Long> orderIds) {
    for (Long id : orderIds) {
        Order order = orderRepository.findById(id).orElseThrow();
        externalService.validate(order);  // HTTP call inside transaction!
        order.setStatus(Status.VALIDATED);
        orderRepository.save(order);
    }
}

// GOOD: Transaction per item, external call outside
public void processAllOrders(List<Long> orderIds) {
    for (Long id : orderIds) {
        Order order = readOrder(id);                    // Quick read tx
        ValidationResult result = externalService.validate(order);  // No tx
        saveValidation(id, result);                     // Quick write tx
    }
}
```

---

## Red Flags for Code Review

| Red Flag | Problem |
|---|---|
| `@Transactional` on a method calling `RestTemplate`/`WebClient`/`HttpClient` | External call inside transaction |
| `@Transactional` on a method with `Thread.sleep()` | Sleeping with connection held |
| `@Transactional` on a method longer than 20 lines | Likely doing too much in one transaction |
| `@Transactional` on a controller method | Transaction scope is too broad |
| `@Transactional` on a method sending messages to a queue | Message broker call inside transaction |
| `@Transactional` without `readOnly = true` on a read-only method | Unnecessary write locks |
| Nested `@Transactional` methods with different propagation | Hard to reason about, likely a bug |
| `@Transactional` on a method that calls other `@Transactional` methods | Verify propagation behavior is intentional |
