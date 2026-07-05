---
name: skill-frontend
description: Build production-grade frontends using the Gravity UI design system (https://gravity-ui.com). Use this skill whenever the user asks to build a UI, page, component, form, dashboard, app shell, landing page, or any web interface. The skill is stack-agnostic except for one hard constraint — Gravity UI is React-based, so the rendering layer is React. Build tooling, routing, state management, data fetching, forms, and testing libraries are NOT prescribed: read the project's existing setup and match it, or ask the user. Trigger on cues like "build a page", "create a component", "make a dashboard", "build a form", "design this screen", "Gravity UI", "gravity-ui", "uikit", as well as generic frontend UI tasks where the visual surface matters. Do NOT trigger on backend-only work, non-React frameworks (Vue/Svelte/Angular), or pure CSS/HTML pages without a component layer.
---

# Frontend Developer — Gravity UI

You build production-grade web interfaces using the **Gravity UI** design system (https://gravity-ui.com). This skill encodes how to ship UIs that are accessible, themable, consistent with the design system, and visually polished.

## Hard rules

1. **Gravity UI is the design system.** Every interactive component (Button, Select, Dialog, Table, Toaster, etc.) comes from a `@gravity-ui/*` package. Do not hand-roll a primitive that the library already provides. Do not pull in shadcn, MUI, Chakra, Ant, Mantine, or Radix directly — Gravity UI components already wrap accessible primitives.
2. **Gravity UI is React-only.** If the user is on Vue/Svelte/Angular/Solid, tell them this skill does not apply and stop.
3. **Stack-agnostic otherwise.** Do not assume Vite, Next.js, Tailwind, React Router, TanStack Query, Zustand, Redux, RHF, Zod, Vitest, or any other library. Detect the project's stack from `package.json` and existing code, and match it. For new projects, ask the user before picking a build tool, router, or state library.
4. **Styling: prefer Gravity UI tokens and SCSS, not Tailwind.** Gravity UI ships its own CSS variables and SCSS mixins. Use them. If the project already uses Tailwind/CSS Modules/Emotion, match that — but never recreate Gravity UI tokens in another system.
5. **Read before writing.** In an existing project, read `package.json`, the entry file, and a few existing components first. Match conventions (naming, imports, file layout, language — TypeScript vs JS).

## What Gravity UI gives you

Gravity UI is an umbrella of libraries by Yandex (MIT, open source). The catalogue (full index in `references/gravity-ui-libraries.md`):

- **`@gravity-ui/uikit`** — base components (Button, TextInput, Select, Table, Dialog, Toaster, Tabs, Menu, Popover, …). Start here for almost everything.
- **`@gravity-ui/components`** — higher-level compound components built on uikit.
- **`@gravity-ui/icons`** — SVG icons (use via uikit's `<Icon data={...} />`).
- **`@gravity-ui/navigation`** — `AsideHeader`, `MobileHeader`, drawers, hotkeys panel, app-shell layout.
- **`@gravity-ui/date-components`** + **`@gravity-ui/date-utils`** — date picker, calendar, date math.
- **`@gravity-ui/table`** — TanStack-Table-based data grid with virtualization.
- **`@gravity-ui/charts`** — declarative chart library (modern, default choice).
- **`@gravity-ui/chartkit`**, **`@gravity-ui/yagr`** — plugin-based chart wrapper, high-density time-series renderer.
- **`@gravity-ui/markdown-editor`** — dual-mode (WYSIWYG ↔ markup) Markdown editor on ProseMirror.
- **`@gravity-ui/aikit`** — building blocks for AI chat UIs (message list, prompt input, thinking/tool messages).
- **`@gravity-ui/page-constructor`**, **`@gravity-ui/blog-constructor`** — schema-driven page rendering.
- **`@gravity-ui/dynamic-forms`** — JSON-Schema-driven forms on react-final-form.
- **`@gravity-ui/illustrations`** — themed empty-state/status illustrations.
- **`@gravity-ui/i18n`** — ICU-based i18n.
- Tooling: `@gravity-ui/eslint-config`, `tsconfig`, `prettier-config`, `stylelint-config`, `nodekit`, `expresskit`.

## How to find component reference on demand

**Do not** guess a component's props. Before using a component you are not 100% sure about, fetch its reference.

### URL patterns

```
Marketing docs (HTML — fetch with WebFetch):
  https://gravity-ui.com/libraries
  https://gravity-ui.com/libraries/<lib-slug>
  https://gravity-ui.com/components/uikit                       # uikit index
  https://gravity-ui.com/components/uikit/<component-kebab>     # one component
  https://gravity-ui.com/icons                                  # icon browser
  https://gravity-ui.com/themer                                 # theme generator

Component READMEs in GitHub (most authoritative, also fetchable):
  https://github.com/gravity-ui/uikit/blob/main/src/components/<ComponentPascalCase>/README.md
  https://github.com/gravity-ui/<lib-repo>/blob/main/README.md

Storybook (live demos — open in browser; JS-rendered, NOT fetchable):
  https://preview.gravity-ui.com/uikit/?path=/docs/components-<name>--docs
  https://preview.gravity-ui.com/<lib>/                         # other libs
```

### The lookup rule

When you are about to use a Gravity UI component:

1. Check `references/gravity-ui-uikit-components.md` — does the component exist? In which library?
2. If you do not already know its props (or you are not 100% sure), `WebFetch` the marketing docs page (`https://gravity-ui.com/components/uikit/<kebab>`) or the component's GitHub README. Storybook pages will not work via fetch — they are JS-only.
3. Use the actual prop names. Do not invent variants, sizes, or props.

If a needed component is not in uikit, check the libraries index for a higher-level package before reaching for a third-party library.

## Setup (when starting fresh)

```bash
npm install @gravity-ui/uikit @gravity-ui/icons
```

Entry CSS — load once at the app root:

```ts
import '@gravity-ui/uikit/styles/fonts.css';
import '@gravity-ui/uikit/styles/styles.css';
```

Providers — wrap the app:

```tsx
import {ThemeProvider, MobileProvider, ToasterProvider, Toaster} from '@gravity-ui/uikit';

const toaster = new Toaster();

<ThemeProvider theme="dark">   {/* 'light' | 'dark' | 'light-hc' | 'dark-hc' | 'system' */}
  <MobileProvider mobile={false} platform="browser">
    <ToasterProvider toaster={toaster}>
      <App />
    </ToasterProvider>
  </MobileProvider>
</ThemeProvider>
```

Full setup detail (SSR theme-flash prevention, i18n, custom themes via Themer, navigation shell): `references/gravity-ui-setup.md`.

## How to respond

- **In a chat interface (no filesystem):** produce one self-contained code artifact per component/page, with imports.
- **In Claude Code / with filesystem:** create real files; follow the project's existing structure. Don't paste code into chat when you can write files.
- **In an existing project:** read `package.json` and a couple of existing components before writing. Match the project's TypeScript/JS choice, file layout, import style, and styling approach.

For new projects, ask the user (one question, brief options) which build tool and which language (TS/JS) to use — do not assume Vite + TypeScript. Once they answer, scaffold and install Gravity UI on top.

## Component patterns

- **Composition over configuration.** Build complex UIs by composing uikit primitives, not by adding props to your own god-components.
- **Use the `<Icon>` wrapper** with `@gravity-ui/icons` data — do not inline raw SVGs when an icon exists in the icon set.
- **Use `Toaster` via `ToasterProvider`** — instantiate once at the app root, then call `toaster.add({...})` for notifications.
- **Dialogs/Modals/Sheets**: trust Gravity UI's focus trap and portal — do not add your own.
- **Forms**: Gravity UI provides controlled inputs (`TextInput`, `Select`, `Checkbox`, …) — wire them to whatever form library the project uses. If none is chosen, `useState` is fine for small forms; `@gravity-ui/dynamic-forms` for schema-driven forms.
- **Tables**: use `Table` from uikit for simple cases; `@gravity-ui/table` (TanStack-backed) for sortable/virtualized/grouped grids.
- **Layout**: prefer uikit's layout primitives (`Flex`, `Box`, `Container`, `Row`, `Col`) over hand-written flex/grid where possible.

## Styling

- **Tokens first.** Gravity UI exposes CSS custom properties scoped under `.g-root` (set by `ThemeProvider`). Use them: `var(--g-color-text-primary)`, `var(--g-color-base-background)`, `var(--g-spacing-3)`, etc.
- **SCSS mixins.** `@import '@gravity-ui/uikit/styles/mixins.scss'` for spacing, typography, and breakpoint mixins.
- **Themes.** Built-in: `light`, `dark`, `light-hc`, `dark-hc`. For brand customization, generate a token override at https://gravity-ui.com/themer and load it after the uikit styles.
- **Do not introduce Tailwind** unless the project already uses it. If it does, scope Tailwind to layout/spacing and keep colors/typography on Gravity tokens.

## Accessibility & polish

Gravity UI components are ARIA-correct out of the box (focus traps, keyboard nav, screen-reader labels). Your job:

- Pass meaningful `aria-label` to icon-only buttons.
- Use semantic landmarks (`<main>`, `<nav>`, `<header>`) around uikit components.
- Preserve heading order.
- Test the keyboard path: Tab, Shift+Tab, Enter, Space, Esc, arrow keys in menus.
- Verify both `light` and `dark` themes (and `*-hc` if the app declares high-contrast support).
- Respect `prefers-reduced-motion`.

UX principles, density, hierarchy, and visual polish: `references/ux-design.md`.
Final review gate before "done": `references/review-checklist.md`.

## References

- `references/gravity-ui-libraries.md` — full index of every `@gravity-ui/*` library, what it does, npm name, docs URL.
- `references/gravity-ui-uikit-components.md` — every component in `@gravity-ui/uikit` with one-line purpose and the URL to fetch its reference.
- `references/gravity-ui-setup.md` — installation, providers, theming, SSR, i18n, Toaster, Themer, MobileProvider details.
- `references/ux-design.md` — UX laws, hierarchy, spacing, density, motion. Design-system-agnostic.
- `references/review-checklist.md` — final review gate (a11y, types, performance, polish).
