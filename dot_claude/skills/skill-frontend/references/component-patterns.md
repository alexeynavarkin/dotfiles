# Component Patterns

Structure for React components that scales and stays typesafe.

## Basic component template

```tsx
import { cn } from "@/lib/utils";

interface UserCardProps {
  name: string;
  email: string;
  avatarUrl?: string;
  className?: string;
  onSelect?: (email: string) => void;
}

export function UserCard({ name, email, avatarUrl, className, onSelect }: UserCardProps) {
  return (
    <button
      type="button"
      onClick={() => onSelect?.(email)}
      className={cn(
        "flex items-center gap-3 rounded-lg border p-4 text-left transition-colors",
        "hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        className,
      )}
    >
      {avatarUrl ? (
        <img src={avatarUrl} alt="" className="h-10 w-10 rounded-full" />
      ) : (
        <div className="h-10 w-10 rounded-full bg-muted" aria-hidden="true" />
      )}
      <div className="min-w-0">
        <p className="truncate font-medium">{name}</p>
        <p className="truncate text-sm text-muted-foreground">{email}</p>
      </div>
    </button>
  );
}
```

Notes:
- `className` is accepted and merged with `cn()` so parents can tweak layout.
- Decorative avatar fallback uses `aria-hidden`; real avatar has empty `alt=""` because the name next to it carries the meaning.
- Whole card is a `<button>` because it's clickable — no `div onClick`.

## Variant APIs with `cva`

Use `class-variance-authority` for components with style variants. This is how shadcn/ui does it.

```tsx
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground",
        secondary: "bg-secondary text-secondary-foreground",
        destructive: "bg-destructive text-destructive-foreground",
        outline: "border text-foreground",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
```

## Ref forwarding in React 19

No more `forwardRef`. Ref is just another prop.

```tsx
interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  ref?: React.Ref<HTMLInputElement>;
}

export function Input({ ref, className, ...props }: InputProps) {
  return (
    <input
      ref={ref}
      className={cn("h-9 rounded-md border px-3 text-sm", className)}
      {...props}
    />
  );
}
```

## Compound components

For components that have multiple coordinating parts (Tabs, Accordion, Dialog), use the compound pattern. shadcn gives you this out of the box:

```tsx
<Tabs defaultValue="account">
  <TabsList>
    <TabsTrigger value="account">Account</TabsTrigger>
    <TabsTrigger value="password">Password</TabsTrigger>
  </TabsList>
  <TabsContent value="account">…</TabsContent>
  <TabsContent value="password">…</TabsContent>
</Tabs>
```

When building your own, share state via context. Keep the context **internal** to the component folder; don't export it.

## Controlled vs uncontrolled

- **Uncontrolled** (component owns its state): default for inputs that don't need external access.
- **Controlled** (parent owns state): when the value is used elsewhere, submitted as part of a form, or needs to be reset externally.
- **Dual** (either/both): accept optional `value`/`onChange`, fall back to internal state. Use when you're building a reusable primitive. Look at how Radix does it.

```tsx
function useControllableState<T>(
  controlled: T | undefined,
  defaultValue: T,
  onChange?: (value: T) => void,
) {
  const [internal, setInternal] = useState(defaultValue);
  const value = controlled ?? internal;
  const setValue = (next: T) => {
    if (controlled === undefined) setInternal(next);
    onChange?.(next);
  };
  return [value, setValue] as const;
}
```

## Polymorphic `as` prop (use sparingly)

When you genuinely need the same component to render as different elements. Often a sign you should just make two components. If you must:

```tsx
import { Slot } from "@radix-ui/react-slot";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  asChild?: boolean;
}

export function Button({ asChild, ...props }: ButtonProps) {
  const Comp = asChild ? Slot : "button";
  return <Comp {...props} />;
}
```

This is the shadcn pattern — simpler than full polymorphic typing and handles 95% of cases.

## Error boundaries

Every route-level component should be wrapped in an error boundary. Use `react-error-boundary`:

```tsx
import { ErrorBoundary } from "react-error-boundary";

<ErrorBoundary FallbackComponent={ErrorFallback} onReset={() => queryClient.resetQueries()}>
  <RouteContent />
</ErrorBoundary>
```

## Suspense boundaries

Wrap async UI in `<Suspense>` with a skeleton fallback that matches the final layout.

```tsx
<Suspense fallback={<UserListSkeleton />}>
  <UserList />
</Suspense>
```
