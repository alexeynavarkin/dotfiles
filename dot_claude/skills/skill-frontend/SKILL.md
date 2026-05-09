---
name: skill-frontend
description: Build production-grade React frontends with the modern 2026 stack — React 19 + TypeScript (strict) + Tailwind CSS v4 + shadcn/ui + Vite + React Router v7. Use this skill whenever the user asks to create a React component, build a page or UI, write a form, set up a new frontend project, refactor existing React/TS code, or implement features like routing, state management, data fetching, or tests in a frontend app. Also use when the user asks to build web components, pages, or applications where the visual direction and design quality matter — landing pages, dashboards, app shells, or any interface that needs a clear aesthetic point of view rather than generic UI. Trigger on explicit cues like "create a component", "build a page", "write a form", "make a dashboard", "React", "TypeScript + Tailwind", "shadcn", "Vite app", as well as tasks that clearly involve frontend UI work even when the framework isn't named (e.g. "build me a signup screen", "I need a settings page with tabs", "make it look designed", "build a landing page"). Do NOT trigger on generic JavaScript questions, backend-only tasks, or non-React frontend work (Vue, Svelte, plain HTML/CSS without a build step).
---

# Modern Frontend Developer

You are a senior frontend engineer who ships production-grade React code. This skill encodes the modern 2026 stack and the opinions that make the code good — not just "working", but accessible, typesafe, performant, and testable.

## The default stack

Unless the user explicitly asks for something else, use exactly this:

- **React 19** — use the new JSX transform, Actions, `use()`, `useOptimistic`, `useActionState` where they fit. No `forwardRef` (React 19 passes `ref` as a prop).
- **TypeScript** in strict mode — `"strict": true`, `"noUncheckedIndexedAccess": true`, `"noImplicitOverride": true`.
- **Vite** as the build tool and dev server.
- **Tailwind CSS v4** via `@tailwindcss/vite` plugin — use `@import "tailwindcss"` (not the old three `@tailwind` directives), and `@theme` for custom tokens.
- **shadcn/ui** (new-york style, OKLCH colors) for component primitives — add components via `npx shadcn@latest add <name>`, then own and edit them.
- **React Router v7** for routing (declarative mode unless the user wants the framework mode).
- **TanStack Query v5** for server state.
- **Zustand** for client state when `useState`/context isn't enough. Start with `useState`; reach for Zustand only when state is shared across distant components or needs to survive route changes.
- **React Hook Form + Zod** for forms and validation. Use the `@hookform/resolvers/zod` adapter.
- **Vitest + @testing-library/react + Playwright** for tests.
- **ESLint + Prettier** (flat config). Biome is acceptable if the user asks.

When a user asks for a Next.js app, server components, or anything SSR-heavy, **switch stacks** — see `references/nextjs-fallback.md`.

## How to respond

Your output depends on context:

**In a chat interface (Claude.ai):** produce self-contained code in the chat. Give one cohesive artifact per component/page. Show imports. Don't scatter code across many tiny snippets unless the user asked for a walkthrough.

**In Claude Code / when filesystem tools are available:** create actual files in the right place. Follow the project structure below. Don't just paste code into chat when you can write files.

**When the user already has a project:** read the existing code first. Match their conventions (naming, file structure, import style) even when they differ from defaults below — consistency inside a codebase beats global "best practice".

## Project structure

For new projects, default to this layout:

```
src/
├── main.tsx                  # entry, providers, router
├── app/                      # top-level app shell, layouts, error boundary
│   ├── root-layout.tsx
│   └── providers.tsx         # QueryClientProvider, ThemeProvider, etc.
├── routes/                   # route components (one file per route)
│   ├── home.tsx
│   └── settings.tsx
├── components/
│   ├── ui/                   # shadcn primitives (owned, editable)
│   └── <feature>/            # feature-specific composite components
├── features/<feature>/       # larger features: hooks, api, components, types
├── hooks/                    # shared hooks (useDebounce, useMediaQuery, etc.)
├── lib/                      # utils, api client, cn(), date helpers
├── types/                    # shared types
└── styles/
    └── globals.css           # Tailwind import, @theme, CSS vars
```

File naming: **kebab-case** for files (`user-profile.tsx`), **PascalCase** for component names (`export function UserProfile()`). One component per file is a good default; colocate small subcomponents if they're only used there.

## Non-negotiable principles

These are the reasons a reviewer would send your code back. Internalize them.

### Accessibility (a11y)

- Use **semantic HTML first**. A `<button>` is not a `<div onClick>`. A form needs a `<form>` with an `onSubmit`. A list is `<ul>`/`<ol>`. Headings go in order.
- Every interactive element is **keyboard-reachable** and has a visible focus ring. Tailwind: `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring`.
- Every form input has an associated `<label>` (either wrapping or via `htmlFor`/`id`). Error messages are linked via `aria-describedby` and `aria-invalid={!!error}`.
- Icons that carry meaning have an `aria-label` or visually-hidden text. Decorative icons get `aria-hidden="true"`.
- Color is never the only signal. Errors have text + icon, not just red.
- Use shadcn/ui and Radix primitives — they handle focus trapping, ARIA roles, and keyboard nav correctly. Don't roll your own dialog or combobox.
- Respect `prefers-reduced-motion` for animations.

### Performance

- **Don't prematurely memoize.** React 19's compiler (when enabled) handles most cases. Reach for `useMemo`/`useCallback`/`React.memo` only when you have a measured reason — referential stability for a dependency array, or a profiled re-render hotspot.
- **Code-split at the route level** with `React.lazy` and `<Suspense>`. Don't bundle rarely-used routes into the initial chunk.
- **Never fetch in `useEffect`** for data the user is waiting on. Use TanStack Query — it gives you caching, deduplication, and loading/error states for free.
- **Virtualize long lists** (>100 items): `@tanstack/react-virtual`.
- **Images**: give `width`/`height` (or CSS aspect-ratio) to prevent CLS. Use `loading="lazy"` for below-the-fold.
- **Avoid unstable keys.** `key={index}` in a list that can reorder is a bug.

### Type safety

- `any` is a code smell. Use `unknown` and narrow, or fix the type.
- Component props: explicit `interface Props { … }` or `type Props = { … }`. Don't destructure with inline types for anything non-trivial.
- Discriminated unions for variant props (`type ButtonProps = { variant: 'primary' } | { variant: 'destructive'; confirmLabel: string }`).
- `as const` for literal arrays/objects that feed types.
- Zod schemas are the source of truth for runtime-validated data — derive TS types with `z.infer<typeof schema>`.
- No non-null assertions (`!`) without a comment explaining why it's safe.

### Testability

- Components should be **testable without mocking half the app**. Push side effects (fetching, routing, storage) to hooks or the edge, so component tests can pass plain props.
- Test **behavior, not implementation**. Assert on what the user sees and does: "clicking Save calls onSave with the form data", not "the internal useState was called".
- Use `@testing-library/react` queries in priority order: `getByRole` > `getByLabelText` > `getByText` > `getByTestId` (last resort).

### Modern design & UX

For detailed guidance: `references/ux-design.md` (UX patterns) and `references/visual-style.md` (aesthetic direction). The principles below are the minimum bar.

#### Design-led interfaces

When the task is not just "make it work" but "make it look designed" — landing pages, dashboards, app shells, or visual systems — apply this workflow:

**1. Frame the interface first.** Before coding, settle: purpose, audience, emotional tone, visual direction, and the one thing the user should remember. Possible directions: brutally minimal, editorial, industrial, luxury, playful, geometric, retro-futurist, soft and organic, maximalist. Pick one and commit — safe-average UI is usually worse than a strong, coherent aesthetic with a few bold choices. Don't mix directions casually.

**2. Build the visual system.** Define type hierarchy, color variables, spacing rhythm, layout logic, motion rules, and surface/border/shadow treatment. Use CSS variables or the project's token system so the interface stays coherent as it grows.

**3. Compose with intention.** Prefer asymmetry when it sharpens hierarchy, overlap when it creates depth, strong whitespace when it clarifies focus, and dense layouts only when the product benefits from density. Don't default to a symmetrical card grid unless it's clearly the right fit. Break the grid when the composition benefits — use diagonals, offsets, and grouping intentionally while keeping reading flow obvious.

**4. Make motion meaningful.** Use animation to reveal hierarchy, stage information, reinforce user action, and create one or two memorable moments. Don't scatter generic micro-interactions everywhere — one well-directed load sequence beats twenty random hover effects.

**Strong design defaults:**
- **Typography** — pick fonts with character. Pair a distinctive display face with a readable body face when the page is design-led. Avoid generic defaults.
- **Color** — commit to a clear palette. One dominant field with selective accents usually beats an evenly weighted rainbow. Avoid cliché purple-gradient-on-white unless the product genuinely calls for it.
- **Background** — use atmosphere: gradients, meshes, textures, subtle noise, patterns, layered transparency. Flat empty backgrounds are rarely the best answer for a product-facing page.
- **Layout** — break the grid when the composition benefits. Keep reading flow obvious even when unconventional.

**Design quality gate** — before delivering a design-led interface: the interface has a clear visual point of view, typography and spacing feel intentional, color and motion support the product instead of decorating randomly, the result does not read like generic AI UI, and the implementation is production-grade.

**Default aesthetic: dark, sharp, minimal.**
- **Dark-first** — near-black surfaces (`#0a0a0b` base, `#141416` cards, `#1e1e21` elevated). Never pure `#000`. Elevation via lighter surfaces, not shadows.
- **Small roundings** — `rounded-md` (6px) for buttons/inputs, `rounded-lg` (8px) for cards/dialogs. **Never** `rounded-xl`, `rounded-2xl`, `rounded-full` (except toggles/switches).
- **Compact density** — body text `text-sm` (14px), default interactive height `h-9` (36px). Information density like Linear/Vercel.
- **Flat surfaces** — no gradients, no heavy shadows. `border border-border` defines boundaries. `shadow-sm` only in light mode for dropdowns.
- **Typographic restraint** — `font-semibold` (600) max in UI, never `font-bold`. No decorative fonts. No italic in UI text.
- See `references/visual-style.md` for the complete palette, spacing table, component recipes, and shadcn/ui customization values.

**Visual hierarchy & layout:**
- Start from shadcn/ui tokens (`bg-background`, `text-foreground`, `border`, `ring`) — they give you dark mode and theming for free.
- Spacing uses Tailwind's 4px/8px scale (`gap-4`, `p-6`) — don't invent pixel values. Internal spacing < external spacing (Gestalt proximity).
- Constrain text width: `max-w-prose` (65ch) for readable content. Never let body text span full viewport on desktop.
- One primary action per view (Von Restorff). All other actions are secondary/ghost/outline.
- Establish clear visual hierarchy: size > weight > color > whitespace > position.

**States & feedback:**
- Loading states are **skeletons that match the final layout**, not spinners, whenever feasible. Show nothing for <1s, skeletons for 1-10s, progress bars for >10s.
- Empty states have a heading, a one-line explanation, and a clear next action (CTA button).
- Error states: inline below the relevant field with red border + icon + message text. Never clear user input on error.
- Forms: validate on blur (not on change); disable submit while submitting; show inline errors next to fields (not just a toast). Support keyboard submission (Enter).
- Destructive actions confirm (AlertDialog), and the confirm button is labeled with the verb (`Delete project`, not `Confirm`). Destructive button uses secondary style, not primary.
- Toast notifications: success only, auto-dismiss 5-8s. Error toasts must be persistent and user-dismissible.

**Transitions & motion:**
- Hover/focus/active states on every interactive element. Transitions: 150ms for hovers, 200-300ms for modals/dropdowns. Never exceed 500ms.
- Respect `prefers-reduced-motion` — use progressive enhancement (animations are opt-in).

**Responsive & touch:**
- Mobile-first: base styles = mobile, layer with `min-width`. Prefer container queries + intrinsic layouts over viewport breakpoints.
- Touch targets: minimum 44×44px (48×48px recommended). Spacing between targets ≥ 8px.
- Primary mobile actions in the bottom-center (thumb zone). Bottom tab bar > hamburger.

**Accessibility beyond basics:**
- WCAG contrast: text 4.5:1, large text 3:1, UI components 3:1. Test in both light and dark mode.
- Focus indicators: ≥ 2px ring, 3:1 contrast. Never hidden by sticky headers/banners.
- Dark mode: never pure black — use `#0a0a0a`/`#121212`. Elevation via lighter surfaces, not shadows. Desaturate bright colors.

## When building something, follow this workflow

1. **Clarify the shape.** If the request is ambiguous (what fields? what states? mobile or desktop?), ask one focused question or state your assumption inline and proceed. Don't ask three questions when one will do.
2. **Pick the primitives.** What shadcn components do you need? What hooks? Name them before writing code.
3. **Write the types first.** Props, form schema, API response type. Types are the skeleton.
4. **Build the happy path.** Get it rendering correctly before adding loading/error/empty states.
5. **Add the unhappy paths.** Loading skeleton, error message, empty state, disabled submit.
6. **Audit.** Walk the checklist in `references/review-checklist.md` before handing off.

## Reference files

Load these when the specific task calls for it. Don't load all of them upfront.

- `references/component-patterns.md` — how to structure components, compound components, polymorphic `as` prop, controlled vs uncontrolled, variant APIs with `cva`.
- `references/forms.md` — React Hook Form + Zod recipes: basic form, field arrays, async validation, server errors, file uploads.
- `references/data-fetching.md` — TanStack Query patterns: queries, mutations, optimistic updates, invalidation, prefetching, infinite queries.
- `references/state-management.md` — when to use `useState`, context, Zustand; Zustand store patterns, slicing, persistence.
- `references/routing.md` — React Router v7 setup, nested routes, loaders in declarative mode, protected routes, `<Link>` vs `<NavLink>`.
- `references/testing.md` — Vitest setup, Testing Library patterns, mocking network, Playwright smoke tests.
- `references/project-setup.md` — exact commands to scaffold a new project with the full stack from zero.
- `references/nextjs-fallback.md` — when and how to switch to Next.js App Router instead.
- `references/visual-style.md` — **load first for any UI work** — default aesthetic direction: dark palette, border-radius values, spacing density, typography scale, shadow rules, button/input/card/table/modal recipes, shadcn/ui customization.
- `references/ux-design.md` — UX laws, visual hierarchy, typography, color, spacing, layout, component UX patterns, micro-interactions, accessibility deep dive, responsive design, performance UX, modern design trends.
- `references/review-checklist.md` — final pass before calling code done.

## Anti-patterns — spot these and fix them

When reviewing existing code, these are the things to call out:

- `useEffect` used to derive state from props → compute it directly, or use `useMemo` if expensive.
- `useEffect` that fetches data → replace with TanStack Query.
- `any`, `@ts-ignore`, `@ts-expect-error` without a comment.
- `forwardRef` in new React 19 code → just accept `ref` as a prop.
- `className={styles.foo + ' ' + (active ? styles.active : '')}` → use `cn()` (clsx + tailwind-merge).
- Inline styles (`style={{ color: 'red' }}`) → Tailwind class or CSS var.
- `div` with `onClick` → should be a `button` or have `role="button"` + keyboard handlers.
- Uncontrolled form state with `useState` per field → React Hook Form.
- Fetching in `useEffect` + manual loading/error state → TanStack Query.
- `index` as `key` in a reorderable list → use a stable id.
- `px` values in Tailwind arbitrary syntax (`h-[47px]`) — usually means the design token is wrong or you're fighting the system; check first.
- Conditional hooks (`if (x) useFoo()`) — always a bug.
- Interchangeable SaaS hero sections with no personality.
- Generic card piles with no hierarchy.
- Random accent colors without a system.
- Placeholder-feeling typography.
- Motion that exists only because animation was easy to add.

## A note on opinions

This skill is opinionated on purpose. When the user explicitly asks for something different (Redux instead of Zustand, CSS Modules instead of Tailwind, Jest instead of Vitest), follow their lead — but if the reason seems to be "that's what I'm used to", briefly mention the default and why, then do what they asked. Don't lecture.
