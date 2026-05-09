# API Security — OWASP API Security Top 10 (2023)

## API1: Broken Object Level Authorization (BOLA)

Endpoints expose objects by ID without verifying the requesting user owns or may access them.

**Vulnerable:**
```javascript
app.get('/api/orders/:id', requireAuth, async (req, res) => {
  const order = await db.orders.findById(req.params.id);
  res.json(order);  // Any authenticated user sees any order
});
```

**Secure:**
```javascript
app.get('/api/orders/:id', requireAuth, async (req, res) => {
  const order = await db.orders.findById(req.params.id);
  if (!order) return res.status(404).json({ error: 'Not found' });
  if (order.userId !== req.user.id && req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden' });
  }
  res.json(order);
});
```

**Detection:** `findById(req.params` without subsequent ownership check; endpoints returning data keyed by user-supplied ID.

---

## API2: Broken Authentication

Weak token validation, missing rate limiting, insecure token storage.

**What to flag:**
- JWT without signature verification or with `alg: "none"` accepted
- API keys in query strings (logged in server/proxy logs)
- No rate limiting on auth endpoints
- Long-lived tokens without rotation
- Missing token revocation mechanism

---

## API3: Broken Object Property Level Authorization

Combines excessive data exposure and mass assignment.

### Excessive data exposure

```javascript
// VULNERABLE — returns password hash, internal fields
app.get('/api/users/:id', async (req, res) => {
  const user = await db.users.findById(req.params.id);
  res.json(user);  // Full DB object
});

// SECURE — explicit field selection
app.get('/api/users/:id', async (req, res) => {
  const user = await db.users.findById(req.params.id);
  res.json({
    id: user.id,
    name: user.name,
    email: user.email,
  });
});
```

### Mass assignment

```javascript
// VULNERABLE — user controls which fields get updated
app.put('/api/users/:id', async (req, res) => {
  await db.users.update(req.params.id, req.body);  // User sends { role: "admin" }
});

// SECURE — allowlist fields
app.put('/api/users/:id', async (req, res) => {
  const { name, email, avatar } = req.body;  // Only allowed fields
  await db.users.update(req.params.id, { name, email, avatar });
});
```

**Detection:** `Object.assign(model, req.body)`, `model.update(req.body)`, `{ ...req.body }` spread into DB operations; endpoints returning full DB objects without field filtering.

---

## API4: Unrestricted Resource Consumption

No rate, size, or pagination limits.

**What to flag:**
- Missing rate limiting middleware on any public endpoint
- No pagination cap (user requests `?limit=999999`)
- Unbounded file upload size
- Expensive operations without cost limits (regex, search, report generation)
- Missing request body size limit

**Secure pagination:**
```javascript
app.get('/api/items', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);  // Cap at 100
  const offset = Math.max(parseInt(req.query.offset) || 0, 0);
  const items = await db.items.find().skip(offset).limit(limit);
  res.json({ items, limit, offset });
});
```

---

## API5: Broken Function Level Authorization

Admin functions accessible to regular users.

**What to flag:**
- Admin routes without role-checking middleware
- Separate admin API with same authentication as user API
- Authorization based on client-supplied role/permissions
- Missing authorization on batch/bulk operation endpoints

---

## API6: Unrestricted Access to Sensitive Business Flows

Automated abuse of business logic.

**What to flag:**
- Purchase/checkout without CAPTCHA or fraud detection
- Coupon/promo code endpoints without usage limits
- Account creation without abuse prevention
- Scraping-sensitive endpoints without bot detection

---

## API7: Server-Side Request Forgery (SSRF)

API fetches user-controlled URLs.

**Vulnerable:**
```javascript
app.post('/api/preview', async (req, res) => {
  const response = await fetch(req.body.url);
  res.json({ content: await response.text() });
});
```

**Secure:**
```javascript
const ALLOWED_HOSTS = new Set(['api.example.com', 'cdn.example.com']);

app.post('/api/preview', async (req, res) => {
  const parsed = new URL(req.body.url);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    return res.status(400).json({ error: 'Invalid protocol' });
  }
  if (!ALLOWED_HOSTS.has(parsed.hostname)) {
    return res.status(400).json({ error: 'Host not allowed' });
  }
  // Also validate resolved IP is not private/internal
  const response = await fetch(req.body.url, {
    redirect: 'error',
    signal: AbortSignal.timeout(5000),
  });
  res.json({ content: await response.text() });
});
```

**Detection:** `fetch(req.`, `axios(req.`, `requests.get(user`, `http.Get(` with user-controlled arguments.

---

## API8: Security Misconfiguration

See `references/security-headers.md` for headers and CORS.

**Additional API-specific items:**
- Verbose error responses exposing stack traces, SQL errors, internal paths
- Debug endpoints enabled in production
- Default API documentation publicly accessible (Swagger UI with "Try it out")
- Missing request/response schema validation

---

## API9: Improper Inventory Management

**What to flag:**
- Old API versions still active (`/v1/` alongside `/v3/`)
- Undocumented endpoints
- Missing API gateway for centralized auth/rate-limiting
- Development/staging endpoints accessible from production

---

## API10: Unsafe Consumption of APIs

**What to flag:**
- Third-party API responses used without validation
- External webhooks processed without signature verification
- Trusting HTTP redirects from external services
- External data inserted into SQL/HTML without sanitization

---

## GraphQL-Specific Security

### Introspection in production

```javascript
// VULNERABLE — full schema exposed
const server = new ApolloServer({ typeDefs, resolvers });

// SECURE
const server = new ApolloServer({
  typeDefs,
  resolvers,
  introspection: process.env.NODE_ENV !== 'production',
});
```

### Query depth attacks

```javascript
// SECURE — limit query depth
const depthLimit = require('graphql-depth-limit');
const server = new ApolloServer({
  typeDefs,
  resolvers,
  validationRules: [depthLimit(7)],
});
```

### Query cost / complexity analysis

```javascript
// SECURE — limit query complexity
const { createComplexityLimitRule } = require('graphql-validation-complexity');
const server = new ApolloServer({
  validationRules: [createComplexityLimitRule(1000)],
});
```

### Batching/alias brute force

```graphql
# Attacker bypasses rate limiting via aliases
{
  a1: login(password: "pass1") { token }
  a2: login(password: "pass2") { token }
}
```

**Fix:** Rate limit by resolved operations, not HTTP requests. Limit operations per request.

### What to flag in GraphQL
- Introspection enabled in production
- No query depth limit
- No query complexity/cost analysis
- Batch endpoints without per-operation rate limiting
- Resolvers without authorization checks
- No persisted queries (allows arbitrary query execution)
