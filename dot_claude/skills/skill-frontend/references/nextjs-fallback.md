# Next.js — When to Switch

The default stack (Vite + React Router) is right for most SPAs. Reach for Next.js App Router when:

- **SEO matters** — content needs to render server-side for crawlers and social previews (marketing site, blog, e-commerce).
- **You want server components** — data fetching co-located with UI, zero client JS for pure-render pieces.
- **You need server actions** — mutations without hand-rolling an API route.
- **You're building a content site** with MDX, static generation, or incremental static regeneration.
- **The user explicitly asks for Next.js.**

Stay with Vite + React Router when:

- It's an authenticated app (dashboard, admin, SaaS internals). SEO doesn't apply.
- You want the simplest possible deploy (static site to any CDN).
- The team is small and doesn't need two runtimes (Node server + browser) to worry about.

## Next.js setup (App Router)

```bash
npx create-next-app@latest my-app --typescript --tailwind --app --src-dir --use-npm
cd my-app
```

Pick: **App Router yes**, **Tailwind yes**, **src/ directory yes**, **import alias `@/*`**.

Then add shadcn:

```bash
npx shadcn@latest init
npx shadcn@latest add button input label form
```

## Key differences from the Vite stack

### Client vs server components

Every component is a server component by default. Add `"use client"` at the top only when you need:
- `useState`, `useEffect`, `useRef` (any hook)
- Event handlers (`onClick`, `onChange`)
- Browser APIs (`window`, `localStorage`)
- Context consumers (most contexts)

Keep as much as possible on the server. Pass serializable data from server → client components.

### Routing

File-based, in `src/app/`:
- `app/page.tsx` → `/`
- `app/settings/page.tsx` → `/settings`
- `app/users/[id]/page.tsx` → `/users/:id`
- `app/layout.tsx` → wraps all routes
- `app/(marketing)/pricing/page.tsx` → route group, URL is `/pricing`

No `<BrowserRouter>`, no `<Routes>`. Links:

```tsx
import Link from "next/link";
<Link href="/settings">Settings</Link>
```

Navigation:

```tsx
"use client";
import { useRouter } from "next/navigation";
const router = useRouter();
router.push("/dashboard");
```

### Data fetching

In server components, just `await`:

```tsx
// app/users/[id]/page.tsx
export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const user = await getUser(id); // runs on the server
  return <UserDetails user={user} />;
}
```

In client components, use TanStack Query as before.

### Mutations — server actions

```tsx
// app/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

const schema = z.object({ name: z.string().min(1), email: z.string().email() });

export async function updateUser(formData: FormData) {
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { error: parsed.error.flatten() };

  await db.user.update({ where: { id: userId }, data: parsed.data });
  revalidatePath("/users");
  return { success: true };
}
```

Use with `useActionState` (React 19):

```tsx
"use client";
import { useActionState } from "react";
import { updateUser } from "./actions";

const [state, formAction, isPending] = useActionState(updateUser, null);

<form action={formAction}>
  <input name="name" />
  <button disabled={isPending}>Save</button>
</form>
```

### Caching

Next.js caches aggressively. Be explicit:
- `fetch(url, { cache: "no-store" })` — never cache.
- `fetch(url, { next: { revalidate: 60 } })` — ISR, refresh every 60s.
- `fetch(url, { next: { tags: ["users"] } })` — tag-based revalidation via `revalidateTag("users")`.

### Metadata

```tsx
// app/users/[id]/page.tsx
export async function generateMetadata({ params }): Promise<Metadata> {
  const { id } = await params;
  const user = await getUser(id);
  return {
    title: `${user.name} · Users`,
    description: user.bio,
  };
}
```

No `react-helmet` needed.

## What carries over from the Vite stack

Everything **inside** client components is the same:
- React 19 patterns, TypeScript strict mode.
- Tailwind v4, shadcn/ui components.
- React Hook Form + Zod for complex forms (server actions handle simple ones).
- TanStack Query for client-side data (lists that paginate, infinite scroll, etc.).
- Zustand for client state.
- Vitest for component tests, Playwright for E2E.

## Don't

- Don't `"use client"` on everything. Defeats the purpose. Push the boundary down the tree — make client "leaves", not client "roots".
- Don't fetch in a `useEffect` inside a server-component page. Fetch at the top of the async server component.
- Don't import server-only code into client components. Split into separate files.
- Don't use React Router inside Next.js. Use Next's router.
