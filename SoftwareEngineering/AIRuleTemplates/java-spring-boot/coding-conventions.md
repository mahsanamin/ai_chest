---
description: Java and Spring Boot coding conventions
alwaysApply: true
globs: ["**/*.java"]
---

# Java / Spring Boot Coding Conventions

## Transaction Boundaries

See [transaction-boundaries.md](transaction-boundaries.md) for detailed transaction management rules.

## Formatting

- **Line length:** 120 characters max.
- **Indentation:** 2 spaces (no tabs).
- **Braces:** K&R style (opening brace on same line).
- **Switch statements:** Always include a `default` case, even if it throws.

```java
switch (status) {
  case ACTIVE -> handleActive();
  case INACTIVE -> handleInactive();
  default -> throw new IllegalStateException("Unexpected status: " + status);
}
```

## Imports

- **No wildcard imports** (`import java.util.*` is forbidden).
- **Static imports first**, then standard library, then third-party, then project.
- **No fully-qualified class names inline** -- always import at the top.

```java
import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;

import org.springframework.stereotype.Service;

import com.example.myapp.entity.Order;
```

## Annotations

- Place annotations on their own line, one per line.
- Order: framework annotations first (`@Service`, `@RestController`), then cross-cutting (`@Transactional`, `@Validated`), then field-level (`@Column`, `@NotNull`).

```java
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class OrderService {
```

## Whitespace and Vertical Spacing

- One blank line between methods.
- No blank line after opening brace or before closing brace.
- Group related statements; separate logical blocks with one blank line.

## Constants

Extract a value to a constant only when it is used **3 or more times**. Avoid premature constant extraction for single-use values.

```java
// GOOD - used in multiple places
private static final int MAX_RETRY_ATTEMPTS = 3;

// BAD - only used once, just inline it
private static final String ORDER_NOT_FOUND = "Order not found";
```

## Lombok Best Practices

| Annotation                | Use                                      | Notes                                     |
|---------------------------|------------------------------------------|-------------------------------------------|
| `@Data`                   | DTOs and value objects                   | Avoid on JPA entities (breaks equals/hash)|
| `@Value`                  | Immutable DTOs                           | Makes all fields `private final`          |
| `@RequiredArgsConstructor`| Service/component constructor injection  | Preferred over `@Autowired`               |
| `@Builder`                | Complex object construction              | Pair with `@AllArgsConstructor(access = PRIVATE)` |
| `@Slf4j`                  | Logging                                  | Use everywhere instead of manual logger   |
| `@Getter` / `@Setter`     | JPA entities                             | Use instead of `@Data` on entities        |
| `@ToString.Exclude`       | Lazy associations on entities            | Prevents LazyInitializationException      |
| `@EqualsAndHashCode`      | Override only with `onlyExplicitlyIncluded` on entities | Use business key, not ID |

### JPA Entity Pattern

```java
@Entity
@Getter
@Setter
@NoArgsConstructor
@EqualsAndHashCode(onlyExplicitlyIncluded = true)
public class Order {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @EqualsAndHashCode.Include
  private String orderNumber;

  @ToString.Exclude
  @OneToMany(mappedBy = "order")
  private List<OrderItem> items;
}
```

## Javadoc

- **Required on:** public API classes, interfaces, and non-trivial public methods.
- **Not required on:** simple getters/setters, test methods, private methods with clear names.
- Use `@param`, `@return`, and `@throws` tags for public methods.

```java
/**
 * Calculates the total price for an order, including tax and discounts.
 *
 * @param orderId the order to calculate
 * @return the total price as a BigDecimal
 * @throws NotFoundException if the order does not exist
 */
public BigDecimal calculateTotal(Long orderId) {
```
