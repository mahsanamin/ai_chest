---
description: Database migration rules - versioning, naming, safety, and index guidelines
alwaysApply: true
---

# Database Migration Rules

> Examples use raw SQL (compatible with Flyway, Liquibase SQL changelogs, Alembic raw SQL, Django RunSQL, etc.). Adapt the versioning scheme to your migration tool's conventions.

---

## 1. Versioning Strategy

Use a major version + sub-version scheme to allow inserting migrations without conflicts.

```
V{major}__{sub}__{description}.sql
```

**Examples:**
```
V47__1__create_orders_table.sql
V47__2__add_status_column_to_orders.sql
V47__3__create_order_items_table.sql
V48__1__add_shipping_address_to_orders.sql
```

**Rules:**
- Major version increments for each feature or sprint
- Sub-versions allow multiple developers to work within the same major version
- Never modify a migration that has been applied to any shared environment
- If you need to fix a mistake, create a new migration

---

## 2. Naming Conventions

Migration descriptions should clearly state the operation and target:

| Operation | Naming Pattern | Example |
|---|---|---|
| Create table | `create_{table}_table` | `create_orders_table` |
| Add column | `add_{column}_to_{table}` | `add_status_to_orders` |
| Drop column | `drop_{column}_from_{table}` | `drop_legacy_flag_from_users` |
| Create index | `add_index_{table}_{columns}` | `add_index_orders_customer_id` |
| Add constraint | `add_{constraint_type}_{table}_{column}` | `add_fk_order_items_product_id` |
| Data migration | `migrate_{description}` | `migrate_status_enum_values` |
| Alter column | `alter_{column}_in_{table}` | `alter_amount_in_orders` |

---

## 3. Content Guidelines

### Always Use IF NOT EXISTS / IF EXISTS

Every DDL statement must be idempotent. Migrations may be re-run during recovery.

```sql
-- Tables
CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Columns (PostgreSQL)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'orders'
        AND column_name = 'shipped_at'
    ) THEN
        ALTER TABLE public.orders ADD COLUMN shipped_at TIMESTAMP;
    END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_customer_id
    ON public.orders (customer_id);

-- Drop
DROP TABLE IF EXISTS legacy_orders;
DROP INDEX IF EXISTS idx_old_orders_date;
```

### Specify Schema Explicitly

Never rely on the default schema. Always qualify table names.

```sql
-- BAD
CREATE TABLE orders (...);

-- GOOD
CREATE TABLE public.orders (...);
```

### Add Comments to Tables and Columns

Document the purpose of new tables and non-obvious columns.

```sql
COMMENT ON TABLE public.orders IS 'Customer purchase orders';
COMMENT ON COLUMN public.orders.status IS 'Order lifecycle state: PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED';
COMMENT ON COLUMN public.orders.idempotency_key IS 'Client-provided key to prevent duplicate order creation';
```

### Always Define Defaults for New Non-Null Columns

Adding a NOT NULL column to an existing table requires a default, or the migration will fail if the table has data.

```sql
-- BAD: Fails if orders table has rows
ALTER TABLE public.orders ADD COLUMN priority VARCHAR(20) NOT NULL;

-- GOOD: Safe for existing rows
ALTER TABLE public.orders ADD COLUMN priority VARCHAR(20) NOT NULL DEFAULT 'NORMAL';
```

### Foreign Key Constraints

Always name constraints explicitly. Auto-generated names differ across databases and are hard to reference later.

```sql
ALTER TABLE public.order_items
    ADD CONSTRAINT fk_order_items_order_id
    FOREIGN KEY (order_id)
    REFERENCES public.orders (id);

ALTER TABLE public.order_items
    ADD CONSTRAINT fk_order_items_product_id
    FOREIGN KEY (product_id)
    REFERENCES public.products (id);
```

---

## 4. Index Creation Guidelines

### When to Create an Index

- Column is used in `WHERE` clauses in queries
- Column is used in `JOIN` conditions
- Column is used in `ORDER BY` on large result sets
- Column is a foreign key (most databases don't auto-index FK columns)
- Column is used in unique constraints that need enforcement

### When NOT to Create an Index

- Table has very few rows (< 1,000) and is not expected to grow
- Column has very low cardinality (e.g., boolean with 50/50 distribution)
- Column is rarely queried
- Table is write-heavy and rarely read (each index slows writes)
- An existing composite index already covers the query

### Single-Column vs Composite Indexes

```sql
-- Single column: Good for simple lookups
CREATE INDEX IF NOT EXISTS idx_orders_customer_id
    ON public.orders (customer_id);

-- Composite: Good when queries always filter on both columns
-- Column order matters: most selective column first
CREATE INDEX IF NOT EXISTS idx_orders_customer_id_status
    ON public.orders (customer_id, status);

-- Partial index: Good for filtering a common subset
CREATE INDEX IF NOT EXISTS idx_orders_pending
    ON public.orders (customer_id)
    WHERE status = 'PENDING';
```

**Composite index rules:**
- The leftmost column(s) can serve queries on their own
- `(customer_id, status)` serves queries on `customer_id` alone AND `customer_id + status`
- `(customer_id, status)` does NOT efficiently serve queries on `status` alone
- Order columns from most selective to least selective

### Unique Indexes

Use for business-rule uniqueness enforcement:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email
    ON public.users (email);

-- Partial unique index: unique only among active records
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_active_email
    ON public.users (email)
    WHERE deleted_at IS NULL;
```

---

## 5. Dependency Handling

### Foreign Key Order

If table B references table A, the migration creating table A must run before the migration creating table B.

```
V10__1__create_customers_table.sql    -- First: parent table
V10__2__create_orders_table.sql       -- Second: references customers
V10__3__create_order_items_table.sql  -- Third: references orders and products
```

### Cross-Schema References

If referencing a table in another schema, ensure the other schema's migration has already run. Document the dependency.

```sql
-- Depends on: V8__1__create_products_table.sql (catalog schema)
ALTER TABLE public.order_items
    ADD CONSTRAINT fk_order_items_product_id
    FOREIGN KEY (product_id)
    REFERENCES catalog.products (id);
```

---

## 6. Testing Checklist

Before committing a migration:

- [ ] Runs successfully on an empty database (fresh install)
- [ ] Runs successfully on a database with existing data
- [ ] Is idempotent (can run twice without error, using IF NOT EXISTS / IF EXISTS)
- [ ] New NOT NULL columns have DEFAULT values
- [ ] Foreign keys reference existing tables (check migration order)
- [ ] Index names are unique and follow naming convention
- [ ] Constraint names are explicit, not auto-generated
- [ ] Schema is explicitly specified in all table references
- [ ] No `DROP` without `IF EXISTS`
- [ ] No `CREATE` without `IF NOT EXISTS`
- [ ] Large table alterations are tested for lock duration
- [ ] Data migrations handle NULL values and edge cases

---

## 7. Troubleshooting

### Migration Fails on Existing Data

**Symptom:** `NOT NULL constraint violation` when adding a column.
**Fix:** Add a DEFAULT or make the migration two steps (add nullable, backfill, add NOT NULL).

```sql
-- Step 1: Add nullable column
ALTER TABLE public.orders ADD COLUMN region VARCHAR(50);

-- Step 2: Backfill
UPDATE public.orders SET region = 'UNKNOWN' WHERE region IS NULL;

-- Step 3: Add NOT NULL (separate migration after backfill is verified)
ALTER TABLE public.orders ALTER COLUMN region SET NOT NULL;
```

### Migration Locks Table for Too Long

**Symptom:** Adding index on large table causes downtime.
**Fix:** Use `CONCURRENTLY` (PostgreSQL) or equivalent.

```sql
-- PostgreSQL: Non-blocking index creation
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_created_at
    ON public.orders (created_at);
```

Note: `CONCURRENTLY` cannot run inside a transaction block. Configure your migration tool accordingly.

### Duplicate Migration Version

**Symptom:** Two developers pick the same version number.
**Fix:** Use sub-versions. Each developer takes a different sub-version within the agreed major version.

### Foreign Key Fails Because Referenced Table Doesn't Exist

**Symptom:** `relation "X" does not exist`
**Fix:** Check migration ordering. The parent table migration must have a lower version number.

---

## 8. Data Migration Safety

When migrating existing data:

```sql
-- Always wrap data migrations in a transaction (if your tool doesn't already)
BEGIN;

-- Use explicit WHERE to avoid unintended updates
UPDATE public.orders
SET status = 'CONFIRMED'
WHERE status = 'APPROVED'
  AND created_at < '2025-01-01';

-- Verify row count before committing
-- (Check in application or manually)

COMMIT;
```

**Rules for data migrations:**
- Always have a rollback plan (reverse UPDATE, backup, etc.)
- Test on a copy of production data first
- Log the number of rows affected
- Never delete data without a backup or soft-delete mechanism
- Keep data migrations separate from schema migrations
