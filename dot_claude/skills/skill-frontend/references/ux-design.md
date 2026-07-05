# UX Design Reference

Comprehensive guide for designing beautiful, usable interfaces. Stack-agnostic UX principles. Load this when building UI from scratch, designing layouts, choosing component patterns, or reviewing UX quality.

> **Note on examples.** Some code snippets below use Tailwind class names as shorthand for sizes/spacing (e.g. `text-sm` ≈ 14px, `gap-4` ≈ 16px, `max-w-prose` ≈ 65ch). When working in a Gravity UI project, translate these to **Gravity UI tokens** (`var(--g-spacing-*)`, `var(--g-text-body-*-font-size)`, the `Text` component's `variant` prop) and uikit primitives (`Flex`, `Box`, `Card`, `Text`). The **pixel values and UX principles are what matter** — the Tailwind syntax is incidental.

---

## 1. Core UX Laws

Apply these principles when making layout and interaction decisions.

### Fitts's Law
The time to reach a target is a function of distance to it and its size. **Make primary actions large and close to the user's likely cursor/thumb position.**
- Primary CTAs: minimum `h-10 px-6` (40px height). Hero CTAs: `h-12 px-8` (48px).
- Place primary actions near content they relate to, not at the opposite end of the screen.
- On mobile, place key actions in the **bottom third** (thumb zone).

### Hick's Law
Decision time increases with the number and complexity of choices. **Reduce options at each decision point.**
- Navigation: **5-7 top-level items** max. Use grouping/submenus beyond that.
- Forms: show only required fields initially; reveal optional fields via progressive disclosure.
- Action menus: group related actions, separate destructive actions visually.

### Jakob's Law
Users spend most of their time on *other* sites and expect yours to work the same way. **Follow established conventions.**
- Logo top-left links to home. Search top-right or top-center. Navigation left sidebar or top bar.
- Underlined blue text = link. Shopping cart icon top-right. Settings = gear icon.
- Don't innovate on navigation patterns unless you have a strong UX reason and test it.

### Miller's Law
People can hold ~4-5 items in working memory (updated from the classic 7±2). **Chunk and group information.**
- Break long forms into logical sections with headings.
- Group related navigation items under clear categories.
- Dashboard cards: 4-6 key metrics, not 15.

### Doherty Threshold
Productivity soars when system response is **< 400ms**. Keep interactions feeling instant.
- Use optimistic UI for actions with >97% success rate (likes, toggles, saves).
- Show skeleton screens immediately; never let the user stare at a blank page.
- Transitions: 150-300ms for UI feedback. Anything > 500ms feels sluggish.

### Aesthetic-Usability Effect
Users perceive beautiful interfaces as more usable. **Invest in visual polish.**
- Consistent spacing, aligned elements, and clean typography create trust.
- Use Gravity UI tokens (`var(--g-color-*)`, `var(--g-spacing-*)`) to ensure visual consistency.
- Small details matter: consistent border-radius, aligned padding, subtle shadows for depth.

### Von Restorff Effect (Isolation Effect)
A distinctive item among similar items is most likely to be remembered. **Make the primary action visually unique.**
- One primary button per view. All others are secondary/ghost/outline.
- Use color, size, or weight to differentiate the key action.
- Highlight the recommended pricing plan, the active nav item, the new feature.

### Peak-End Rule
Users judge an experience by its peak moment and end moment. **Nail the first impression and the completion state.**
- Onboarding: make the first interaction delightful and successful.
- Success states: celebrate meaningful completions (subtle animation, clear confirmation).
- Error recovery: a smooth recovery from an error can be a positive peak.

### Serial Position Effect
Users remember the first and last items in a list best. **Put the most important items first and last.**
- Navigation: most-used items first, account/settings last.
- Feature lists: lead with the strongest benefit, end with the CTA.

### Tesler's Law (Law of Conservation of Complexity)
Every system has inherent complexity that cannot be removed — only moved. **Absorb complexity so users don't have to.**
- Smart defaults: pre-fill country from locale, pre-select common options.
- Auto-formatting: mask phone numbers, credit cards, dates.
- Compute derived values instead of asking the user to enter them.

### Postel's Law (Robustness Principle)
Be liberal in what you accept, conservative in what you produce. **Accept flexible input, output clean results.**
- Accept phone numbers in any format (spaces, dashes, parens), store/display consistently.
- Search: handle typos, synonyms, partial matches.
- Dates: accept "tomorrow", "next Monday", ISO, locale format.

---

## 2. Gestalt Principles for Layout

These govern how users perceive visual grouping. Apply them to every layout decision.

### Proximity
Elements close together are perceived as related. **Use spacing to create logical groups.**
- Related form fields: `gap-3` (12px) between fields within a section.
- Section separation: `gap-8` to `gap-12` (32-48px) between sections.
- Card internal padding: `p-4` to `p-6` (16-24px). Grid gap between cards: `gap-4` to `gap-6`.
- **Rule: internal spacing < external spacing.** Padding inside a group must be less than the margin separating groups.

### Similarity
Elements that look similar are perceived as related. **Make same-function elements look the same.**
- All navigation links share the same style. All action buttons share the same height.
- Use consistent icon style (outline OR filled, not mixed).
- Status badges: same shape, different colors.

### Continuity
The eye follows lines and curves. **Align elements along clear axes.**
- Left-align form labels and inputs on the same vertical axis.
- Use CSS Grid for strict alignment. Avoid mixing centered and left-aligned content in the same section.
- Cards in a grid should have consistent heights (use `line-clamp` on descriptions).

### Common Region
Elements within a shared boundary are perceived as a group. **Use cards, borders, and backgrounds to group.**
- Card component: `rounded-lg border bg-card p-4` groups related content.
- Sidebar navigation: distinct background from main content.
- Form sections: either a border/card or a clear heading + spacing.

### Figure-Ground
Users distinguish foreground content from background. **Create clear depth layers.**
- Modals: dim backdrop (`bg-black/50`) separates dialog from page.
- Dropdown menus: shadow (`shadow-md`) lifts them above the page surface.
- Toasts: elevated with shadow, distinct from page content.
- Dark mode: use slightly lighter surfaces for elevated elements instead of shadows.

---

## 3. Visual Hierarchy

### Scanning Patterns

**F-Pattern** (text-heavy pages — docs, search results, settings):
- Place the most important content in the first two lines.
- Use strong left-aligned headings as scannable anchors.
- Bullet points and bold keywords on the left edge.

**Z-Pattern** (minimal-text pages — landing, marketing, login):
- Top-left: logo/brand. Top-right: CTA or navigation.
- Diagonal: key visual/content. Bottom-right: primary action.

### Hierarchy Tools (in order of impact)
1. **Size** — Primary headings 2-3x body text size.
2. **Weight** — `font-semibold` (600) for emphasis, `font-bold` (700) for headings. Reserve 800-900 for hero only.
3. **Color contrast** — High contrast for primary content (`text-foreground`); reduced for secondary (`text-muted-foreground`).
4. **Whitespace** — More space around an element = more importance.
5. **Position** — Top-left gets seen first (in LTR layouts).

### Hierarchy in Components
```
Card:
├── Image/media         (visual anchor, optional)
├── Title               (text-lg font-semibold text-foreground)
├── Description         (text-sm text-muted-foreground, line-clamp-2)
├── Metadata            (text-xs text-muted-foreground)
└── Actions             (separated by spacing or border-t)
```

---

## 4. Typography

### Type Scale
Use a **modular scale** with ratio **1.2-1.25** for app UIs, **1.333** for content sites:

| Token | Size | Usage |
|-------|------|-------|
| `text-xs` | 12px | Captions, badges, timestamps |
| `text-sm` | 14px | Secondary text, labels, helper text |
| `text-base` | 16px | Body text (minimum for readability) |
| `text-lg` | 18px | Card titles, subheadings |
| `text-xl` | 20px | Section headings |
| `text-2xl` | 24px | Page headings |
| `text-3xl` | 30px | Hero subheading |
| `text-4xl` | 36px | Hero heading |

### Line Height
- Body text: `leading-relaxed` (1.625) or `leading-normal` (1.5) — WCAG recommends at least 1.5.
- Headings: `leading-tight` (1.25) or `leading-snug` (1.375).
- Small text: `leading-normal` (1.5) minimum.

### Line Width
- **Optimal: 45-75 characters** per line. Target ~65ch.
- Use `max-w-prose` (65ch) on text containers. Or `max-w-2xl` (~42rem) for wider layouts.
- Never let body text span the full viewport width on desktop.

### Fluid Typography
```css
h1 { font-size: clamp(1.75rem, 1rem + 2.5vw, 3rem); }
h2 { font-size: clamp(1.375rem, 0.875rem + 1.5vw, 2.25rem); }
body { font-size: clamp(1rem, 0.875rem + 0.5vw, 1.125rem); }
```

### Rules
- **Never go below 12px** for any text. 14px minimum for content users need to read.
- Limit to **2 typefaces** max (one heading, one body). In most apps, one font family is enough.
- Limit to **~7 distinct sizes** in the whole system.
- Paragraphs: `text-muted-foreground` for secondary, `text-foreground` for primary.

---

## 5. Color

### Contrast Requirements (WCAG)

| Element | AA | AAA |
|---------|-----|------|
| Normal text (<18px) | 4.5:1 | 7:1 |
| Large text (≥18px / ≥14px bold) | 3:1 | 4.5:1 |
| UI components & graphics | 3:1 | — |

83.6% of websites fail contrast requirements (WebAIM 2024). Always verify.

### Semantic Color Usage
```
Primary (brand)     — main CTAs, active states, links
Destructive (red)   — delete, errors, critical warnings
Success (green)     — confirmations, completion, positive states
Warning (amber)     — cautions, non-critical alerts
Muted (grey)        — secondary text, borders, disabled states
```

### Dark Mode
- **Never use pure black** `#000` as background. Use `#0a0a0a` or `#121212`.
- Surface elevation: progressively lighter backgrounds (`#0a0a0a` → `#141414` → `#1e1e1e`).
- Desaturate bright colors — they bleed/vibrate on dark backgrounds.
- Text: primary at **87% opacity** white, secondary at **60%** opacity.
- Shadows are ineffective on dark backgrounds — use lighter surface colors for elevation.
- **Always test contrast in both modes.** A color passing in light mode may fail in dark.

### OKLCH Palette Strategy
Lock lightness across hues for predictable contrast:
```css
/* Shade 700 (L=38%) on shade 200 (L=89%) ≈ 7:1 contrast (AAA) */
--brand-200: oklch(89% 0.08 250);
--brand-500: oklch(60% 0.27 250); /* primary action */
--brand-700: oklch(38% 0.12 250); /* text on light bg */
```

---

## 6. Spacing System

### The 4px/8px Grid
All spacing derives from a **4px base unit**. Primary steps are multiples of 8px.

| Tailwind | Pixels | Usage |
|----------|--------|-------|
| `gap-1` / `p-1` | 4px | Icon-to-text gap, fine adjustments |
| `gap-2` / `p-2` | 8px | Intra-component spacing, tight gaps |
| `gap-3` / `p-3` | 12px | Related element spacing, form field gaps |
| `gap-4` / `p-4` | 16px | Default card padding, list item spacing |
| `gap-5` / `p-5` | 20px | Medium separation |
| `gap-6` / `p-6` | 24px | Section content padding, card padding (spacious) |
| `gap-8` / `p-8` | 32px | Major section gaps |
| `gap-12` | 48px | Section separation (desktop) |
| `gap-16` | 64px | Page-level spacing, hero sections |

### Spacing Rules
1. **Internal < External**: padding inside a group must be less than margin around the group.
2. **Hierarchy through spacing**: more space = more separation = less related.
3. **Responsive scaling**: use larger spacing on desktop, tighter on mobile.
4. **Line-height alignment**: body 16px × 1.5 = 24px line-height (multiple of 8).
5. **Consistent padding**: same padding on all sides within a component.

---

## 7. Layout

### Max Content Width
- Standard content: `max-w-7xl` (1280px) or `max-w-screen-xl`.
- Text-heavy content: `max-w-prose` (65ch ≈ 700px).
- Wide dashboards: `max-w-screen-2xl` (1536px).
- **Always constrain width** — never let content stretch full viewport on ultra-wide screens.

### Responsive Grid
```tsx
{/* Self-responsive, no breakpoints needed */}
<div className="grid grid-cols-[repeat(auto-fill,minmax(min(280px,100%),1fr))] gap-4">
  {items.map(item => <Card key={item.id} {...item} />)}
</div>
```

### Breakpoint Strategy (mobile-first)

| Tailwind | Width | Target |
|----------|-------|--------|
| default | 0px+ | Mobile (single column) |
| `sm:` | 640px+ | Large phones landscape |
| `md:` | 768px+ | Tablets |
| `lg:` | 1024px+ | Small laptops |
| `xl:` | 1280px+ | Desktops |
| `2xl:` | 1536px+ | Large desktops |

**2026 preference**: container queries + intrinsic layouts (Grid `auto-fill`/`minmax`, Flexbox `flex-wrap`) over explicit breakpoints. Use breakpoints only for major layout shifts (sidebar collapse, navigation switch).

### Touch Targets
- **Minimum: 44×44px** (WCAG 2.5.8), recommended **48×48px** (Material Design).
- Spacing between adjacent targets: **≥ 8px** gap to prevent mis-taps.
- Sticky nav bars: **44-48px** height minimum.
- Inline text links within content: **27×27px** minimum is acceptable.

---

## 8. Component UX Patterns

### Forms
- **Validate on blur** for new input; **validate on keystroke** when correcting an error ("Reward early, punish late").
- Empty required fields: validate **only on submit**, not on blur.
- Real-time validation (password strength, username): debounce **300-500ms** after last keystroke.
- Error placement: **directly below the field**. Use 3 signals: red border + icon + text message.
- Error text: explicit, polite, constructive ("Please enter a valid email" not "Error 422").
- On submit with errors: scroll to first error, focus it, show summary at top for long forms.
- Always support **keyboard submission** (Enter key).
- Smart defaults: pre-fill from locale (country, date format, currency).

### Navigation
- **Sidebar** (220-280px): best for 6-30+ items. Collapse to icon-only (64px) on tablet/mobile.
- **Active state**: background color + left border accent (3-4px).
- **Tabs**: use for 2-7 same-level sections. Never for sequential steps (use stepper).
- **Breadcrumbs**: supplement to primary nav, never replacement. Full hierarchy, each level clickable except current page. On mobile: truncate to parent only.
- **Mobile bottom tab bar**: best for 3-5 primary destinations. 48px targets. Persistent.
- **Hamburger menu**: last resort — hides navigation, reduces discoverability.

### Loading States
- **< 1 second**: show nothing.
- **1-3 seconds**: skeleton screen for full-page loads; spinner for single-component.
- **3-10 seconds**: skeleton screens strongly preferred.
- **> 10 seconds**: percent-done progress bar.
- Skeletons **must match the final layout** — grey boxes for text lines, circles for avatars, rectangles for images. Mismatched skeletons are worse than spinners.
- Subtle pulse/shimmer animation. Respect `prefers-reduced-motion`.

### Empty States
Every empty state needs three things:
1. **Status**: explain *why* it's empty ("No results match your filters").
2. **Learning cue**: teach what will populate the area ("Star favorites to list them here").
3. **Direct action**: CTA to start the workflow ("Create your first project" with primary button).

### Error Handling
- **Inline errors**: below the field/component. Red with icon. Never clear user input on error.
- **Toast notifications**: for success confirmations only. Auto-dismiss after **5-8 seconds**. Error toasts must be **persistent** (user-dismissible).
- **Toast position**: top-right or bottom-right on desktop; top-center on mobile. Consistent.
- **Error pages (404/500)**: plain language, search bar, links to Home and key sections, retry button.
- **Retry pattern**: show inline error with "Retry" button at point of failure.
- **Never** show stack traces or technical codes to users.

### Modals & Dialogs
- **Use when**: critical warnings, irreversible actions, short focused tasks (2-3 inputs max).
- **Don't use when**: complex workflows, tasks needing background content, anything during checkout.
- **If scrolling or > 3 inputs**: use a dedicated page/panel instead.
- **Focus trap**: on open, focus first interactive element. Tab cycles within modal.
- **Escape key**: always closes. Backdrop click: closes for non-destructive dialogs.
- **Scroll lock**: `overflow: hidden` on `<body>`.
- **Return focus**: on close, return focus to the trigger element.
- **Confirmation labels**: specific verbs ("Delete project" / "Cancel"), never "Yes" / "No".
- **Destructive button**: secondary style (not primary). "Cancel" gets equal or higher visual weight.

### Tables & Data
- **Sortable columns**: arrow icon in header. Default sort matches common task (newest first for logs).
- **Pagination**: when users need specific items, position references, shareable links.
- **Load More button**: best compromise for most content sites.
- **Infinite scroll**: only for discovery/browsing feeds (social, galleries).
- **Row height**: 40-48px default (comfortable). 32-36px for power users (dense mode).
- **Responsive**: sticky first column + horizontal scroll, or row-to-card stacking on mobile.
- **Row actions**: primary action inline (icon), secondary in "..." overflow menu.

### Cards
- Internal padding: `p-4` (16px) baseline. Dense: `p-3`. Spacious: `p-5` to `p-6`.
- Grid gap: match internal padding (`gap-4` to `gap-6`).
- **Clickable cards**: entire surface clickable for primary action. Secondary actions have separate targets with `stopPropagation`.
- Hover: subtle elevation (`hover:shadow-md`) and/or background tint.
- Use `line-clamp-2` or `line-clamp-3` on descriptions for uniform card heights.
- Grid: `grid-cols-[repeat(auto-fill,minmax(280px,1fr))]` — single column mobile, 2 tablet, 3-4 desktop.

---

## 9. Micro-interactions & Transitions

### State Requirements
Every interactive element needs 4 visual states:
1. **Default** — resting state
2. **Hover** — subtle background change, underline for links, elevation for cards
3. **Focus-visible** — `ring-2 ring-ring ring-offset-2` (2px ring, 2px offset, high-contrast color)
4. **Active/pressed** — `scale(0.97)` or darken background

### Transition Durations

| Interaction | Duration | Easing |
|-------------|----------|--------|
| Color change, opacity | 100ms | `ease` |
| Hover states | 150ms | `ease-in-out` |
| Modal/dropdown enter | 200-300ms | `ease-out` |
| Modal/dropdown exit | 150-250ms | `ease-in` |
| Page transitions | 300-500ms | `ease-out` |

- **Exits 20% faster than entrances.**
- **Never exceed 500ms** — feels sluggish.
- **Never use `linear`** — feels mechanical and unnatural.
- Tailwind: `transition-colors duration-150`, `transition-all duration-200 ease-out`.

### Button Feedback
- Click: show pressed state immediately (`active:scale-[0.97]`).
- Async action: inline spinner replacing text/icon; disable button to prevent double-submit.
- Completion: brief success state (checkmark, green flash) for 1-1.5 seconds, then return to default.

### Animations & Motion Safety
```css
/* Progressive enhancement: animations opt-in */
@media (prefers-reduced-motion: no-preference) {
  .animate-enter {
    animation: fadeInUp 0.3s ease-out;
  }
}

@keyframes fadeInUp {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}
```

**Safe motion**: opacity changes, small horizontal movements, subtle scaling.
**Avoid**: parallax, large zooms, spinning/rotation, auto-playing backgrounds.
**Max distance**: movement < 5x the element's own size.

---

## 10. Accessibility Deep Dive

### WCAG 2.2 Key Requirements (AA)

| Criterion | Requirement |
|-----------|-------------|
| 1.4.3 Contrast | Text 4.5:1, large text 3:1 |
| 1.4.4 Resize | Usable at 200% zoom |
| 1.4.10 Reflow | No horizontal scroll at 320px width |
| 1.4.11 Non-text Contrast | UI components 3:1 |
| 2.1.1 Keyboard | All functionality via keyboard |
| 2.4.7 Focus Visible | Focus indicator always visible |
| 2.4.11 Focus Not Obscured | Focused element not hidden by sticky headers/banners |
| 2.4.13 Focus Appearance | Focus indicator ≥ 2px, 3:1 contrast |
| 2.5.7 Dragging | Drag actions must have click/tap alternatives |
| 2.5.8 Target Size | Interactive targets ≥ 24×24 CSS pixels |
| 3.2.6 Consistent Help | Help mechanisms in same location across pages |
| 3.3.7 Redundant Entry | Don't re-ask info already provided in session |

### Keyboard Navigation

**Tab order**: follows DOM order. Never use positive `tabindex`. Use `tabindex="0"` to add to flow, `tabindex="-1"` for programmatic focus only.

**Skip link**: first focusable element in `<body>`, targets `<main>`. Visible on `:focus`.

**Roving tabindex** (tabs, toolbars, menus):
- Only active item has `tabindex="0"`; others have `tabindex="-1"`.
- Arrow keys move within group; Tab exits the group.

### ARIA Landmarks

| Role | Element | Rule |
|------|---------|------|
| `banner` | `<header>` | One per page |
| `main` | `<main>` | One per page |
| `navigation` | `<nav>` | Label each if multiple |
| `complementary` | `<aside>` | Supporting content |
| `contentinfo` | `<footer>` | Copyright, legal |
| `search` | `<search>` | Search areas |

- Prefer semantic HTML over ARIA roles.
- When multiple same-type landmarks exist, give each a unique `aria-label`.
- Don't include the role in the label (avoid "Site Navigation" on `<nav>`).

### Live Regions
```html
<!-- Success/status (polite — waits for current speech) -->
<div aria-live="polite" aria-atomic="true">3 items saved</div>

<!-- Errors (assertive — interrupts immediately) -->
<div role="alert">Error: Email is required</div>
```

### Screen Reader Hidden Content
```css
/* Visually hidden, screen-reader accessible */
.sr-only {
  position: absolute;
  width: 1px; height: 1px;
  padding: 0; margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}
```
- `aria-hidden="true"` — hidden from SR, visible on screen (decorative icons with adjacent text).
- `display: none` — hidden from both SR and screen.
- `.sr-only` (Tailwind class) — hidden from screen, visible to SR.

---

## 11. Responsive Design

### Mobile-First
Base styles = mobile. Layer complexity with `min-width`:
```tsx
<div className="flex flex-col md:flex-row gap-4 md:gap-8">
```

### Container Queries (93%+ browser support, 2026)
Components style themselves based on container width, not viewport:
```css
.card-wrapper { container: card / inline-size; }
@container card (width > 480px) { .card { flex-direction: row; } }
```

### Fluid Typography
```css
h1 { font-size: clamp(1.75rem, 1rem + 2.5vw, 3rem); }
body { font-size: clamp(1rem, 0.875rem + 0.5vw, 1.125rem); }
```

### Thumb Zones (Mobile)
- 49% of users hold phone one-handed.
- Primary actions: **bottom-center** (easiest reach).
- Avoid critical actions in **top-left** (hardest reach).
- Bottom navigation > hamburger for discoverability and reachability.

### Bottom Sheets
- Visible Close button (not just drag handle).
- Drag handle: 32-40px wide, 4px tall, centered, rounded.
- Dismiss by: swipe down, Close button, backdrop tap (non-critical).
- Snap to defined detents (40%, 90% viewport height).

---

## 12. Performance UX

### Core Web Vitals (2026)

| Metric | Good | Poor |
|--------|------|------|
| LCP (Largest Contentful Paint) | < 2.5s | > 4.0s |
| INP (Interaction to Next Paint) | < 200ms | > 500ms |
| CLS (Cumulative Layout Shift) | < 0.1 | > 0.25 |

### Key Optimizations
- **LCP**: never lazy-load the hero image. Use `fetchpriority="high"`. Preload critical assets. Inline critical CSS.
- **CLS**: always set `width`/`height` or `aspect-ratio` on images/video. Reserve space for dynamic content with `min-height`.
- **INP**: debounce/throttle high-frequency handlers. Break long tasks with `scheduler.yield()`. Use `content-visibility: auto` for off-screen content.
- **Perceived performance**: skeleton screens, optimistic UI, progressive loading. A fast-feeling app > a technically fast app.

### Optimistic UI Rules
- Use when success rate > 97% and action is low-risk (likes, toggles, adding to lists).
- Show success within **100ms**. Send request async.
- On failure: revert within **2 seconds**. Show inline error with retry.
- **Never use for**: payments, deletions, account changes.

---

## 13. Modern Design Patterns (2025-2026)

### Bento Grids
Modular, asymmetric grid layouts. Each cell is a self-contained module.
```tsx
<div className="grid grid-cols-4 gap-4">
  <div className="col-span-2 row-span-2">Feature card</div>
  <div className="col-span-1">Stat</div>
  <div className="col-span-1">Stat</div>
</div>
```

### Command Palettes
Accessible search-based navigation (`Cmd+K` / `Ctrl+K`). Gravity UI does not ship a dedicated palette — compose one from `Dialog` + `TextInput` + `Menu`/`List`, or wire in `cmdk` if you need fuzzy-search and section grouping out of the box.
- Built-in fuzzy search, keyboard navigation, section grouping.
- Handles 2,000-3,000 items without virtualization.

### Glassmorphism (use sparingly)
```tsx
<div className="rounded-xl border border-white/10 bg-white/5 backdrop-blur-sm">
```
- Blur: 8-12px. Most effective on dark backgrounds.
- **Must maintain contrast ratios** for text over blurred backgrounds.

### Dark Mode as Primary
- Surface hierarchy: `#0a0a0a` (base) → `#141414` (elevated) → `#1e1e1e` (overlay).
- Text: primary 87% white, secondary 60% white.
- Implement with CSS custom properties for instant theme switching.
