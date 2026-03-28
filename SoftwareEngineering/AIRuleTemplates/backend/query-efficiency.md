---
description: Query efficiency rules - prevent N+1 queries, ensure selective data access
alwaysApply: true
---

# Query Efficiency Rules

> These examples use Java/JPA, but the principles apply to any ORM (Django ORM, ActiveRecord, SQLAlchemy, Entity Framework, etc.). The anti-patterns are universal.

---

## 1. Query Selectivity

### Rule: Use the Most Selective Identifier Available

If you already have an entity's ID, query by that ID. Never traverse relationships or scan collections when a direct lookup is possible.

```java
// BAD: Scanning when you have the ID
Order order = orderRepository.findAll().stream()
    .filter(o -> o.getId().equals(orderId))
    .findFirst().orElseThrow();

// GOOD: Direct lookup
Order order = orderRepository.findById(orderId).orElseThrow();
```

### Rule: Never Assume a Table is Small

Today's 50-row lookup table is next year's 50,000-row table. Always write queries as if the table could grow by 1000x.

```java
// BAD: "Categories is a small table"
List<Category> allCategories = categoryRepository.findAll();
Category match = allCategories.stream()
    .filter(c -> c.getName().equals(name))
    .findFirst().orElseThrow();

// GOOD: Let the database filter
Category match = categoryRepository.findByName(name).orElseThrow();
```

### Rule: Push Filtering to the Database

The database has indexes, query optimizers, and is designed for filtering. Your application code is not.

```java
// BAD: Fetch all, filter in Java
List<Order> allOrders = orderRepository.findByCustomerId(customerId);
List<Order> pending = allOrders.stream()
    .filter(o -> o.getStatus() == Status.PENDING)
    .collect(toList());

// GOOD: Filter in the query
List<Order> pending = orderRepository.findByCustomerIdAndStatus(customerId, Status.PENDING);
```

---

## 2. Query Minimality / N+1 Prevention

An N+1 query occurs when you execute 1 query to get a list of N items, then execute N additional queries to get related data for each item. This is the single most common performance killer in ORM-based applications.

### Pattern 1: Repository Call Inside a Loop

The most obvious form. Easy to spot, easy to fix.

```java
// BAD: N+1 - one query per order
List<Long> orderIds = getOrderIds();
for (Long orderId : orderIds) {
    Order order = orderRepository.findById(orderId).orElseThrow(); // N queries
    process(order);
}

// GOOD: Single batch query
List<Long> orderIds = getOrderIds();
List<Order> orders = orderRepository.findAllByIdIn(orderIds); // 1 query
for (Order order : orders) {
    process(order);
}
```

### Pattern 2: Lazy Collection Access in a Loop

Harder to spot because the query is hidden behind a getter.

```java
// BAD: Each getItems() triggers a lazy-load query
List<Order> orders = orderRepository.findByCustomerId(customerId);
for (Order order : orders) {
    int itemCount = order.getItems().size(); // N queries (lazy load)
    log.info("Order {} has {} items", order.getId(), itemCount);
}

// GOOD: Fetch with items eagerly
List<Order> orders = orderRepository.findByCustomerIdWithItems(customerId); // JOIN FETCH
for (Order order : orders) {
    int itemCount = order.getItems().size(); // No additional query
    log.info("Order {} has {} items", order.getId(), itemCount);
}
```

The repository method:
```java
@Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.customerId = :customerId")
List<Order> findByCustomerIdWithItems(@Param("customerId") Long customerId);
```

### Pattern 3: Helper Method Hiding a Query

The most dangerous form. The N+1 is invisible at the call site.

```java
// BAD: Looks innocent, but getActiveDiscount() queries the DB
for (Product product : products) {
    BigDecimal price = pricingHelper.getActiveDiscount(product.getId()); // Hidden query!
    applyDiscount(product, price);
}

// GOOD: Batch fetch, then use the map
Set<Long> productIds = products.stream().map(Product::getId).collect(toSet());
Map<Long, BigDecimal> discounts = pricingService.getActiveDiscounts(productIds); // 1 query
for (Product product : products) {
    BigDecimal price = discounts.getOrDefault(product.getId(), BigDecimal.ZERO);
    applyDiscount(product, price);
}
```

### Pattern 4: Re-fetching Data You Already Have

If a caller passes you an entity or its data, do not re-fetch it.

```java
// BAD: Caller already has the order, but service re-fetches it
public void processOrder(Long orderId) {
    Order order = orderRepository.findById(orderId).orElseThrow(); // Unnecessary
    // ... process
}

// GOOD: Accept the entity if the caller has it
public void processOrder(Order order) {
    // ... process directly
}
```

### Pattern 5: Chained N+1

Multiple levels of lazy loading, each multiplying the query count.

```java
// BAD: O(orders * items * suppliers) queries
for (Order order : orders) {
    for (OrderItem item : order.getItems()) {          // N queries
        Supplier s = item.getProduct().getSupplier();   // N*M queries
    }
}
```

Fix with a single query that joins all needed relations, or use the DataContext pattern below.

---

## 3. DataContext Pattern

For complex operations that need data from multiple sources, pre-fetch everything into a context object. This makes query counts explicit and testable.

```java
public class OrderProcessingContext {
    private final Map<Long, Order> ordersById;
    private final Map<Long, Customer> customersById;
    private final Map<Long, List<OrderItem>> itemsByOrderId;
    private final Map<Long, Product> productsById;

    public static OrderProcessingContext build(List<Long> orderIds,
                                                OrderRepository orderRepo,
                                                CustomerRepository customerRepo,
                                                OrderItemRepository itemRepo,
                                                ProductRepository productRepo) {
        List<Order> orders = orderRepo.findAllByIdIn(orderIds);          // 1 query
        Set<Long> customerIds = orders.stream()
            .map(Order::getCustomerId).collect(toSet());
        Map<Long, Customer> customers = customerRepo.findAllByIdIn(customerIds)
            .stream().collect(toMap(Customer::getId, identity()));        // 1 query

        List<OrderItem> items = itemRepo.findAllByOrderIdIn(orderIds);   // 1 query
        Set<Long> productIds = items.stream()
            .map(OrderItem::getProductId).collect(toSet());
        Map<Long, Product> products = productRepo.findAllByIdIn(productIds)
            .stream().collect(toMap(Product::getId, identity()));         // 1 query

        // Total: 4 queries regardless of data size
        return new OrderProcessingContext(
            orders.stream().collect(toMap(Order::getId, identity())),
            customers,
            items.stream().collect(groupingBy(OrderItem::getOrderId)),
            products
        );
    }

    // Getters that never trigger queries
    public Customer getCustomerForOrder(Order order) {
        return customersById.get(order.getCustomerId());
    }

    public List<OrderItem> getItemsForOrder(Long orderId) {
        return itemsByOrderId.getOrDefault(orderId, List.of());
    }
}
```

**When to use DataContext:**
- Processing a batch of entities that need related data
- Complex report generation
- Any operation where you need 3+ types of related entities

---

## 4. Before-Writing Checklist

Before writing or reviewing any data access code, verify:

- [ ] No repository/DAO calls inside any loop (for, while, forEach, stream.map)
- [ ] No lazy-loaded collection accessed inside a loop
- [ ] No helper/utility method called in a loop that might hide a query
- [ ] All available IDs are used for direct lookups (not scanning)
- [ ] Filtering happens in SQL, not in application code
- [ ] Data that the caller already has is not re-fetched
- [ ] Batch operations use `IN` clauses or bulk methods
- [ ] For 3+ related entity types, consider a DataContext

---

## 5. Red Flags Table

| Code Pattern | Problem | Fix |
|---|---|---|
| `repository.find*()` inside `for`/`while`/`forEach` | N+1 query | Batch fetch before the loop |
| `entity.getCollection().size()` in a loop | Lazy-load N+1 | JOIN FETCH or batch fetch |
| `helperService.getX(id)` in a loop | Hidden N+1 | Batch method returning Map |
| `repository.findAll()` + `.stream().filter()` | Full table scan + app filtering | Add a query method with WHERE clause |
| `repository.findById(id)` when caller has entity | Redundant query | Pass entity instead of ID |
| `repository.findByX(x)` without index on X | Full table scan | Add database index |
| `@Transactional` on method with loop queries | Holding connection during N+1 | Fix N+1 first, then scope transaction |
| Nested loops accessing relationships | O(N*M) or worse queries | Flatten with DataContext |
