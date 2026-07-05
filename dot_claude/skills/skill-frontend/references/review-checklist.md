# Review Checklist

Run through this before calling a component or feature done. Stack-agnostic — applies to any Gravity UI app.

## Accessibility

- [ ] Interactive elements are semantic (`<button>`, `<a>`) or rendered through a Gravity UI component — never `<div onClick>`.
- [ ] Every form field has an associated label (Gravity UI `ControlLabel`, `<label htmlFor>`, or the component's `label` prop).
- [ ] Errors are wired with `aria-describedby` and `aria-invalid` (Gravity UI inputs do this when you pass `errorMessage`).
- [ ] Focus ring is visible on all focusable elements (do not override Gravity UI's focus styles).
- [ ] Keyboard-only flow works: Tab, Shift+Tab, Enter, Space, Esc, arrow keys in menus/selects.
- [ ] Dialog/Drawer/Sheet trap focus and return it to the trigger (uikit handles this — do not add your own trap).
- [ ] Icons via `<Icon>` are decorative by default; pass `aria-label` on the parent button when the icon is the only content.
- [ ] Color is never the only signal — pair with icon or text.
- [ ] Heading order is preserved (h1 → h2 → h3; don't skip).
- [ ] Images have `alt` text; decorative images use `alt=""`.
- [ ] App is usable in `light`, `dark`, and (if declared) `*-hc` high-contrast themes.

## Design system fidelity

- [ ] No hand-rolled primitive that Gravity UI already provides. Check `references/gravity-ui-uikit-components.md` before building a new control.
- [ ] No third-party UI library used alongside Gravity UI for the same primitive (no MUI Button next to uikit Button).
- [ ] Colors, spacing, and typography come from Gravity UI tokens (`var(--g-color-*)`, `var(--g-spacing-*)`) — not hard-coded hex / px.
- [ ] No `lab/` or `legacy/` components in production code.
- [ ] Icons come from `@gravity-ui/icons` and render through `<Icon data={...} />`.
- [ ] Toaster is instantiated once at the app root via `ToasterProvider`, not per-component.

## Type safety (if TypeScript)

- [ ] No `any`, no `@ts-ignore`, no non-null assertions (`!`) without an explaining comment.
- [ ] Component props are explicitly typed.
- [ ] Data from external sources (API, URL, storage) is validated at the boundary.
- [ ] No `as` casts except at genuine boundaries.

## Performance

- [ ] Routes / heavy components are code-split (lazy-loaded) where it matters.
- [ ] Long lists (>100 items) use a virtualized component (`@gravity-ui/table`, uikit `List`, or library equivalent).
- [ ] Images have `width`/`height` or `aspect-ratio` to prevent layout shift.
- [ ] Stable keys in lists — no `key={index}` for reorderable data.
- [ ] `useMemo` / `useCallback` only where measured or required for stable deps.
- [ ] No data fetching in raw `useEffect` when the project has a query library — use it.

## UX & visual polish

**States & feedback:**
- [ ] Loading state uses `Skeleton` matching the final layout, not just a spinner.
- [ ] Error state shows a clear message + a retry path. Inline errors live next to the relevant field.
- [ ] Empty state uses `PlaceholderContainer` (or equivalent) with heading, explanation, and a primary action.
- [ ] Submit buttons enter a `loading` state during submission and reflect it in their label.
- [ ] Destructive actions confirm via `Dialog` with a verb-labeled `danger`/`outlined-danger` button.
- [ ] Forms validate on blur where possible; Enter submits; input is not cleared on error.
- [ ] Success toasts auto-dismiss; error toasts persist until dismissed or the issue is resolved.

**Hierarchy & layout:**
- [ ] One primary action per view — all others are secondary / outlined / flat.
- [ ] Text columns have constrained width — no full-viewport line lengths.
- [ ] Group spacing follows Gestalt proximity: internal padding < external margin.
- [ ] Hierarchy is communicated through size, weight, color, and whitespace — in that order.

**Interaction:**
- [ ] Every interactive element has hover, focus-visible, and active states (Gravity UI provides these — do not flatten them).
- [ ] Transitions: snappy for hovers (~150ms), 200–300ms for overlays. Nothing over 500ms.
- [ ] Motion respects `prefers-reduced-motion`.

**Responsive & touch:**
- [ ] Touch targets ≥ 44×44px on mobile. Spacing between targets ≥ 8px.
- [ ] Tested at 375px width — no horizontal scroll, content readable, layout collapses cleanly.
- [ ] `MobileProvider` is configured (or kept default) appropriately for the deployment target.
- [ ] Primary mobile actions are reachable in the thumb zone.

**Color & contrast:**
- [ ] Text contrast ≥ 4.5:1 (AA). Large text ≥ 3:1. UI components ≥ 3:1.
- [ ] Both `light` and `dark` themes verified.
- [ ] Custom theme (if any) generated via Themer, not by overriding individual CSS variables ad hoc.

## Testability

- [ ] Components are mostly driven by props; side effects extracted to hooks.
- [ ] At least one test covers the happy path.
- [ ] Tests query by role/label/text, not by `data-testid` first.
- [ ] Error and empty states are tested.

## Code hygiene

- [ ] File/component naming matches the project's existing convention.
- [ ] No inline `style={{…}}` unless the value is dynamically computed.
- [ ] Refs are passed as a normal prop (uikit forwards refs; do not wrap in `forwardRef` yourself).
- [ ] Server data lives in the project's query layer; URL state (filters, pagination) lives in search params, not local component state.

## Before PR

- [ ] Typecheck passes.
- [ ] Lint passes.
- [ ] Tests pass.
- [ ] Production build succeeds.
- [ ] Manual smoke test in Chrome **and** Safari.
- [ ] Mobile width (375px) verified — no horizontal scroll, tap targets ≥ 44×44.
- [ ] Both themes verified if the app supports theme switching.
