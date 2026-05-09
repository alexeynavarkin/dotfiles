# Review Checklist

Run through this before calling a component or feature done.

## Accessibility

- [ ] Interactive elements are `<button>`, `<a>`, or have proper ARIA roles — never `<div onClick>`.
- [ ] Every form field has an associated `<label>`.
- [ ] Errors are connected via `aria-describedby` and `aria-invalid`.
- [ ] Focus ring is visible on all focusable elements.
- [ ] Keyboard-only user can complete every flow (Tab, Shift+Tab, Enter, Space, Esc).
- [ ] Dialog/modal traps focus and returns focus to trigger on close (shadcn handles this).
- [ ] Icons have `aria-label` if meaningful, `aria-hidden` if decorative.
- [ ] Color is not the only signal for errors/success/warnings.
- [ ] Headings are in order (h1 → h2 → h3; don't skip levels).
- [ ] Images have `alt` text — empty `alt=""` if purely decorative.

## Type safety

- [ ] No `any`, no `@ts-ignore`, no non-null assertions (`!`) without explaining comments.
- [ ] Props are explicitly typed with `interface` or `type`.
- [ ] API responses are validated with Zod at the boundary.
- [ ] No `as` casts except at genuine boundaries (e.g., `JSON.parse` result).
- [ ] `noUncheckedIndexedAccess` passes — array and object index access is narrowed where needed.

## Performance

- [ ] Route is code-split with `React.lazy` + `<Suspense>` (unless it's the landing page).
- [ ] No data fetching in `useEffect` — TanStack Query instead.
- [ ] Long lists (>100 items) are virtualized.
- [ ] Images have `width`/`height` or `aspect-ratio` to prevent CLS.
- [ ] Stable keys in lists — no `key={index}` for reorderable data.
- [ ] No `useMemo`/`useCallback` added speculatively — only where measured or needed for stable deps.

## UX & Visual Design

**States & feedback:**
- [ ] Loading state uses skeletons matching the final layout (not just a spinner).
- [ ] Error state shows a clear message + a way to retry. Inline errors below relevant fields.
- [ ] Empty state has a heading, explanation, and a primary action (CTA button).
- [ ] Submit buttons disable during submission and change label ("Saving…").
- [ ] Destructive actions confirm via AlertDialog with a verb-labeled button (destructive = secondary style).
- [ ] Forms validate on blur, support keyboard submission (Enter), never clear input on error.
- [ ] Toasts are for success confirmations only (auto-dismiss 5-8s); error toasts are persistent.

**Visual hierarchy & layout:**
- [ ] One primary action per view — all others are secondary/ghost/outline (Von Restorff).
- [ ] Text containers have constrained width (`max-w-prose` or similar) — no full-viewport text.
- [ ] Spacing follows Gestalt proximity: internal padding < external margin for groups.
- [ ] Visual hierarchy is clear: size > weight > color > whitespace guides the eye.

**Transitions & interaction:**
- [ ] Every interactive element has hover, focus-visible, and active states.
- [ ] Transitions: 150ms hovers, 200-300ms modals/dropdowns. Nothing > 500ms.
- [ ] Animations respect `prefers-reduced-motion` (opt-in via media query).

**Responsive & touch:**
- [ ] Touch targets ≥ 44×44px. Spacing between targets ≥ 8px.
- [ ] Tested at 375px width — no horizontal scroll, content readable, layout single-column.
- [ ] Primary mobile actions in bottom-center (thumb zone).

**Color & contrast:**
- [ ] Text contrast ≥ 4.5:1 (AA). Large text ≥ 3:1. UI components ≥ 3:1.
- [ ] Tested in both light and dark mode (if applicable).
- [ ] Dark mode uses near-black (not #000), lighter surfaces for elevation, desaturated colors.

## Testability

- [ ] Component's behavior is driven by props — side effects pushed to hooks.
- [ ] At least one test for the happy path.
- [ ] Tests query by role/label, not testId.
- [ ] Error states are tested (invalid form, failed fetch).

## Visual style (sharp minimal)

- [ ] Border radius: `rounded-md` (6px) buttons/inputs, `rounded-lg` (8px) cards/dialogs. No `rounded-xl`+, no `rounded-full` (except toggles).
- [ ] No box-shadows in dark mode. Light mode: `shadow-sm` max for dropdowns.
- [ ] Surfaces: near-black backgrounds, not `#000`. Elevation via lighter bg, not shadow.
- [ ] Borders: 1px `border-border`, no thick/double borders.
- [ ] Typography: `text-sm` body, `font-semibold` max (no `font-bold` in UI), no italic, no decorative fonts.
- [ ] Heights: `h-9` default for buttons/inputs. Compact density.
- [ ] One primary button per view. Others: secondary/ghost/outline.
- [ ] No gradients on surfaces. No colored card backgrounds. No zebra-striped tables.
- [ ] Icons: Lucide, `size-4` inline, `text-muted-foreground` default.
- [ ] Avatars: `rounded-md` (not circular).

## Code hygiene

- [ ] File name is kebab-case, export is PascalCase.
- [ ] `cn()` used for conditional classes, not string concatenation.
- [ ] No inline styles (`style={{…}}`) unless the value is dynamic (e.g., a computed color).
- [ ] Tailwind uses design tokens (`bg-background`, `gap-4`), not arbitrary values like `h-[47px]`.
- [ ] `forwardRef` not used — React 19 accepts `ref` as a prop.
- [ ] Server data lives in TanStack Query, not Zustand.
- [ ] URL state (filters, pagination) is in search params, not local state.

## Before PR

- [ ] `npm run typecheck` passes.
- [ ] `npm run lint` passes.
- [ ] `npm test` passes.
- [ ] `npm run build` succeeds.
- [ ] Manual test in Chrome **and** Safari (Safari catches Flexbox/Tailwind quirks).
- [ ] Test at mobile width (375px) — no horizontal scroll, tap targets ≥ 44×44.
- [ ] Test in dark mode if the app has a theme.
