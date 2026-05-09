# Routing — React Router v7 (Declarative Mode)

React Router v7 merges the old `react-router-dom` (declarative) with Remix (framework). For SPAs built with Vite, **declarative mode** is the default — it's v6 with new features. If you need file-based routing and SSR, that's framework mode (closer to Next.js; see `nextjs-fallback.md` for when to just use Next).

## Basic setup

```tsx
// main.tsx
import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router";

import { Providers } from "./app/providers";
import { RootLayout } from "./app/root-layout";
import { Home } from "./routes/home";
import { Settings } from "./routes/settings";
import { NotFound } from "./routes/not-found";

createRoot(document.getElementById("root")!).render(
  <Providers>
    <BrowserRouter>
      <Routes>
        <Route element={<RootLayout />}>
          <Route index element={<Home />} />
          <Route path="settings/*" element={<Settings />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </Providers>,
);
```

## Nested routes & layouts

Parent routes render an `<Outlet />` where child routes go:

```tsx
// app/root-layout.tsx
import { Outlet } from "react-router";
import { Header } from "@/components/header";

export function RootLayout() {
  return (
    <div className="min-h-screen">
      <Header />
      <main className="container mx-auto p-6">
        <Outlet />
      </main>
    </div>
  );
}
```

## Code-splitting routes

Lazy-load everything except the landing page:

```tsx
import { lazy, Suspense } from "react";

const Settings = lazy(() => import("./routes/settings").then((m) => ({ default: m.Settings })));

<Route
  path="settings/*"
  element={
    <Suspense fallback={<PageSkeleton />}>
      <Settings />
    </Suspense>
  }
/>
```

## Links & navigation

```tsx
import { Link, NavLink, useNavigate } from "react-router";

// Regular link
<Link to="/settings">Settings</Link>

// Nav link with active styling
<NavLink
  to="/settings"
  className={({ isActive }) =>
    cn("rounded-md px-3 py-2", isActive && "bg-accent")
  }
>
  Settings
</NavLink>

// Programmatic navigation
const navigate = useNavigate();
navigate("/dashboard", { replace: true });
```

**Never use `<a href>` for internal navigation** — it triggers a full page reload. Use `<Link>`.

## Protected routes

Wrap a layout with an auth check:

```tsx
// app/require-auth.tsx
import { Navigate, Outlet, useLocation } from "react-router";

export function RequireAuth() {
  const { user, isLoading } = useAuth();
  const location = useLocation();

  if (isLoading) return <PageSkeleton />;
  if (!user) return <Navigate to="/login" state={{ from: location }} replace />;

  return <Outlet />;
}

// In the route tree:
<Route element={<RequireAuth />}>
  <Route path="dashboard" element={<Dashboard />} />
  <Route path="settings/*" element={<Settings />} />
</Route>
```

## URL params

```tsx
import { useParams } from "react-router";

<Route path="users/:userId" element={<UserPage />} />

function UserPage() {
  const { userId } = useParams<{ userId: string }>();
  if (!userId) return null; // shouldn't happen, but narrows the type
  return <UserDetails id={userId} />;
}
```

## Search params

```tsx
import { useSearchParams } from "react-router";

const [params, setParams] = useSearchParams();
const page = Number(params.get("page") ?? 1);

setParams((prev) => {
  prev.set("page", String(page + 1));
  return prev;
});
```

## Scroll restoration

```tsx
import { ScrollRestoration } from "react-router";

// In RootLayout, after <Outlet />:
<ScrollRestoration />
```

## Document titles

Use `react-helmet-async` or a simple hook:

```tsx
// hooks/use-document-title.ts
import { useEffect } from "react";

export function useDocumentTitle(title: string) {
  useEffect(() => {
    const previous = document.title;
    document.title = title;
    return () => { document.title = previous; };
  }, [title]);
}
```

## Don't

- Don't use `window.location.href = "/foo"` to navigate — breaks SPA behavior. Use `navigate()`.
- Don't fetch data in route components with `useEffect`. Use TanStack Query; let Suspense handle loading.
- Don't nest `<BrowserRouter>` — exactly one, at the top.
- Don't put auth checks in individual pages. Use a route-level guard (`<RequireAuth />`) once.
