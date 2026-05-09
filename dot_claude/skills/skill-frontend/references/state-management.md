# State Management

Pick the simplest thing that works. Escalate only when you hit the ceiling.

## The ladder

1. **`useState`** — component-local state. Default choice. Start here.
2. **Lifting state up** — two or three siblings need the same state. Move it to the nearest common parent.
3. **`useReducer`** — state transitions are complex (multiple related fields that change together).
4. **Context** — state that many deeply-nested components need, that changes rarely (theme, current user). Beware: every context consumer re-renders when the value changes.
5. **Zustand** — shared client state that changes frequently, is accessed by distant components, or needs to survive route changes without prop drilling.
6. **TanStack Query** — this is a **different axis**. Any state that comes from the server belongs here, not in Zustand or context. Don't duplicate.

## When NOT to reach for Zustand

- **Server data** → TanStack Query. Never mirror a server response into Zustand.
- **Form state** → React Hook Form.
- **URL state** (filters, pagination, selected tab) → URL search params via `useSearchParams`. Bookmarkable, shareable, back-button friendly.
- **State used by two siblings** → lift it up.

## Zustand basics

```ts
// features/cart/store.ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

interface CartItem {
  id: string;
  name: string;
  priceCents: number;
  quantity: number;
}

interface CartState {
  items: CartItem[];
  addItem: (item: Omit<CartItem, "quantity">) => void;
  removeItem: (id: string) => void;
  setQuantity: (id: string, quantity: number) => void;
  clear: () => void;
}

export const useCartStore = create<CartState>()(
  persist(
    (set) => ({
      items: [],
      addItem: (item) =>
        set((state) => {
          const existing = state.items.find((i) => i.id === item.id);
          if (existing) {
            return {
              items: state.items.map((i) =>
                i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i,
              ),
            };
          }
          return { items: [...state.items, { ...item, quantity: 1 }] };
        }),
      removeItem: (id) =>
        set((state) => ({ items: state.items.filter((i) => i.id !== id) })),
      setQuantity: (id, quantity) =>
        set((state) => ({
          items: state.items.map((i) => (i.id === id ? { ...i, quantity } : i)),
        })),
      clear: () => set({ items: [] }),
    }),
    { name: "cart-storage" },
  ),
);
```

## Using the store — select narrowly

```tsx
// Good — re-renders only when items change
const items = useCartStore((state) => state.items);

// Good — actions are stable, no re-render triggered
const addItem = useCartStore((state) => state.addItem);

// Bad — re-renders on ANY store change
const store = useCartStore();

// Bad — returns a new object every render, causing infinite loops
const { items, addItem } = useCartStore((state) => ({ items: state.items, addItem: state.addItem }));
```

For multiple slices, use `useShallow`:

```tsx
import { useShallow } from "zustand/react/shallow";

const { items, addItem } = useCartStore(
  useShallow((state) => ({ items: state.items, addItem: state.addItem })),
);
```

## Computed values

Derive, don't store:

```tsx
// In the component:
const items = useCartStore((state) => state.items);
const total = items.reduce((sum, i) => sum + i.priceCents * i.quantity, 0);
```

For expensive computations, use `useMemo`. Don't put `total` in the store — it's derivable.

## Slicing large stores

When a store gets big, split into slices:

```ts
import { type StateCreator, create } from "zustand";

interface AuthSlice { user: User | null; signIn: (u: User) => void; }
interface UiSlice { sidebarOpen: boolean; toggleSidebar: () => void; }

const createAuthSlice: StateCreator<AuthSlice & UiSlice, [], [], AuthSlice> = (set) => ({
  user: null,
  signIn: (user) => set({ user }),
});

const createUiSlice: StateCreator<AuthSlice & UiSlice, [], [], UiSlice> = (set) => ({
  sidebarOpen: true,
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
});

export const useAppStore = create<AuthSlice & UiSlice>()((...a) => ({
  ...createAuthSlice(...a),
  ...createUiSlice(...a),
}));
```

## URL state

For anything a user might want to bookmark, share, or navigate back to:

```tsx
import { useSearchParams } from "react-router";

function ProductList() {
  const [params, setParams] = useSearchParams();
  const category = params.get("category") ?? "all";
  const sort = params.get("sort") ?? "name";

  return (
    <Select
      value={category}
      onValueChange={(v) => setParams((prev) => {
        prev.set("category", v);
        return prev;
      })}
    >
      {/* ... */}
    </Select>
  );
}
```

For complex URL state with validation, look at `nuqs`.

## Context — when to actually use it

Good fits:
- Current authenticated user (read everywhere, changes rarely).
- Theme (`light` / `dark` / `system`).
- i18n translations.

Bad fits:
- Anything that changes often — triggers re-render of every consumer.
- Global form state — use RHF's `FormProvider`.
- Anything shared across sibling components — lift state up instead.
