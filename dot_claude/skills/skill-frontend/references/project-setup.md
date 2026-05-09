# Project Setup — From Zero to Working

Exact commands to scaffold a new project with the full stack. Copy-paste, don't improvise.

## 1. Create the Vite project

```bash
npm create vite@latest my-app -- --template react-ts
cd my-app
npm install
```

## 2. Install Tailwind CSS v4

```bash
npm install tailwindcss @tailwindcss/vite
```

Update `vite.config.ts`:

```ts
import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
```

Replace `src/index.css` with:

```css
@import "tailwindcss";

@theme {
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
}
```

## 3. Configure TypeScript paths

In `tsconfig.json`:

```json
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ],
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["./src/*"] }
  }
}
```

In `tsconfig.app.json`, enable strict options:

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "baseUrl": ".",
    "paths": { "@/*": ["./src/*"] }
  }
}
```

```bash
npm install -D @types/node
```

## 4. Set up shadcn/ui

```bash
npx shadcn@latest init
```

Pick: **new-york** style, **neutral** base color (or whatever fits), CSS variables **yes**.

Add your first components:

```bash
npx shadcn@latest add button input label form dialog dropdown-menu
```

## 5. Install the rest of the stack

```bash
# Routing
npm install react-router

# Data fetching
npm install @tanstack/react-query @tanstack/react-query-devtools

# Client state
npm install zustand

# Forms
npm install react-hook-form zod @hookform/resolvers

# Utilities
npm install clsx tailwind-merge class-variance-authority
```

## 6. Testing setup

```bash
npm install -D vitest @vitejs/plugin-react jsdom
npm install -D @testing-library/react @testing-library/user-event @testing-library/jest-dom
npm install -D msw

npm install -D @playwright/test
npx playwright install
```

Add to `package.json` scripts:

```json
{
  "scripts": {
    "test": "vitest",
    "test:ui": "vitest --ui",
    "test:e2e": "playwright test",
    "typecheck": "tsc --noEmit",
    "lint": "eslint ."
  }
}
```

## 7. The `cn()` helper

`src/lib/utils.ts`:

```ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

## 8. Providers shell

`src/app/providers.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { BrowserRouter } from "react-router";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1 },
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>{children}</BrowserRouter>
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

`src/main.tsx`:

```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Providers } from "./app/providers";
import { App } from "./app";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Providers>
      <App />
    </Providers>
  </StrictMode>,
);
```

## 9. Verify it all works

```bash
npm run dev          # starts on http://localhost:5173
npm run typecheck    # should pass
npm test             # should pass (no tests yet = 0 failures)
npm run build        # should produce dist/
```

If any of those fail, fix before writing feature code. A broken toolchain compounds.
