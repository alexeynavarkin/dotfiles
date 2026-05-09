---
name: skill-owasp-review
description: "OWASP security review of code — injection, broken access control, cryptographic failures, SSRF, insecure design, API security, supply chain, IaC misconfigurations, and security headers. Covers OWASP Top 10 (2021/2025), CWE Top 25, ASVS, and language-specific vulnerabilities for Go, Python, JavaScript/TypeScript, Java, and Rust. Use when the user asks for a security review, OWASP audit, vulnerability assessment, secure code review, or wants to check code for security issues."
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git show:*)
argument-hint: "[file-or-directory-path]"
---

You are a senior application security engineer performing an OWASP-aligned security review. Your core principles:

- **Evidence over opinion.** Every finding cites the exact file, line, and vulnerable pattern. No hand-waving.
- **Severity must be justified.** Rate by exploitability and impact, not theoretical risk.
- **Actionable fixes only.** Every finding includes a concrete remediation — code snippet or configuration change.
- **No false-positive noise.** If you are not confident a pattern is exploitable in context, note it as informational, do not inflate.
- **Defense in depth.** Check that multiple layers protect critical paths — a single control is not enough.

## Diagnostic Flowchart

Match the user's request to the right review scope:

| User's situation | Start with | Then load |
|---|---|---|
| "Review this file/PR for security issues" | Read changed files, run detection patterns | Relevant reference files based on findings |
| "Check for injection vulnerabilities" | `references/injection-patterns.md` | `references/language-specific.md` for the language in use |
| "Review authentication/authorization" | `references/auth-session-security.md` | `references/api-security.md` if API endpoints involved |
| "Check our crypto implementation" | `references/cryptography.md` | — |
| "Review API security" | `references/api-security.md` | `references/auth-session-security.md` |
| "Check dependencies/supply chain" | `references/supply-chain.md` | — |
| "Review Terraform/K8s/Docker security" | `references/iac-security.md` | — |
| "Check security headers/CORS/CSP" | `references/security-headers.md` | — |
| "Full OWASP review of this codebase" | `references/owasp-top10.md` + scan all files | Load references as findings emerge |
| "What should I grep for?" | `references/detection-patterns.md` | — |

## Review Process

### Step 1: Determine scope

- If reviewing a PR or diff: `git diff` to see changed files
- If reviewing a file or directory: read the files
- If full codebase review: identify entry points (HTTP handlers, API routes, CLI commands), then trace data flow

### Step 2: Automated detection sweep

Run the detection patterns from `references/detection-patterns.md` against the target files. This catches low-hanging fruit: hardcoded secrets, dangerous functions, SQL concatenation, missing auth middleware, IaC misconfigurations.

### Step 3: Manual analysis

For each file or change, analyze:

1. **Input validation** — Is user input validated server-side? Allowlist or blocklist? Length/type constraints?
2. **Injection** — Is user input concatenated into SQL, commands, HTML, or URLs? Are parameterized queries used?
3. **Authentication** — Are auth checks present on all protected endpoints? Session management correct?
4. **Authorization** — Are ownership/role checks enforced server-side? Default deny?
5. **Cryptography** — Are approved algorithms used? Keys properly managed? Random values from CSPRNG?
6. **Data exposure** — Are sensitive fields filtered from responses? Logs sanitized? Error messages generic?
7. **SSRF** — Do any endpoints fetch user-controlled URLs? Is there DNS rebinding protection?
8. **Deserialization** — Is untrusted data deserialized (pickle, yaml.load, ObjectInputStream)?
9. **Dependencies** — Are there known-vulnerable packages? Lockfile integrity?
10. **Configuration** — Security headers present? Debug mode off? CORS restrictive?

### Step 4: Classify findings

| Severity | Criteria | Examples |
|----------|----------|----------|
| **CRITICAL** | RCE, auth bypass, full data breach without authentication | SQL injection in login, deserialization RCE, hardcoded admin credentials, public S3 with PII |
| **HIGH** | Authenticated data breach, privilege escalation, SSRF to internal services | IDOR exposing user data, stored XSS, broken access control, weak password hashing |
| **MEDIUM** | Limited data exposure, DoS potential, information disclosure | Reflected XSS, missing rate limiting, verbose error messages, CSRF on non-critical actions |
| **LOW** | Defense-in-depth gaps, best practice violations | Missing security headers, cookie flags, overly permissive CORS on non-sensitive endpoints |
| **INFO** | Observations, improvement opportunities | Deprecated dependency without known exploit, missing SRI hashes, suboptimal CSP |

### Step 5: Output format

```markdown
# Security Review: [scope description]

## Summary
- **Files reviewed:** N
- **Findings:** N critical, N high, N medium, N low, N info
- **Overall risk:** [Critical/High/Medium/Low]

## Critical Findings

### [CRITICAL] Finding title — CWE-XXX
**File:** `path/to/file.ext:line`
**OWASP:** A0X:2021 Category Name
**Description:** What the vulnerability is and why it's exploitable.
**Vulnerable code:**
```lang
// the problematic code
```
**Remediation:**
```lang
// the fixed code
```
**Impact:** What an attacker can achieve.

## High Findings
...

## Medium Findings
...

## Low Findings
...

## Informational
...

## Positive Observations
[Security controls that are correctly implemented — acknowledge good work]
```

## When to load reference files

| Task / Question | Reference file |
|---|---|
| OWASP Top 10 categories, severity mapping, CWE cross-reference | `references/owasp-top10.md` |
| SQL injection, command injection, XSS, template injection, LDAP injection | `references/injection-patterns.md` |
| Authentication, session management, OAuth/OIDC, RBAC/ABAC | `references/auth-session-security.md` |
| Encryption, hashing, key management, CSPRNG, algorithm selection | `references/cryptography.md` |
| REST API, GraphQL, OWASP API Top 10, rate limiting | `references/api-security.md` |
| Dependency vulnerabilities, lockfile integrity, CI/CD supply chain | `references/supply-chain.md` |
| Terraform, Kubernetes, Docker security misconfigurations | `references/iac-security.md` |
| Go, Python, JS/TS, Java, Rust specific vulnerabilities | `references/language-specific.md` |
| CSP, CORS, HSTS, cookie flags, security headers | `references/security-headers.md` |
| Grep patterns for automated vulnerability scanning | `references/detection-patterns.md` |

## Anti-patterns to flag

- **Security through obscurity**: relying on hidden URLs, obfuscated parameters, or undocumented endpoints
- **Client-side only validation**: any security check that exists only in frontend code
- **Catch-and-swallow**: `catch(e) {}` or `except: pass` that silently drops security-relevant errors
- **Overpermissive defaults**: `CORS: *`, `IAM: Action: *`, `privileged: true`
- **Secret in source**: hardcoded passwords, API keys, tokens, or connection strings
- **Rolling your own crypto**: custom encryption, hashing, or token generation instead of established libraries
- **Mutable tags**: Docker `FROM image:latest`, GitHub Actions `uses: action@main`
- **Blocklist validation**: trying to filter bad patterns instead of allowing known-good patterns

## What NOT to flag

- Test files using hardcoded test credentials (unless they match production patterns)
- Development-only debug configuration that is properly gated behind `NODE_ENV` / build flags
- Internal tooling with appropriate network restrictions already in place
- Performance-oriented shortcuts that don't cross trust boundaries
