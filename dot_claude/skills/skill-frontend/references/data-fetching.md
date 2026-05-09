# Data Fetching — TanStack Query v5

Default for anything that comes from the server. You get caching, deduplication, background refetch, loading/error states, and optimistic updates for free.

## Setup

```tsx
// app/providers.tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,           // 30s — tune per app
      refetchOnWindowFocus: true,   // nice for dashboards, annoying for forms
      retry: 1,
    },
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

## Queries

Colocate query hooks with the feature that uses them. Name them `use<Thing>`.

```tsx
// features/users/api.ts
import { useQuery } from "@tanstack/react-query";

export const userKeys = {
  all: ["users"] as const,
  lists: () => [...userKeys.all, "list"] as const,
  list: (filters: UserFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, "detail"] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
};

export function useUser(id: string) {
  return useQuery({
    queryKey: userKeys.detail(id),
    queryFn: () => api.getUser(id),
    enabled: !!id,
  });
}
```

The keys factory pattern (above) keeps invalidation consistent. `queryClient.invalidateQueries({ queryKey: userKeys.lists() })` invalidates all list queries regardless of filters.

## In a component

```tsx
function UserPage({ id }: { id: string }) {
  const { data, isPending, isError, error } = useUser(id);

  if (isPending) return <UserSkeleton />;
  if (isError) return <ErrorMessage error={error} />;

  return <UserDetails user={data} />;
}
```

In v5 it's `isPending` (not `isLoading`) for the initial load. `isLoading` is now only true on the very first fetch with no cached data.

## Mutations

```tsx
export function useUpdateUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (input: UpdateUserInput) => api.updateUser(input),
    onSuccess: (updated) => {
      queryClient.setQueryData(userKeys.detail(updated.id), updated);
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
    },
  });
}
```

Usage:

```tsx
const { mutate, isPending } = useUpdateUser();

<Button onClick={() => mutate({ id, name })} disabled={isPending}>
  {isPending ? "Saving…" : "Save"}
</Button>
```

## Optimistic updates

```tsx
useMutation({
  mutationFn: api.toggleFavorite,
  onMutate: async ({ id }) => {
    await queryClient.cancelQueries({ queryKey: itemKeys.detail(id) });
    const previous = queryClient.getQueryData<Item>(itemKeys.detail(id));
    queryClient.setQueryData<Item>(itemKeys.detail(id), (old) =>
      old ? { ...old, favorited: !old.favorited } : old,
    );
    return { previous };
  },
  onError: (_err, { id }, context) => {
    if (context?.previous) queryClient.setQueryData(itemKeys.detail(id), context.previous);
  },
  onSettled: (_data, _err, { id }) => {
    queryClient.invalidateQueries({ queryKey: itemKeys.detail(id) });
  },
});
```

## Infinite queries

```tsx
const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useInfiniteQuery({
  queryKey: postKeys.list(filters),
  queryFn: ({ pageParam }) => api.getPosts({ cursor: pageParam, filters }),
  initialPageParam: null as string | null,
  getNextPageParam: (last) => last.nextCursor,
});
```

## Prefetching on hover

Great for lists where the user is about to click into a detail page:

```tsx
<Link
  to={`/users/${user.id}`}
  onMouseEnter={() => {
    queryClient.prefetchQuery({
      queryKey: userKeys.detail(user.id),
      queryFn: () => api.getUser(user.id),
      staleTime: 10_000,
    });
  }}
>
  {user.name}
</Link>
```

## Error handling

Throw in `queryFn` — TanStack Query catches it. Your `fetch` wrapper should throw on non-2xx:

```ts
export async function apiFetch<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  if (!res.ok) throw new ApiError(res.status, await res.text());
  return res.json();
}
```

For global error handling (e.g., 401 → redirect to login), use `QueryCache`'s `onError`:

```ts
new QueryClient({
  queryCache: new QueryCache({
    onError: (error) => {
      if (error instanceof ApiError && error.status === 401) {
        redirectToLogin();
      }
    },
  }),
});
```

## Don't

- Don't fetch inside `useEffect` with `useState` for loading/error. That's the bug TanStack Query fixes.
- Don't put the whole response in Zustand. Let TanStack Query be your server-state cache.
- Don't forget `enabled: false` or `enabled: !!someValue` for queries that shouldn't run until preconditions are met.
- Don't pass unstable objects as query keys — `queryKey: ["foo", { filter }]` is fine because TanStack deep-compares, but `queryKey: ["foo", Date.now()]` will refetch forever.
