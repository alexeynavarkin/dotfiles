# Security Headers & Browser Security

## Required Security Headers

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Content-Security-Policy: default-src 'self'; script-src 'nonce-{random}' 'strict-dynamic'; style-src 'self' 'nonce-{random}'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
```

### Express.js implementation

```javascript
const helmet = require('helmet');
app.use(helmet());
app.disable('x-powered-by');

// Or manual configuration
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'nonce-${nonce}'", "'strict-dynamic'"],
      styleSrc: ["'self'", "'nonce-${nonce}'"],
      imgSrc: ["'self'", "data:"],
      objectSrc: ["'none'"],
      baseUri: ["'self'"],
      formAction: ["'self'"],
      frameAncestors: ["'none'"],
    },
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
  frameguard: { action: 'deny' },
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
}));
```

---

## Content Security Policy (CSP)

### Strict CSP with nonces (recommended)

```javascript
const crypto = require('crypto');

app.use((req, res, next) => {
  res.locals.nonce = crypto.randomBytes(16).toString('base64');
  res.setHeader('Content-Security-Policy',
    `default-src 'self'; ` +
    `script-src 'nonce-${res.locals.nonce}' 'strict-dynamic'; ` +
    `style-src 'self' 'nonce-${res.locals.nonce}'; ` +
    `object-src 'none'; ` +
    `base-uri 'self'`
  );
  next();
});

// In HTML templates
`<script nonce="${res.locals.nonce}">/* app code */</script>`
```

### Dangerous CSP directives to flag

| Directive | Why dangerous |
|-----------|---------------|
| `'unsafe-inline'` in `script-src` | Defeats XSS protection entirely |
| `'unsafe-eval'` in `script-src` | Allows `eval()`, `Function()`, `setTimeout(string)` |
| `*` in any directive | Allows loading from any origin |
| `data:` in `script-src` | Allows script injection via data URIs |
| Missing `default-src` | Falls back to allowing everything |
| `https:` in `script-src` | Any HTTPS origin can serve scripts |
| `'unsafe-hashes'` | Allows specific inline event handlers |

### CSP reporting

```
Content-Security-Policy: ...; report-uri /csp-report; report-to csp-endpoint
Content-Security-Policy-Report-Only: ...  # Monitor without blocking
```

---

## CORS Configuration

### Vulnerable patterns

```javascript
// DANGEROUS — wildcard with credentials (browsers block, but indicates confusion)
app.use(cors({
  origin: '*',
  credentials: true,
}));

// DANGEROUS — reflecting any origin
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin);
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  next();
});

// DANGEROUS — regex too broad
app.use(cors({
  origin: /example\.com/,  // Matches evil-example.com too
}));
```

### Secure CORS

```javascript
const ALLOWED_ORIGINS = new Set([
  'https://app.example.com',
  'https://admin.example.com',
]);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || ALLOWED_ORIGINS.has(origin)) {
      callback(null, true);
    } else {
      callback(new Error('CORS not allowed'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  maxAge: 86400,
}));
```

### What to flag
- `Access-Control-Allow-Origin: *` with credentials
- Origin reflected from request without validation
- Regex origin matching that's too broad
- `Access-Control-Allow-Headers: *`
- `Access-Control-Allow-Methods: *`
- Preflight cache (`maxAge`) set too long without good reason

---

## Cookie Security

### Required flags

```
Set-Cookie: sid=value; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=28800
```

| Flag | Purpose | When Required |
|------|---------|---------------|
| `Secure` | HTTPS only | Always in production |
| `HttpOnly` | No `document.cookie` access | Always for session/auth cookies |
| `SameSite=Strict` | Never sent cross-site | Auth-critical cookies |
| `SameSite=Lax` | Sent on top-level navigations | Default for most cookies |
| `__Host-` prefix | Enforces Secure + Path=/ + no Domain | Highest security sessions |
| `__Secure-` prefix | Enforces Secure | When Domain attribute needed |
| `Max-Age` or `Expires` | Session lifetime | Always (don't rely on browser close) |

### What to flag
- Cookies without `Secure` flag
- Session/auth cookies without `HttpOnly`
- Missing `SameSite` attribute (defaults to `Lax` in modern browsers, but be explicit)
- `SameSite=None` without `Secure` (rejected by browsers)
- Cookie `Domain` set too broadly (`.example.com` includes all subdomains)

---

## HSTS (HTTP Strict Transport Security)

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

### What to flag
- Missing HSTS header entirely
- `max-age` less than 31536000 (1 year)
- Missing `includeSubDomains` (subdomains still allow HTTP)
- Application serving on HTTP without redirect to HTTPS

---

## Additional Browser Security

### Subresource Integrity (SRI)

```html
<!-- SECURE — verify CDN script integrity -->
<script src="https://cdn.example.com/lib.js"
        integrity="sha384-abc123..."
        crossorigin="anonymous"></script>
```

Flag CDN resources without `integrity` attribute.

### X-Content-Type-Options

```
X-Content-Type-Options: nosniff
```

Prevents MIME-type sniffing. Always include.

### Permissions-Policy

```
Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()
```

Restrict browser features the application doesn't need.

---

## Detection Patterns

```
# Missing headers
helmet(?!\(\))                       # helmet imported but not used
X-Powered-By                        # Should be disabled

# Dangerous CORS
Access-Control-Allow-Origin.*\*     # Wildcard origin
origin.*req\.headers\.origin        # Reflected origin
credentials.*true.*origin.*\*       # Credentials + wildcard

# CSP issues
unsafe-inline|unsafe-eval           # Weakens CSP
Content-Security-Policy.*\*         # Wildcard in CSP

# Cookie issues
Set-Cookie(?!.*Secure)              # Missing Secure
Set-Cookie(?!.*HttpOnly)            # Missing HttpOnly
SameSite.*None(?!.*Secure)          # SameSite=None without Secure
```
