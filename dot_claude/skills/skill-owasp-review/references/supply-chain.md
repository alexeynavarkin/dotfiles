# Supply Chain Security

## Attack Vectors

### Dependency confusion / typosquatting
Attacker publishes malicious package with name similar to legitimate package or matching internal package name on public registry.

**Detection:**
- Unusual package names in `package.json`, `requirements.txt`, `go.mod`
- Packages with very low download counts for seemingly common names
- Missing `.npmrc` / `pip.conf` scoping for private registries

**Mitigation:**
- Use scoped packages (`@myorg/package-name`)
- Configure registry scoping for private packages
- Use `npm config set registry` per-scope

### Maintainer account compromise
Legitimate packages hijacked via compromised maintainer credentials.

**Mitigation:**
- Pin dependencies by exact version + integrity hash
- Use lockfiles and verify integrity
- Monitor for unexpected version bumps

### CI/CD pipeline compromise
Malicious code injected via compromised build tools, GitHub Actions, or CI configurations.

**Detection:**
- GitHub Actions pinned by mutable tag: `uses: action@v1` (vulnerable)
- `npm install` instead of `npm ci` in CI (ignores lockfile)
- Missing `--frozen-lockfile` in yarn/pnpm CI builds
- Build scripts that download external resources at build time

---

## Lockfile Integrity

### What to check

**npm (package-lock.json):**
- Must exist and be committed
- Integrity hashes should be SHA-512: `"integrity": "sha512-..."`
- Flag SHA-1 hashes: `"integrity": "sha1-..."` (collision-vulnerable)
- CI must use `npm ci` (respects lockfile), NOT `npm install`

**yarn (yarn.lock):**
- Must exist and be committed
- CI must use `yarn install --frozen-lockfile`

**Go (go.sum):**
- Must exist and be committed
- Contains SHA-256 hashes for all dependencies
- `GONOSUMCHECK` / `GONOSUMDB` should not be set in production

**Python (Pipfile.lock / requirements.txt):**
- Use `pip install --require-hashes -r requirements.txt`
- Pin all transitive dependencies

**Rust (Cargo.lock):**
- Must be committed for applications (not libraries)
- `cargo install --locked` in CI

---

## GitHub Actions Security

### Pin by SHA, not tag

```yaml
# VULNERABLE — mutable tag, can be changed by attacker
- uses: actions/checkout@v4
- uses: some-org/some-action@main

# SECURE — pinned by commit SHA
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

### Restrict workflow permissions

```yaml
# Restrict default permissions
permissions:
  contents: read

jobs:
  build:
    permissions:
      contents: read
      packages: write  # Only what's needed
```

### What to flag
- `uses:` with tag or branch reference (not SHA)
- `permissions: write-all` or missing permissions block
- Workflows triggered by `pull_request_target` with checkout of PR head (code injection)
- Secrets passed to third-party actions
- `${{ github.event.pull_request.title }}` in `run:` (injection via PR title)

---

## Dependency Audit Commands

```bash
# Node.js
npm audit
npm audit --audit-level=high

# Python
pip-audit
safety check

# Go
govulncheck ./...

# Rust
cargo audit

# Java/Maven
mvn org.owasp:dependency-check-maven:check

# Container images
trivy image myapp:latest
grype myapp:latest
```

---

## CI/CD Security Checklist

1. **Lockfile committed and enforced** — `npm ci` / `--frozen-lockfile`
2. **Dependencies pinned by hash** — not just version
3. **Automated vulnerability scanning** — in CI pipeline
4. **GitHub Actions pinned by SHA** — not tag
5. **Minimal CI permissions** — principle of least privilege
6. **No secrets in build logs** — mask sensitive values
7. **Signed commits/artifacts** — integrity verification
8. **Registry scoping** — private packages resolve to private registry
9. **Dependency update automation** — Dependabot/Renovate with auto-merge for patch updates
10. **SBOM generation** — Software Bill of Materials for audit trail

---

## Detection Patterns

```
# Lockfile issues
sha1-                           # Weak hash in lockfile
npm install(?!.*--ci)           # Should be npm ci in CI
yarn install(?!.*frozen)        # Missing --frozen-lockfile

# GitHub Actions
uses:.*@v[0-9]                  # Mutable tag reference
uses:.*@main                    # Branch reference
uses:.*@latest                  # Latest tag
pull_request_target             # Potentially dangerous trigger
permissions:\s*write-all        # Overly broad permissions

# Build-time downloads
curl.*\|.*sh                    # Pipe-to-shell pattern
wget.*&&.*chmod.*\+x            # Download and execute
```
