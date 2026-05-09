# OWASP Top 10 (2021 & 2025) with CWE Cross-Reference

## A01:2021 / A01:2025 — Broken Access Control

The #1 vulnerability category in both 2021 and 2025.

**CWEs:** CWE-862 (Missing Authorization), CWE-863 (Incorrect Authorization), CWE-284 (Improper Access Control), CWE-639 (Authorization Bypass via User-Controlled Key), CWE-352 (CSRF), CWE-22 (Path Traversal)

**What to look for:**
- Route handlers missing auth middleware
- Endpoints accepting user IDs as parameters without ownership checks (IDOR)
- Missing CSRF tokens on state-changing operations
- Path traversal in file operations (`../` not sanitized)
- Horizontal privilege escalation (user A accessing user B's data)
- Vertical privilege escalation (regular user accessing admin functions)
- Direct object references without authorization verification

**Key rule:** Every endpoint that touches user-specific data must verify the requesting user owns or is authorized to access that data. Default deny.

---

## A02:2021 / A02:2025 — Cryptographic Failures

Moved to #2 in 2025 (Security Misconfiguration).

**CWEs:** CWE-327 (Broken Crypto Algorithm), CWE-328 (Weak Hash), CWE-330 (Insufficient Randomness), CWE-312 (Cleartext Storage), CWE-319 (Cleartext Transmission)

**What to look for:**
- MD5, SHA-1 for password hashing or integrity
- Hardcoded encryption keys, API keys, passwords
- Data transmitted over HTTP (not HTTPS)
- Sensitive data stored unencrypted at rest
- Weak/deprecated TLS versions (< 1.2)
- Non-CSPRNG for security-critical random values

See `references/cryptography.md` for approved algorithms and detailed patterns.

---

## A03:2021 / A05:2025 — Injection

Dropped to #5 in 2025 but remains critically dangerous.

**CWEs:** CWE-79 (XSS), CWE-89 (SQLi), CWE-78 (OS Command Injection), CWE-94 (Code Injection), CWE-77 (Command Injection)

**What to look for:**
- String concatenation/interpolation in SQL queries
- User input passed to `os.system()`, `exec()`, `eval()`
- Unescaped user input rendered in HTML (`innerHTML`, `dangerouslySetInnerHTML`)
- Template injection in server-side rendering
- LDAP injection in directory queries

See `references/injection-patterns.md` for comprehensive patterns per injection type.

---

## A04:2021 — Insecure Design

Architectural flaws that code-level fixes cannot address.

**What to look for:**
- No rate limiting on password reset / OTP verification
- Client-side price/discount calculations
- File uploads without type/size/content validation
- Multi-step workflows without server-side state validation
- Missing re-authentication for sensitive operations (password change, payment)
- Business logic that assumes sequential execution

---

## A05:2021 / A02:2025 — Security Misconfiguration

Moved to #2 in 2025.

**CWEs:** CWE-16 (Configuration), CWE-1188 (Insecure Default)

**What to look for:**
- Debug mode enabled in production (`DEBUG=True`, `debug: true`)
- Default credentials unchanged
- Stack traces in error responses
- Missing security headers (HSTS, CSP, X-Content-Type-Options)
- Overly permissive CORS (`Access-Control-Allow-Origin: *`)
- Unnecessary features/services enabled
- Missing `helmet()` or equivalent middleware

---

## A06:2021 — Vulnerable and Outdated Components

Expanded to A03:2025 — Software Supply Chain Failures.

**What to look for:**
- Known CVEs in dependencies (`npm audit`, `pip-audit`, `govulncheck`)
- Unpinned dependency versions
- Missing lockfile or lockfile with SHA-1 integrity
- GitHub Actions pinned by mutable tag instead of SHA

See `references/supply-chain.md` for full supply chain review.

---

## A07:2021 — Identification and Authentication Failures

**CWEs:** CWE-306 (Missing Auth for Critical Function), CWE-287 (Improper Authentication), CWE-798 (Hardcoded Credentials)

**What to look for:**
- Weak password hashing (MD5, SHA-1, unsalted)
- Missing session regeneration after login
- No account lockout or rate limiting on login
- Permitting weak passwords
- Session IDs in URLs
- Missing MFA for sensitive operations
- Credential stuffing vulnerability (no detection/prevention)

See `references/auth-session-security.md` for secure patterns.

---

## A08:2021 — Software and Data Integrity Failures

**CWEs:** CWE-502 (Deserialization of Untrusted Data), CWE-829 (Untrusted Functionality)

**What to look for:**
- `pickle.loads()`, `yaml.load()`, `ObjectInputStream.readObject()`
- Missing integrity verification on updates/plugins
- CI/CD pipelines without signed artifacts
- Unsigned or unverified data driving application behavior

---

## A09:2021 — Security Logging and Monitoring Failures

**What to look for:**
- Login/logout events not logged
- Authorization failures not logged
- Sensitive operations without audit trail
- Logs containing sensitive data (passwords, tokens, PII)
- Missing alerting on suspicious patterns
- `catch` blocks that silently swallow errors

---

## A10:2021 — Server-Side Request Forgery (SSRF)

Consolidated into A01 in 2025.

**CWEs:** CWE-918 (SSRF)

**What to look for:**
- `fetch()`, `axios()`, `http.get()`, `requests.get()` with user-controlled URLs
- No URL allowlisting
- No DNS rebinding protection
- Following redirects on user-supplied URLs
- Internal metadata endpoints accessible (cloud provider metadata at 169.254.169.254)

---

## 2025 New Categories

### A03:2025 — Software Supply Chain Failures
Expanded from A06:2021. Covers integrity of acquisition, build, and distribution processes — not just known CVEs in dependencies.

### A10:2025 — Mishandling of Exceptional Conditions
Failures to prevent, detect, and respond to unusual situations: uncaught exceptions, improper null handling, resource exhaustion, and undefined behavior leading to crashes or security bypasses.

---

## CWE Top 25 (2025) Quick Reference

| Rank | CWE | Name | OWASP Category |
|------|-----|------|----------------|
| 1 | CWE-79 | Cross-site Scripting (XSS) | A03 Injection |
| 2 | CWE-89 | SQL Injection | A03 Injection |
| 3 | CWE-352 | CSRF | A01 Broken Access Control |
| 4 | CWE-862 | Missing Authorization | A01 Broken Access Control |
| 5 | CWE-787 | Out-of-bounds Write | Memory Safety |
| 6 | CWE-22 | Path Traversal | A01 Broken Access Control |
| 7 | CWE-416 | Use After Free | Memory Safety |
| 8 | CWE-125 | Out-of-bounds Read | Memory Safety |
| 9 | CWE-78 | OS Command Injection | A03 Injection |
| 10 | CWE-94 | Code Injection | A03 Injection |
| 11 | CWE-120 | Buffer Overflow | Memory Safety |
| 12 | CWE-434 | Unrestricted File Upload | A04 Insecure Design |
| 13 | CWE-476 | NULL Pointer Dereference | Availability |
| 14 | CWE-121 | Stack-based Buffer Overflow | Memory Safety |
| 15 | CWE-502 | Deserialization of Untrusted Data | A08 Integrity |
| 16 | CWE-122 | Heap-based Buffer Overflow | Memory Safety |
| 17 | CWE-863 | Incorrect Authorization | A01 Broken Access Control |
| 18 | CWE-20 | Improper Input Validation | A03 Injection |
| 19 | CWE-284 | Improper Access Control | A01 Broken Access Control |
| 20 | CWE-200 | Sensitive Info Exposure | A02 Crypto Failures |
| 21 | CWE-306 | Missing Authentication | A07 Auth Failures |
| 22 | CWE-918 | SSRF | A01 Broken Access Control |
| 23 | CWE-77 | Command Injection | A03 Injection |
| 24 | CWE-639 | Authz Bypass via User Key | A01 Broken Access Control |
| 25 | CWE-770 | Resource Allocation Without Limits | A04 Insecure Design |

## OWASP ASVS Verification Levels

| Level | Target | Scope |
|-------|--------|-------|
| L1 — Opportunistic | All apps (baseline) | Top 10 coverage, penetration-testable |
| L2 — Standard | Apps with sensitive data | Automated + manual testing, design review |
| L3 — Advanced | High-value targets (financial, health, gov) | L1+L2 + defense-in-depth, anti-tampering |
