---
description: REST API conventions - request flow, validation, security, and DTO patterns
alwaysApply: true
---

# REST API Conventions

> Examples use Java/Spring, but the patterns (layered architecture, validation, DTOs) apply to any backend framework (Django, Rails, Express, .NET, FastAPI, etc.).

---

## 1. Request Flow

Every request follows this pipeline:

```
HTTP Request
  -> Controller    (routing, HTTP concerns, auth annotation)
  -> Validator     (input validation, returns error list)
  -> Service       (business logic, authorization, orchestration)
  -> Repository    (data access)
  -> Presenter     (response mapping, DTO construction)
HTTP Response
```

**Rules:**
- Each layer has a single responsibility
- Dependencies flow inward only (Controller -> Service -> Repository)
- Never skip layers (Controller must not call Repository directly)
- Each layer uses its own data types (DTOs in, entities in service, DTOs out)

---

## 2. URL Conventions

### Structure

```
/{version}/{resource}
/{version}/{resource}/{id}
/{version}/{resource}/{id}/{sub-resource}
```

### Rules

- Use kebab-case for multi-word resources: `/v1/order-items`, not `/v1/orderItems`
- Always version APIs: `/v1/orders`, `/v2/orders`
- Use nouns for resources, not verbs: `/v1/orders` not `/v1/create-order`
- Use plural nouns: `/v1/orders` not `/v1/order`
- Nest sub-resources one level max: `/v1/orders/{id}/items`
- Use query parameters for filtering: `/v1/orders?status=PENDING&customer-id=123`

### HTTP Methods

| Method | Usage | Idempotent |
|---|---|---|
| GET | Read resource(s) | Yes |
| POST | Create resource | No |
| PUT | Full replace | Yes |
| PATCH | Partial update | Yes |
| DELETE | Remove resource | Yes |

---

## 3. Controller Patterns

Controllers handle HTTP concerns only: routing, status codes, and authentication annotations.

```java
@RestController
@RequestMapping("/v1/orders")
public class OrderController {

    private final OrderService orderService;
    private final OrderValidator orderValidator;

    // Public endpoint (authenticated users)
    @GetMapping("/{id}")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<OrderResponse> getOrder(
            @PathVariable Long id,
            @AuthenticationPrincipal UserPrincipal principal) {

        OrderResponse response = orderService.getOrder(id, principal);
        return ResponseEntity.ok(response);
    }

    // Create with validation
    @PostMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<OrderResponse> createOrder(
            @RequestBody CreateOrderRequest request,
            @AuthenticationPrincipal UserPrincipal principal) {

        List<String> errors = orderValidator.validate(request);
        if (!errors.isEmpty()) {
            return ResponseEntity.badRequest()
                .body(OrderResponse.withErrors(errors));
        }

        OrderResponse response = orderService.createOrder(request, principal);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    // Internal/admin endpoint
    @GetMapping("/internal/metrics")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<OrderMetrics> getMetrics() {
        return ResponseEntity.ok(orderService.getMetrics());
    }

    // List with query parameters
    @GetMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<PagedResponse<OrderSummary>> listOrders(
            @Valid OrderSearchRequest searchRequest,
            @AuthenticationPrincipal UserPrincipal principal) {

        List<String> errors = orderValidator.validateSearch(searchRequest);
        if (!errors.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }

        return ResponseEntity.ok(
            orderService.searchOrders(searchRequest, principal));
    }
}
```

**Controller rules:**
- No business logic in controllers
- No direct repository calls
- Always pass the authenticated principal to the service layer
- Use `@PreAuthorize` or equivalent for role-based access
- Return appropriate HTTP status codes (201 for create, 204 for delete, etc.)
- Separate public and internal endpoints with clear access control

---

## 4. Validator Pattern

Validators return a list of error messages. They do not throw exceptions for expected validation failures.

```java
@Component
public class OrderValidator {

    public List<String> validate(CreateOrderRequest request) {
        List<String> errors = new ArrayList<>();

        if (request.getCustomerId() == null) {
            errors.add("customerId is required");
        }

        if (request.getItems() == null || request.getItems().isEmpty()) {
            errors.add("At least one order item is required");
        } else {
            for (int i = 0; i < request.getItems().size(); i++) {
                OrderItemRequest item = request.getItems().get(i);
                if (item.getProductId() == null) {
                    errors.add("items[" + i + "].productId is required");
                }
                if (item.getQuantity() == null || item.getQuantity() < 1) {
                    errors.add("items[" + i + "].quantity must be >= 1");
                }
            }
        }

        return errors;
    }
}
```

### CRITICAL: Query Parameter Validation - The All-Optional Problem

When a search/list endpoint has all optional parameters, you MUST ensure the caller provides at least something meaningful. Otherwise a bare `GET /v1/orders` returns the entire table.

```java
public List<String> validateSearch(OrderSearchRequest request) {
    List<String> errors = new ArrayList<>();

    // At least one filter must be provided
    boolean hasFilter = request.getCustomerId() != null
        || request.getStatus() != null
        || request.getDateFrom() != null;

    if (!hasFilter) {
        errors.add("At least one search filter is required: "
            + "customerId, status, or dateFrom");
    }

    // Date range validation
    if (request.getDateFrom() != null && request.getDateTo() != null) {
        if (request.getDateFrom().isAfter(request.getDateTo())) {
            errors.add("dateFrom must be before dateTo");
        }
        // Cap the range to prevent massive queries
        long daysBetween = ChronoUnit.DAYS.between(
            request.getDateFrom(), request.getDateTo());
        if (daysBetween > 90) {
            errors.add("Date range must not exceed 90 days");
        }
    }

    // Mutually exclusive parameters
    if (request.getCustomerId() != null && request.getCustomerEmail() != null) {
        errors.add("Provide customerId or customerEmail, not both");
    }

    // Pagination defaults and limits
    if (request.getPageSize() != null && request.getPageSize() > 100) {
        errors.add("pageSize must not exceed 100");
    }

    return errors;
}
```

**Query parameter validation rules:**
- Require at least one meaningful filter on list endpoints
- Validate date ranges (from < to, max span)
- Cap page size (default 20, max 100)
- Check for mutually exclusive parameters
- Validate enum values explicitly with a clear error message

---

## 5. Mapper Pattern

Mappers convert between layers. Keep them simple and free of logic.

```java
@Component
public class OrderMapper {

    public Order toEntity(CreateOrderRequest request) {
        Order order = new Order();
        order.setCustomerId(request.getCustomerId());
        order.setNote(request.getNote());
        order.setStatus(OrderStatus.PENDING);
        order.setCreatedAt(Instant.now());
        return order;
    }

    public OrderResponse toResponse(Order order, Customer customer,
                                     List<OrderItem> items) {
        return OrderResponse.builder()
            .id(order.getId())
            .customerName(customer.getName())
            .status(order.getStatus().name())
            .items(items.stream()
                .map(this::toItemResponse)
                .collect(toList()))
            .createdAt(order.getCreatedAt())
            .build();
    }

    private OrderItemResponse toItemResponse(OrderItem item) {
        return OrderItemResponse.builder()
            .productId(item.getProductId())
            .quantity(item.getQuantity())
            .unitPrice(item.getUnitPrice())
            .build();
    }
}
```

**Mapper rules:**
- No business logic in mappers (no conditional transformations based on business rules)
- No database or service calls in mappers
- One mapper per aggregate root
- Mappers are stateless

---

## 6. Service Pattern

Services contain business logic, authorization checks, and orchestrate calls to repositories.

```java
@Service
public class OrderService {

    private final OrderRepository orderRepository;
    private final CustomerRepository customerRepository;
    private final OrderMapper orderMapper;

    // Always check ownership/authorization in the service layer
    public OrderResponse getOrder(Long orderId, UserPrincipal principal) {
        Order order = orderRepository.findById(orderId)
            .orElseThrow(() -> new ResourceNotFoundException("Order", orderId));

        // Ownership check: users can only see their own orders
        if (!principal.hasRole("ADMIN")) {
            Customer customer = customerRepository
                .findByUserId(principal.getUserId())
                .orElseThrow(() -> new ForbiddenException("No customer profile"));

            if (!order.getCustomerId().equals(customer.getId())) {
                throw new ForbiddenException("Not authorized to view this order");
            }
        }

        Customer customer = customerRepository.findById(order.getCustomerId())
            .orElseThrow();
        List<OrderItem> items = orderItemRepository
            .findAllByOrderId(orderId);

        return orderMapper.toResponse(order, customer, items);
    }

    @Transactional
    public OrderResponse createOrder(CreateOrderRequest request,
                                      UserPrincipal principal) {
        // Verify the customer belongs to the authenticated user
        Customer customer = customerRepository.findById(request.getCustomerId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "Customer", request.getCustomerId()));

        if (!principal.hasRole("ADMIN")
                && !customer.getUserId().equals(principal.getUserId())) {
            throw new ForbiddenException("Cannot create orders for other customers");
        }

        Order order = orderMapper.toEntity(request);
        order = orderRepository.save(order);

        List<OrderItem> items = createOrderItems(order.getId(), request.getItems());

        return orderMapper.toResponse(order, customer, items);
    }
}
```

**Service rules:**
- All business logic lives here
- Always verify ownership/authorization (do not trust the controller alone)
- Use `@Transactional` only for write operations, and keep them short
- Throw meaningful exceptions (not generic 500s)
- Never return entities to the controller; always use DTOs/response objects

---

## 7. Repository Pattern

Repositories handle data access only. No business logic.

```java
@Repository
public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByCustomerId(Long customerId);

    List<Order> findByCustomerIdAndStatus(Long customerId, OrderStatus status);

    @Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.id = :id")
    Optional<Order> findByIdWithItems(@Param("id") Long id);

    List<Order> findAllByIdIn(Collection<Long> ids);

    @Query("SELECT o FROM Order o WHERE o.customerId = :customerId "
         + "AND o.createdAt BETWEEN :from AND :to")
    List<Order> findByCustomerIdAndDateRange(
        @Param("customerId") Long customerId,
        @Param("from") Instant from,
        @Param("to") Instant to);
}
```

**Repository rules:**
- No business logic in repository methods
- Provide batch methods (`findAllByIdIn`) for any entity queried in loops
- Use `JOIN FETCH` for known eager-loading needs
- Name methods consistently: `findBy...`, `findAllBy...`, `countBy...`

---

## 8. Security Checklist

Before shipping any endpoint:

- [ ] Endpoint has authentication annotation (`@PreAuthorize`, `@Secured`, or equivalent)
- [ ] Service layer verifies resource ownership (not just authentication)
- [ ] Admin-only endpoints check for admin role explicitly
- [ ] Internal endpoints are not exposed on public routes
- [ ] User input is validated before reaching business logic
- [ ] IDs from the URL are verified against the authenticated user's permissions
- [ ] Sensitive data (passwords, tokens) is never returned in responses
- [ ] Rate limiting is configured for public-facing endpoints
- [ ] Error messages do not leak internal details (stack traces, SQL, table names)

---

## 9. Request / Response DTO Conventions

### Request DTOs

```java
public class CreateOrderRequest {
    @NotNull
    private Long customerId;

    private String note;               // Optional

    @NotEmpty
    private List<OrderItemRequest> items;

    // Getters, setters (or use records/Lombok)
}

public class OrderItemRequest {
    @NotNull
    private Long productId;

    @NotNull
    @Min(1)
    private Integer quantity;
}

public class OrderSearchRequest {
    private Long customerId;           // Optional
    private String status;             // Optional
    private LocalDate dateFrom;        // Optional
    private LocalDate dateTo;          // Optional
    private Integer page;              // Default: 0
    private Integer pageSize;          // Default: 20, max: 100
}
```

### Response DTOs

```java
public class OrderResponse {
    private Long id;
    private String customerName;       // Resolved, not just an ID
    private String status;
    private List<OrderItemResponse> items;
    private Instant createdAt;
    private List<String> errors;       // Present only when validation fails

    public static OrderResponse withErrors(List<String> errors) {
        OrderResponse r = new OrderResponse();
        r.setErrors(errors);
        return r;
    }
}

public class PagedResponse<T> {
    private List<T> data;
    private int page;
    private int pageSize;
    private long totalElements;
    private int totalPages;
}
```

**DTO rules:**
- Request DTOs contain only input fields (no ID for create, ID in URL for update)
- Response DTOs resolve references (show `customerName`, not just `customerId`)
- Use a standard paged response wrapper for list endpoints
- Never expose entity classes directly in the API
- Error responses follow a consistent structure across all endpoints

---

## 10. Error Response Convention

Use a consistent error format across all endpoints:

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Request validation failed",
    "details": [
      "customerId is required",
      "items[0].quantity must be >= 1"
    ]
  }
}
```

```java
public class ErrorResponse {
    private String code;       // Machine-readable error code
    private String message;    // Human-readable summary
    private List<String> details;  // Specific field-level errors

    // Standard codes: VALIDATION_FAILED, NOT_FOUND, FORBIDDEN,
    //                 CONFLICT, INTERNAL_ERROR
}
```

**Use a global exception handler** to ensure all errors follow this format:

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(ResourceNotFoundException ex) {
        return ResponseEntity.status(404)
            .body(new ErrorResponse("NOT_FOUND", ex.getMessage(), null));
    }

    @ExceptionHandler(ForbiddenException.class)
    public ResponseEntity<ErrorResponse> handleForbidden(ForbiddenException ex) {
        return ResponseEntity.status(403)
            .body(new ErrorResponse("FORBIDDEN", ex.getMessage(), null));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        log.error("Unhandled exception", ex);
        return ResponseEntity.status(500)
            .body(new ErrorResponse("INTERNAL_ERROR",
                "An unexpected error occurred", null));
    }
}
```
