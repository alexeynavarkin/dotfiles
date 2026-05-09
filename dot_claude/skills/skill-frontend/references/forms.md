# Forms — React Hook Form + Zod

The default for any form with more than one field or any validation. Uncontrolled under the hood (fast), typesafe via Zod.

## Basic form

```tsx
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const signupSchema = z.object({
  email: z.string().email("Enter a valid email"),
  password: z.string().min(8, "At least 8 characters"),
});

type SignupValues = z.infer<typeof signupSchema>;

export function SignupForm({ onSubmit }: { onSubmit: (values: SignupValues) => Promise<void> }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<SignupValues>({
    resolver: zodResolver(signupSchema),
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4" noValidate>
      <div className="space-y-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          type="email"
          autoComplete="email"
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? "email-error" : undefined}
          {...register("email")}
        />
        {errors.email && (
          <p id="email-error" role="alert" className="text-sm text-destructive">
            {errors.email.message}
          </p>
        )}
      </div>

      <div className="space-y-2">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          type="password"
          autoComplete="new-password"
          aria-invalid={!!errors.password}
          aria-describedby={errors.password ? "password-error" : undefined}
          {...register("password")}
        />
        {errors.password && (
          <p id="password-error" role="alert" className="text-sm text-destructive">
            {errors.password.message}
          </p>
        )}
      </div>

      <Button type="submit" disabled={isSubmitting} className="w-full">
        {isSubmitting ? "Signing up…" : "Sign up"}
      </Button>
    </form>
  );
}
```

Key points:
- `noValidate` on the form — we handle validation, not the browser.
- `aria-invalid` + `aria-describedby` wire errors to inputs for screen readers.
- `role="alert"` on error messages so they're announced when they appear.
- `autoComplete` attributes are not optional — they make password managers work.
- Submit button is disabled and relabeled during submission.

## Using shadcn's Form components

shadcn/ui ships a `Form` wrapper that reduces boilerplate. Prefer it in shadcn projects:

```tsx
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from "@/components/ui/form";

<Form {...form}>
  <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
    <FormField
      control={form.control}
      name="email"
      render={({ field }) => (
        <FormItem>
          <FormLabel>Email</FormLabel>
          <FormControl>
            <Input type="email" autoComplete="email" {...field} />
          </FormControl>
          <FormMessage />
        </FormItem>
      )}
    />
    {/* ... */}
  </form>
</Form>
```

## Server-side errors

When the server rejects the submission (e.g., "email already taken"), set the field error manually:

```tsx
async function onSubmit(values: SignupValues) {
  try {
    await api.signup(values);
  } catch (err) {
    if (err instanceof ApiError && err.code === "EMAIL_TAKEN") {
      form.setError("email", { message: "This email is already registered" });
      return;
    }
    form.setError("root", { message: "Something went wrong. Please try again." });
  }
}
```

Display `form.formState.errors.root?.message` near the submit button for the root-level error.

## Field arrays (dynamic lists of fields)

```tsx
const schema = z.object({
  invitees: z.array(z.object({ email: z.string().email() })).min(1),
});

const { control, register, handleSubmit } = useForm({ resolver: zodResolver(schema) });
const { fields, append, remove } = useFieldArray({ control, name: "invitees" });

{fields.map((field, index) => (
  <div key={field.id} className="flex gap-2">
    <Input {...register(`invitees.${index}.email` as const)} />
    <Button type="button" variant="outline" onClick={() => remove(index)}>Remove</Button>
  </div>
))}
<Button type="button" onClick={() => append({ email: "" })}>Add invitee</Button>
```

`field.id` (not `index`) as the key — RHF generates stable ids.

## Async validation (e.g., username availability)

Use `mode: "onBlur"` and an async Zod refinement, or a debounced TanStack Query inside the validator.

```tsx
const schema = z.object({
  username: z.string().min(3).refine(async (value) => {
    const res = await fetch(`/api/username-available?u=${value}`);
    const { available } = await res.json();
    return available;
  }, { message: "Username is taken" }),
});
```

## File uploads

File inputs are tricky with RHF. Register with `register("file")` and validate with Zod:

```tsx
const schema = z.object({
  avatar: z.instanceof(FileList)
    .refine((files) => files.length > 0, "Pick a file")
    .refine((files) => files[0].size < 5_000_000, "Max 5MB")
    .refine((files) => ["image/png", "image/jpeg"].includes(files[0].type), "PNG or JPEG only"),
});
```

## Don't

- Don't use `useState` for every field. RHF is faster (no re-render per keystroke).
- Don't show errors before the user has interacted with a field (RHF's default `mode` handles this — don't override to `onChange` without reason).
- Don't submit via `<button onClick>`. Use `<form onSubmit>` so Enter-to-submit works.
- Don't forget `type="button"` on non-submit buttons inside forms — default is `type="submit"`.
