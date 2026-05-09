# Visual Style Guide

Default aesthetic direction for all UI work. Dark, sharp, minimal — every pixel intentional.

---

## Philosophy

**Sharp minimalism.** Interfaces should feel like precision instruments — clean, dense where needed, spacious where it matters. No decoration for decoration's sake. Every element earns its place. The aesthetic is inspired by tools like Linear, Vercel, Raycast, and Figma's dark mode.

The three principles:
1. **Subtract** — remove elements until the next removal would break function.
2. **Contrast** — guide the eye through stark differences in brightness, weight, and scale.
3. **Precision** — pixel-perfect alignment, consistent spacing, no visual noise.

---

## Color Palette

### Dark-first design

The default theme is **dark**. Light mode is the secondary theme.

```css
/* Base surfaces — near-black, never pure #000 */
--background:       oklch(0.10 0.005 260);   /* #0a0a0b — deepest background */
--surface:          oklch(0.13 0.005 260);   /* #141416 — cards, panels */
--surface-elevated: oklch(0.16 0.005 260);   /* #1e1e21 — dropdowns, popovers, modals */
--surface-hover:    oklch(0.19 0.005 260);   /* #272729 — hover states on surfaces */

/* Borders — subtle, low-contrast */
--border:           oklch(0.22 0.005 260);   /* #2e2e31 — default borders */
--border-strong:    oklch(0.30 0.005 260);   /* #3e3e42 — emphasized borders, dividers */

/* Text */
--foreground:       oklch(0.93 0.005 260);   /* #ebebec — primary text, ~93% white */
--muted-foreground: oklch(0.55 0.005 260);   /* #7c7c80 — secondary text, labels, placeholders */
--faint:            oklch(0.40 0.005 260);   /* #555558 — disabled, hints */

/* Accent — single brand color, used sparingly */
--accent:           oklch(0.65 0.00 0);      /* neutral white-ish — or pick one sharp accent */
/* Alternative accents if brand needs color: */
/* --accent:        oklch(0.65 0.25 250);    /* blue */
/* --accent:        oklch(0.70 0.20 145);    /* green */
/* --accent:        oklch(0.65 0.25 30);     /* orange */

/* Semantic */
--destructive:      oklch(0.60 0.22 25);     /* muted red — not screaming */
--success:          oklch(0.62 0.18 155);    /* muted green */
--warning:          oklch(0.70 0.16 80);     /* muted amber */
--info:             oklch(0.62 0.15 250);    /* muted blue */
```

### Rules
- **Primary surfaces**: dark grey, not black. Pure `#000` only for OLED-optimized mobile backgrounds.
- **Elevation through brightness**: deeper = darker, elevated = slightly lighter. No box-shadows for elevation in dark mode.
- **Borders**: subtle, 1px, low-contrast. `border-border` default. `border-border-strong` for emphasis.
- **Text hierarchy**: 3 levels max — `text-foreground` (primary), `text-muted-foreground` (secondary), `text-faint` (tertiary/disabled).
- **Accent usage**: sparingly — active states, selected items, primary CTA. Not on backgrounds or large areas.
- **No gradients** unless they serve a function (progress bars). Flat, solid colors.

### Light mode overrides
Invert the palette — white/off-white backgrounds, dark text. Keep the same accent. Maintain the same sharp, minimal feel — light mode should not feel "softer", just brighter.

---

## Border Radius

**Small roundings. Never pill-shaped.**

| Element | Radius | Tailwind |
|---------|--------|----------|
| Buttons, inputs, selects | 6px | `rounded-md` |
| Cards, panels, modals | 8px | `rounded-lg` |
| Dropdowns, popovers, tooltips | 6px | `rounded-md` |
| Badges, tags | 4px | `rounded` |
| Avatars | 6px (square-ish) | `rounded-md` |
| Full-page containers | 0px | `rounded-none` |
| Checkboxes | 4px | `rounded` |
| Toggles/switches | use shadcn default (pill is acceptable here only) | — |

### Rules
- **Default: `rounded-md` (6px).** This is the base for most interactive elements.
- **Max: `rounded-lg` (8px)** for large containers (cards, dialogs, sheets).
- **Never `rounded-full`** except for toggles/switches and icon-only circular buttons.
- **Never `rounded-xl`, `rounded-2xl`, `rounded-3xl`** — they look soft and bubbly. This is a sharp interface.
- Consistency: if buttons are `rounded-md`, inputs must be `rounded-md` too. Same visual family.

---

## Spacing & Density

### Compact by default

This style favors **information density** — more content visible, less wasted space, but never cramped.

| Context | Padding | Tailwind |
|---------|---------|----------|
| Buttons | 8px vertical, 16px horizontal | `py-2 px-4` |
| Inputs | 8px vertical, 12px horizontal | `py-2 px-3` |
| Cards | 16px all sides | `p-4` |
| Card (spacious variant) | 20-24px | `p-5` or `p-6` |
| Table rows | 8-12px vertical | `py-2` or `py-3` |
| Table cells | 12-16px horizontal | `px-3` or `px-4` |
| Modal body | 24px | `p-6` |
| Sidebar items | 6-8px vertical, 12px horizontal | `py-1.5 px-3` or `py-2 px-3` |
| Page sections | 32-48px gap | `gap-8` to `gap-12` |

### Rules
- **Tight internal, generous external.** Elements within a group are close. Groups are clearly separated.
- **Row height**: default interactive row = 36px (`h-9`). Comfortable = 40px (`h-10`). Compact = 32px (`h-8`).
- **Gap between related elements**: `gap-2` to `gap-3` (8-12px).
- **Gap between sections**: `gap-6` to `gap-8` (24-32px).
- **Page horizontal padding**: `px-4` mobile, `px-6` tablet, `px-8` desktop.
- **Max content width**: `max-w-6xl` (1152px) for app content. `max-w-prose` for text.

---

## Typography

### Font Stack
```css
--font-sans: "Inter", "SF Pro Display", -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
--font-mono: "JetBrains Mono", "SF Mono", "Fira Code", ui-monospace, monospace;
```

If Inter is unavailable, system fonts are acceptable. **Never use decorative fonts** in app UI. For landing pages or marketing, a geometric sans-serif (Geist, Satoshi, General Sans) is acceptable.

### Scale

| Role | Size | Weight | Tailwind |
|------|------|--------|----------|
| Page title | 24px | 600 | `text-2xl font-semibold` |
| Section heading | 18px | 600 | `text-lg font-semibold` |
| Card title | 14-16px | 500-600 | `text-sm font-medium` or `text-base font-semibold` |
| Body | 14px | 400 | `text-sm` |
| Label | 13-14px | 500 | `text-sm font-medium` |
| Caption / helper | 12px | 400 | `text-xs` |
| Badge / tag text | 11-12px | 500 | `text-xs font-medium` |

### Rules
- **Default body text: `text-sm` (14px).** This is denser than the typical 16px but standard for tool/app interfaces (Linear, Vercel, GitHub all use 14px body).
- Headings: `font-semibold` (600). Never `font-bold` (700) inside app UI — it's too heavy. Reserve bold for marketing/landing pages.
- **Tracking**: default or slightly tighter for headings (`tracking-tight`). Default for body.
- **Uppercase text**: use only for small labels/badges, always with `tracking-wider text-xs font-medium`.
- **Monospace** for: code, numbers in tables, technical values, keyboard shortcuts.
- **No italic** in UI text. Italic is for content (articles, quotes), not interface elements.

---

## Shadows & Elevation

### Dark mode
- **No box-shadows.** Elevation = lighter background color. The surface stack handles depth:
  `background` → `surface` → `surface-elevated`
- **Borders define boundaries**, not shadows. A card is `border border-border bg-surface`, not `shadow-md`.

### Light mode
- Subtle shadows are acceptable: `shadow-sm` for dropdowns/popovers, `shadow-md` for modals.
- Still prefer borders over shadows where possible.
- Never `shadow-lg`, `shadow-xl`, `shadow-2xl` — they look puffy and unsharp.

---

## Borders

- Default: `border border-border` — 1px, subtle, low-contrast.
- Emphasis: `border-border-strong` — for active states, focused inputs, section dividers.
- **Dividers**: prefer `border-b border-border` over `<hr>`. Thin, quiet lines.
- **No double borders.** If a card has a border and sits next to another card, use gap instead of adjacent borders.
- **Focus ring**: `ring-1 ring-ring ring-offset-1 ring-offset-background` — thin, tight, visible.

---

## Icons

- Use **Lucide** icons (default in shadcn/ui). Consistent stroke width, clean geometry.
- Default size: `size-4` (16px) for inline/button icons. `size-5` (20px) for standalone.
- **Stroke width**: 1.5px (Lucide default). Never 2px or thicker — it looks heavy in a sharp UI.
- Color: `text-muted-foreground` default. `text-foreground` for emphasis/interactive.
- No colored icons unless semantic (red for destructive, green for success).

---

## Buttons

```tsx
/* Primary — dark bg on dark surfaces is inverted: light bg, dark text */
<Button>Save changes</Button>
/* → bg-primary text-primary-foreground rounded-md h-9 px-4 text-sm font-medium */

/* Secondary — subtle, low emphasis */
<Button variant="secondary">Cancel</Button>
/* → bg-surface-elevated text-foreground border border-border rounded-md */

/* Ghost — no background until hover */
<Button variant="ghost">Edit</Button>
/* → hover:bg-surface-hover text-muted-foreground rounded-md */

/* Destructive — muted red, not screaming */
<Button variant="destructive">Delete</Button>
/* → bg-destructive text-destructive-foreground rounded-md */
```

### Rules
- Default height: `h-9` (36px). Small: `h-8` (32px). Large: `h-10` (40px).
- **No rounded-full buttons** (except icon-only circular actions).
- **One primary button per view.** Everything else: secondary, ghost, or outline.
- Icon + text: icon left, `gap-2`, icon `size-4`.
- Icon-only: `size-9` square, icon centered. Tooltip required for accessibility.
- Loading state: spinner replaces icon (or text), button stays same width, disabled.

---

## Inputs & Forms

```tsx
<Input className="h-9 rounded-md border-border bg-surface px-3 text-sm" />
```

- Height: `h-9` (matches buttons). Small: `h-8`.
- Background: `bg-surface` (slightly lighter than page background), not transparent.
- Border: `border-border`, focus: `ring-1 ring-ring`.
- Placeholder: `text-muted-foreground`.
- Labels: above the input, `text-sm font-medium`, `mb-1.5`.
- Helper text: below input, `text-xs text-muted-foreground`, `mt-1.5`.
- Error: `border-destructive`, error text `text-destructive text-xs mt-1.5`.

---

## Tables

- Header: `text-xs font-medium text-muted-foreground uppercase tracking-wider bg-surface`.
- Rows: `border-b border-border`. No zebra striping — use hover: `hover:bg-surface-hover`.
- Cells: `text-sm py-2.5 px-3`.
- Compact: `py-1.5 px-3 text-xs`.
- Sortable columns: subtle arrow icon in header. Active sort: `text-foreground` (not muted).
- No outer border on the table. Let it breathe against the page.

---

## Cards

```tsx
<div className="rounded-lg border border-border bg-surface p-4">
  <h3 className="text-sm font-medium">Title</h3>
  <p className="mt-1 text-sm text-muted-foreground">Description</p>
</div>
```

- `rounded-lg` (8px) — the sharpest container rounding.
- `border border-border` — visible boundary, subtle.
- `bg-surface` — distinct from page `bg-background`.
- **No shadow in dark mode.** Light mode: `shadow-sm` acceptable.
- Clickable cards: `hover:bg-surface-hover hover:border-border-strong transition-colors cursor-pointer`.

---

## Modals & Sheets

- Backdrop: `bg-black/60 backdrop-blur-sm` — dark, slightly blurred.
- Dialog: `rounded-lg border border-border bg-surface p-6`. Max width: `max-w-md` for small, `max-w-lg` for medium.
- Header: `text-lg font-semibold`. Close button: top-right, ghost, `size-4` X icon.
- Footer: `border-t border-border pt-4 mt-6 flex justify-end gap-2`.
- Sheet (side panel): `rounded-none` on the attached edge, `rounded-lg` on corners facing content.

---

## Applying This Style to shadcn/ui

When initializing shadcn, customize `globals.css` to match:

```css
@theme {
  --radius: 0.375rem;  /* 6px — base radius */
}

:root {
  /* Override shadcn's default rounded tokens */
  /* All components inherit from --radius */
}

.dark {
  --background: 240 6% 4%;      /* #0a0a0b */
  --foreground: 240 2% 93%;     /* #ebebec */
  --card: 240 5% 8%;            /* #141416 */
  --card-foreground: 240 2% 93%;
  --popover: 240 5% 10%;        /* #1e1e21 */
  --popover-foreground: 240 2% 93%;
  --primary: 0 0% 93%;          /* light on dark = inverted primary */
  --primary-foreground: 240 6% 4%;
  --secondary: 240 5% 12%;
  --secondary-foreground: 240 2% 93%;
  --muted: 240 4% 16%;
  --muted-foreground: 240 2% 55%;
  --accent: 240 4% 16%;
  --accent-foreground: 240 2% 93%;
  --destructive: 0 60% 50%;
  --destructive-foreground: 0 0% 98%;
  --border: 240 4% 18%;
  --input: 240 4% 18%;
  --ring: 240 2% 55%;
}
```

---

## Quick Reference: What NOT to Do

| Don't | Do instead |
|-------|-----------|
| `rounded-full` on buttons/cards | `rounded-md` (6px) or `rounded-lg` (8px) |
| `rounded-xl` / `rounded-2xl` | `rounded-lg` max |
| `shadow-lg`, `shadow-xl` | `border border-border` (dark mode), `shadow-sm` (light) |
| Pure `#000000` background | `#0a0a0b` or near-black |
| Gradients on surfaces | Flat, solid colors |
| `font-bold` (700) in UI | `font-semibold` (600) max |
| 16px body text in app UI | 14px (`text-sm`) for density |
| Colored backgrounds on cards | `bg-surface` with border |
| Thick borders (2px+) | 1px `border-border` |
| Decorative icons, emojis | Functional Lucide icons only |
| Rounded avatars | Square-ish `rounded-md` avatars |
| Zebra-striped tables | `hover:bg-surface-hover` |
