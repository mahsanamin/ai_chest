---
description: React form handling conventions
globs: ["**/*.tsx"]
---

# React Form Handling

## Stack

- **React Hook Form** v7 -- form state and submission
- **Zod** -- schema validation
- **@hookform/resolvers** -- connects Zod to RHF via `zodResolver`

## Form Pattern

```typescript
import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { z } from 'zod';

const orderSchema = z.object({
  productName: z.string().min(1, 'Product name is required'),
  quantity: z.coerce.number().int().min(1, 'Quantity must be at least 1'),
  notes: z.string().optional(),
});

type OrderFormValues = z.infer<typeof orderSchema>;

export const OrderForm = ({ onSubmit }: { onSubmit: (data: OrderFormValues) => void }) => {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<OrderFormValues>({
    resolver: zodResolver(orderSchema),
    defaultValues: { productName: '', quantity: 1, notes: '' },
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="productName">Product Name</label>
        <input id="productName" {...register('productName')} />
        {errors.productName && <span role="alert">{errors.productName.message}</span>}
      </div>

      <div>
        <label htmlFor="quantity">Quantity</label>
        <input id="quantity" type="number" {...register('quantity')} />
        {errors.quantity && <span role="alert">{errors.quantity.message}</span>}
      </div>

      <div>
        <label htmlFor="notes">Notes</label>
        <textarea id="notes" {...register('notes')} />
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Submitting...' : 'Create Order'}
      </button>
    </form>
  );
};
```

## Form Element Rules

- **Always add `noValidate`** to `<form>` elements -- let Zod handle validation, not the browser.
- **Always set `type` on buttons:**
  - `type="submit"` for form submission.
  - `type="button"` for everything else (prevents accidental submission).
- **Always use `htmlFor`** on labels pointing to the input `id`.

## FormField Component Pattern

For reusable form fields, wrap the registration logic:

```typescript
import { type FieldError, type UseFormRegisterReturn } from 'react-hook-form';

interface FormFieldProps {
  label: string;
  id: string;
  registration: UseFormRegisterReturn;
  error?: FieldError;
  type?: string;
}

export const FormField = ({ label, id, registration, error, type = 'text' }: FormFieldProps) => (
  <div>
    <label htmlFor={id}>{label}</label>
    <input id={id} type={type} aria-invalid={!!error} {...registration} />
    {error && <span role="alert">{error.message}</span>}
  </div>
);
```

## Validation with Zod

### Schema Patterns

```typescript
// String with translated error keys
const nameField = z.string().min(1, 'validation.required');

// Email
const emailField = z.string().email('validation.invalidEmail');

// Number from string input
const quantityField = z.coerce.number().int().positive('validation.positiveNumber');

// Enum
const statusField = z.enum(['active', 'inactive'], {
  errorMap: () => ({ message: 'validation.invalidStatus' }),
});

// Conditional validation
const shippingSchema = z.discriminatedUnion('method', [
  z.object({ method: z.literal('pickup'), storeId: z.string().min(1) }),
  z.object({ method: z.literal('delivery'), address: z.string().min(1) }),
]);
```

### i18n Error Keys

Use translation keys in Zod error messages so errors can be localized:

```typescript
const schema = z.object({
  name: z.string().min(1, 'errors.nameRequired'),
  email: z.string().email('errors.invalidEmail'),
});

// In the component, pass the message through your i18n function:
{errors.name && <span role="alert">{t(errors.name.message)}</span>}
```

## Schema Testing

Always test schemas independently:

```typescript
import { orderSchema } from './orderSchema';

describe('orderSchema', () => {
  it('should accept valid order data', () => {
    const result = orderSchema.safeParse({ productName: 'Widget', quantity: 3 });
    expect(result.success).toBe(true);
  });

  it('should reject empty product name', () => {
    const result = orderSchema.safeParse({ productName: '', quantity: 1 });
    expect(result.success).toBe(false);
  });

  it('should reject zero quantity', () => {
    const result = orderSchema.safeParse({ productName: 'Widget', quantity: 0 });
    expect(result.success).toBe(false);
  });

  it('should coerce string quantity to number', () => {
    const result = orderSchema.safeParse({ productName: 'Widget', quantity: '5' });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.quantity).toBe(5);
    }
  });
});
```

## Auto-Save Pattern

For forms that save automatically on change:

```typescript
import { useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { useDebouncedCallback } from 'use-debounce';

export const AutoSaveForm = ({ defaultValues, onSave }: AutoSaveFormProps) => {
  const { register, watch, handleSubmit } = useForm({ defaultValues });

  const debouncedSave = useDebouncedCallback((data) => {
    onSave(data);
  }, 500);

  useEffect(() => {
    const subscription = watch((data) => {
      debouncedSave(data);
    });
    return () => subscription.unsubscribe();
  }, [watch, debouncedSave]);

  return (
    <form onSubmit={handleSubmit(onSave)} noValidate>
      {/* fields */}
    </form>
  );
};
```

## Common Mistakes

| Mistake                                 | Fix                                                    |
|-----------------------------------------|--------------------------------------------------------|
| Missing `noValidate` on `<form>`        | Always add `noValidate`; Zod handles validation        |
| Button without `type`                   | Add `type="submit"` or `type="button"` explicitly      |
| Duplicating Zod schema as TS interface  | Use `z.infer<typeof schema>` to derive the type        |
| Not disabling submit during submission  | Use `isSubmitting` from `formState`                    |
| Calling `reset()` without new values    | Pass `defaultValues` to `reset(newValues)`             |
| Forgetting `z.coerce` for number inputs | HTML inputs are always strings; use `z.coerce.number()`|
| No `role="alert"` on error messages     | Add for accessibility and Testing Library queries      |
