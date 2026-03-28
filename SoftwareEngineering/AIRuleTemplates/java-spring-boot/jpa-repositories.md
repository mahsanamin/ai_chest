---
description: JPA repository conventions for Spring Boot applications
globs: ["**/repository/**/*.java", "**/repo/**/*.java"]
---

# JPA Repository Conventions

## Basic Pattern

Extend `JpaRepository<Entity, ID>` for full JPA features or `CrudRepository<Entity, ID>` for basics.

```java
package com.example.myapp.repository;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderRepository extends JpaRepository<Order, Long> {
}
```

## CRITICAL: Validate Before Querying (Defense in Depth)

Never pass raw input directly to repository methods. Always validate parameters in the service layer before calling the repository.

```java
// GOOD - validate first
public Order findOrder(Long id, String userHash) {
  Objects.requireNonNull(id, "Order ID must not be null");
  Objects.requireNonNull(userHash, "userHash must not be null");
  return orderRepository.findByIdAndUserHash(id, userHash)
      .orElseThrow(() -> new NotFoundException("Order not found"));
}

// BAD - no validation
public Order findOrder(Long id, String userHash) {
  return orderRepository.findByIdAndUserHash(id, userHash).orElseThrow();
}
```

## PostgreSQL vs H2 Compatibility

When using H2 for tests and PostgreSQL in production, handle type mismatches carefully.

### Nullable Parameters in Queries

Use COALESCE or IS NULL checks to handle nullable filter parameters:

```java
@Query("""
    SELECT o FROM Order o
    WHERE (:status IS NULL OR o.status = :status)
    AND (:userHash IS NULL OR o.userHash = :userHash)
    """)
List<Order> findByFilters(@Param("status") String status,
                          @Param("userHash") String userHash);
```

### CAST Patterns for Cross-DB Compatibility

```java
// BAD - breaks on H2
@Query("SELECT o FROM Order o WHERE o.createdAt > CAST(:date AS timestamp)")

// GOOD - works on both PostgreSQL and H2
@Query("SELECT o FROM Order o WHERE o.createdAt > :date")
List<Order> findAfterDate(@Param("date") Instant date);
```

### Type Mapping Table

| Java Type          | PostgreSQL         | H2                | Notes                              |
|--------------------|--------------------|--------------------|-------------------------------------|
| `String`           | `VARCHAR`/`TEXT`   | `VARCHAR`          | Use `@Column(length=...)` for VARCHAR |
| `Instant`          | `TIMESTAMPTZ`      | `TIMESTAMP`        | Prefer Instant over LocalDateTime   |
| `UUID`             | `UUID`             | `UUID`             | Works on both                       |
| `Long`             | `BIGINT`           | `BIGINT`           | Primary key default                 |
| `BigDecimal`       | `NUMERIC`          | `DECIMAL`          | Specify precision/scale             |
| `Boolean`          | `BOOLEAN`          | `BOOLEAN`          | Consistent                          |
| `enum` (STRING)    | `VARCHAR`          | `VARCHAR`          | Use `@Enumerated(EnumType.STRING)`  |
| `byte[]`           | `BYTEA`            | `BLOB`             | May need dialect handling           |
| `JsonNode`/`Map`   | `JSONB`            | `TEXT`/`VARCHAR`   | Requires custom type or converter   |

## Soft-Delete Pattern (Optional)

If your application uses soft deletes, add a `deletedAt` column and filter by default:

```java
@Entity
@Where(clause = "deleted_at IS NULL")
public class Order {
  // ...
  @Column(name = "deleted_at")
  private Instant deletedAt;
}
```

Repository:

```java
@Modifying
@Query("UPDATE Order o SET o.deletedAt = CURRENT_TIMESTAMP WHERE o.id = :id")
void softDelete(@Param("id") Long id);

@Query("SELECT o FROM Order o WHERE o.id = :id AND o.deletedAt IS NULL")
Optional<Order> findActiveById(@Param("id") Long id);
```

## Ownership Filtering Pattern (Optional)

When entities are scoped to a user (e.g., multi-tenant), add ownership checks:

```java
public interface OrderRepository extends JpaRepository<Order, Long> {
  Optional<Order> findByIdAndUserHash(Long id, String userHash);
  List<Order> findByUserHashAndStatus(String userHash, OrderStatus status);
}
```

Always enforce ownership in the service layer -- never trust the client to send the correct user context.

## Query Strategy: Prefer Method-Name Queries for Simple Cases

```java
// GOOD - simple, readable, Spring validates at startup
Optional<Order> findByIdAndUserHash(Long id, String userHash);
List<Order> findByStatusOrderByCreatedAtDesc(OrderStatus status);
boolean existsByProductIdAndUserHash(Long productId, String userHash);
long countByStatus(OrderStatus status);

// Use @Query only when method names become unwieldy or need joins
@Query("""
    SELECT o FROM Order o
    JOIN o.items i
    WHERE i.product.id = :productId
    AND o.status = :status
    """)
List<Order> findByProductAndStatus(@Param("productId") Long productId,
                                   @Param("status") OrderStatus status);
```

## Index Alignment

Ensure database indexes match your WHERE clause patterns:

```sql
-- If you query: findByUserHashAndStatus(...)
CREATE INDEX idx_order_userhash_status ON orders (user_hash, status);

-- If you query: findByProductIdAndCreatedAtAfter(...)
CREATE INDEX idx_order_product_created ON orders (product_id, created_at);
```

Column order in the index should match query patterns. Use `EXPLAIN ANALYZE` in PostgreSQL to verify index usage.

## @Modifying for DELETE/UPDATE

All DELETE and UPDATE queries require `@Modifying`:

```java
@Modifying
@Query("DELETE FROM OrderItem oi WHERE oi.order.id = :orderId")
void deleteByOrderId(@Param("orderId") Long orderId);

@Modifying
@Query("UPDATE Order o SET o.status = :status WHERE o.id = :id")
int updateStatus(@Param("id") Long id, @Param("status") OrderStatus status);
```

- `@Modifying` methods return `void` or `int` (affected row count).
- The persistence context is automatically cleared after execution when using `@Modifying(clearAutomatically = true)`.
- Always call these within a `@Transactional` service method.

## LazyInitializationException Prevention

### Problem

Accessing a lazy collection outside an active Hibernate session throws `LazyInitializationException`.

### Solutions (Pick One)

**1. Fetch from the child repository directly (preferred for simple cases):**

```java
// Instead of order.getItems(), query directly
List<OrderItem> items = orderItemRepository.findByOrderId(orderId);
```

**2. JOIN FETCH in JPQL:**

```java
@Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.id = :id")
Optional<Order> findByIdWithItems(@Param("id") Long id);
```

**3. @Transactional on the service method (use judiciously):**

```java
@Transactional(readOnly = true)
public OrderDto getOrderWithItems(Long id) {
  Order order = orderRepository.findById(id).orElseThrow();
  // Safe to access lazy collections within the transaction
  List<OrderItem> items = order.getItems();
  return mapToDto(order, items);
}
```

**4. @EntityGraph (for reusable fetch plans):**

```java
@EntityGraph(attributePaths = {"items", "items.product"})
Optional<Order> findWithItemsById(Long id);
```

### Anti-Patterns

- `FetchType.EAGER` on entity relationships (causes N+1 everywhere).
- `spring.jpa.open-in-view=true` (leaks DB connections into the view layer).

## Testing: @DataJpaTest

### Basic Setup

```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
// ^^^ Use this ONLY if testing against real PostgreSQL via Testcontainers.
//     Omit to use the default embedded H2.
class OrderRepositoryTest {

  @Autowired
  private OrderRepository orderRepository;

  @Autowired
  private TestEntityManager entityManager;

  @Test
  void shouldFindOrderByUserHash() {
    Order order = new Order();
    order.setUserHash("user-abc");
    order.setStatus(OrderStatus.PENDING);
    entityManager.persistAndFlush(order);

    Optional<Order> found = orderRepository.findByIdAndUserHash(
        order.getId(), "user-abc");

    assertThat(found).isPresent();
    assertThat(found.get().getUserHash()).isEqualTo("user-abc");
  }
}
```

### H2 vs PostgreSQL Gaps

| Gap                         | Mitigation                                           |
|-----------------------------|------------------------------------------------------|
| JSONB not supported in H2   | Use VARCHAR column + converter in test profile        |
| Case sensitivity differs    | Use LOWER() in queries or CI collation                |
| Sequence behavior differs   | Use `@GeneratedValue(strategy = IDENTITY)` or align   |
| Date/time function names    | Avoid DB-specific functions; use JPQL equivalents      |
| Partial indexes             | Not available in H2; test critical paths with Testcontainers |

For production-critical queries, consider **Testcontainers** with a real PostgreSQL instance.

## Complete Repository Example

```java
package com.example.myapp.repository;

import com.example.myapp.entity.Order;
import com.example.myapp.entity.OrderStatus;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OrderRepository extends JpaRepository<Order, Long> {

  // Simple method-name queries
  Optional<Order> findByIdAndUserHash(Long id, String userHash);
  List<Order> findByUserHashAndStatus(String userHash, OrderStatus status);
  boolean existsByProductIdAndUserHash(Long productId, String userHash);

  // Fetch with associations
  @EntityGraph(attributePaths = {"items"})
  Optional<Order> findWithItemsById(Long id);

  @Query("""
      SELECT o FROM Order o
      JOIN FETCH o.items i
      WHERE o.userHash = :userHash
      AND o.createdAt >= :since
      ORDER BY o.createdAt DESC
      """)
  List<Order> findRecentWithItems(@Param("userHash") String userHash,
                                  @Param("since") Instant since);

  // Filtered query with nullable params
  @Query("""
      SELECT o FROM Order o
      WHERE (:status IS NULL OR o.status = :status)
      AND (:userHash IS NULL OR o.userHash = :userHash)
      ORDER BY o.createdAt DESC
      """)
  List<Order> findByFilters(@Param("status") OrderStatus status,
                            @Param("userHash") String userHash);

  // Mutations
  @Modifying
  @Query("UPDATE Order o SET o.status = :status WHERE o.id = :id AND o.userHash = :userHash")
  int updateStatus(@Param("id") Long id,
                   @Param("userHash") String userHash,
                   @Param("status") OrderStatus status);

  @Modifying
  @Query("UPDATE Order o SET o.deletedAt = CURRENT_TIMESTAMP WHERE o.id = :id")
  void softDelete(@Param("id") Long id);
}
```

## Quick Reference

| Need                              | Pattern                                              |
|-----------------------------------|------------------------------------------------------|
| Simple lookup                     | Method-name query                                    |
| Multi-condition filter            | `@Query` with JPQL                                   |
| Nullable filter params            | `(:param IS NULL OR o.field = :param)`               |
| Fetch lazy associations           | `JOIN FETCH`, `@EntityGraph`, or child repo query    |
| Bulk update/delete                | `@Modifying` + `@Query`                              |
| Ownership scoping                 | Add `userHash` param to every query                  |
| Soft delete                       | `@Where` on entity + `deletedAt` column              |
| Cross-DB compatibility            | Avoid DB-specific SQL; use JPQL; test with Testcontainers |
| Index verification                | `EXPLAIN ANALYZE` in PostgreSQL                      |
| Test repo queries                 | `@DataJpaTest` + `TestEntityManager`                 |
