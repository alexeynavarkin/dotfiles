# Testing

Two layers:
- **Component tests** with Vitest + Testing Library — fast, run in jsdom.
- **E2E tests** with Playwright — slower, real browser, cover critical flows.

Skip "shallow rendering" and snapshot-everything approaches. Test behavior a user would notice.

## Vitest setup

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
```

```ts
// src/test/setup.ts
import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

afterEach(() => cleanup());
```

## A good component test

```tsx
// user-card.test.tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { UserCard } from "./user-card";

describe("UserCard", () => {
  it("calls onSelect with the email when clicked", async () => {
    const onSelect = vi.fn();
    const user = userEvent.setup();

    render(<UserCard name="Ada" email="ada@example.com" onSelect={onSelect} />);

    await user.click(screen.getByRole("button", { name: /ada/i }));

    expect(onSelect).toHaveBeenCalledWith("ada@example.com");
  });

  it("shows the email under the name", () => {
    render(<UserCard name="Ada" email="ada@example.com" />);
    expect(screen.getByText("ada@example.com")).toBeInTheDocument();
  });
});
```

## Query priority

Prefer queries that reflect how users interact:

1. `getByRole("button", { name: /save/i })` — best
2. `getByLabelText(/email/i)` — for form fields
3. `getByText(/welcome/i)` — for visible text
4. `getByPlaceholderText`, `getByDisplayValue` — less preferred
5. `getByTestId` — last resort, when no accessible query works

If you can't find something by role or label, that's often a sign the component isn't accessible. Fix the component first.

## Testing async UI

```tsx
import { render, screen } from "@testing-library/react";

it("shows the list after loading", async () => {
  render(<UserList />);
  expect(screen.getByText(/loading/i)).toBeInTheDocument();

  // Wait for the loading state to go away and real content to appear
  expect(await screen.findByText("Ada Lovelace")).toBeInTheDocument();
});
```

Use `findBy*` (async) for elements that appear later. Don't pepper tests with arbitrary `setTimeout`s.

## Mocking network calls

Use **MSW (Mock Service Worker)** — mocks the network layer, not `fetch` directly. Same handlers work in tests and in the browser.

```ts
// src/test/handlers.ts
import { http, HttpResponse } from "msw";

export const handlers = [
  http.get("/api/users/:id", ({ params }) => {
    return HttpResponse.json({ id: params.id, name: "Ada", email: "ada@example.com" });
  }),
];
```

```ts
// src/test/setup.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";
import { afterAll, afterEach, beforeAll } from "vitest";

export const server = setupServer(...handlers);

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

Override per test:

```tsx
import { server } from "@/test/setup";
import { http, HttpResponse } from "msw";

it("shows an error when the API fails", async () => {
  server.use(
    http.get("/api/users/:id", () => HttpResponse.json({ message: "Server error" }, { status: 500 })),
  );

  render(<UserPage id="1" />);
  expect(await screen.findByText(/server error/i)).toBeInTheDocument();
});
```

## Testing with providers

Wrap in the providers the component needs. Make a helper:

```tsx
// src/test/render.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderOptions } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import type { ReactElement, ReactNode } from "react";

export function renderWithProviders(
  ui: ReactElement,
  { route = "/", ...options }: RenderOptions & { route?: string } = {},
) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } }, // fail fast in tests
  });

  const Wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>
    </QueryClientProvider>
  );

  return render(ui, { wrapper: Wrapper, ...options });
}
```

## Testing forms

```tsx
it("shows a validation error for an invalid email", async () => {
  const user = userEvent.setup();
  render(<SignupForm onSubmit={vi.fn()} />);

  await user.type(screen.getByLabelText(/email/i), "not-an-email");
  await user.click(screen.getByRole("button", { name: /sign up/i }));

  expect(await screen.findByText(/valid email/i)).toBeInTheDocument();
});
```

## Playwright — smoke tests for critical flows

Don't duplicate unit tests. Use Playwright for flows that span multiple pages and real interactions (login, checkout, create-edit-delete).

```ts
// e2e/login.spec.ts
import { test, expect } from "@playwright/test";

test("user can sign in and see their dashboard", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill("ada@example.com");
  await page.getByLabel("Password").fill("correct-horse-battery");
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page).toHaveURL("/dashboard");
  await expect(page.getByRole("heading", { name: /welcome, ada/i })).toBeVisible();
});
```

## Don't

- Don't test implementation details (`expect(useState).toHaveBeenCalled`). Test what the user sees.
- Don't use snapshot tests for everything. They rot and nobody reads the diffs.
- Don't mock `fetch` with `vi.fn()` ad-hoc — use MSW. Keeps tests close to reality.
- Don't `await waitFor(() => {})` with empty bodies — that's just waiting for nothing. Use `findBy*`.
- Don't test every path in every component. Test the public API (props → rendered output + callbacks).
