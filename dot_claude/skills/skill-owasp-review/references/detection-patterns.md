# Automated Detection Patterns

Quick-reference grep/search patterns for security review. Use these for the initial automated sweep before manual analysis.

## Injection

```
# SQL injection — string interpolation in queries
fmt\.Sprintf.*SELECT|fmt\.Sprintf.*INSERT|fmt\.Sprintf.*UPDATE|fmt\.Sprintf.*DELETE
f"SELECT|f"INSERT|f"UPDATE|f"DELETE
"SELECT.*\+|"INSERT.*\+|"UPDATE.*\+|"DELETE.*\+
\.query\(.*\+|\.execute\(.*\+|\.exec\(.*\+
\.query\(.*\$\{|\.execute\(.*\$\{
cursor\.execute\(f"|cursor\.execute\(.*%

# Command injection
os\.system\(|os\.popen\(
subprocess.*shell\s*=\s*True
child_process\.exec\(.*\+|child_process\.exec\(.*\$\{
exec\.Command\(.*\+|exec\.Command.*Sprintf
Runtime\.getRuntime\(\)\.exec

# Code execution
eval\(|exec\(|compile\(
new Function\(
setTimeout\(\s*["']|setInterval\(\s*["']
__import__\(

# XSS
innerHTML\s*=|outerHTML\s*=
dangerouslySetInnerHTML
document\.write\(
\.html\((?!.*sanitize|.*DOMPurify|.*escape)
v-html\s*=
\{\{.*\|.*safe\s*\}\}

# Template injection
Template\(.*request|Template\(.*req\.|Template\(.*user
render_template_string\(.*request|render_template_string\(.*f"
```

## Authentication & Authorization

```
# Missing auth middleware (look for route handlers without auth)
app\.(get|post|put|delete|patch)\(.*(?!requireAuth|authenticate|isAuth|protect|guard|middleware)

# IDOR — ID from params used without ownership check
findById\(req\.params|findOne\(.*req\.params|findByPk\(req\.params
# Then verify there's a subsequent ownership/role check

# Password hashing issues
createHash\(['"]md5|createHash\(['"]sha1
hashlib\.md5|hashlib\.sha1
MD5\.Create|SHA1\.Create

# Session issues
session(?!.*regenerate).*login|session(?!.*destroy).*logout

# JWT issues
algorithms.*none|alg.*none
verify\(.*\{.*algorithms
```

## Cryptography

```
# Weak algorithms
\bmd5\b|\bsha1\b|DES|RC4|Blowfish|ECB
AES(?!.*GCM|.*CCM|.*Poly)

# Insecure random
Math\.random\(\)|random\.random\(\)|rand\(\)
# In context of tokens, keys, session IDs, OTPs

# Hardcoded secrets
(password|secret|token|api_key|apikey|access_key|private_key|aws_secret)\s*[:=]\s*["'][^"']{8,}
(PASSWORD|SECRET|TOKEN|API_KEY|APIKEY|ACCESS_KEY|PRIVATE_KEY)\s*[:=]\s*["'][^"']{8,}

# Timing attacks
==.*hash|==.*mac|==.*token|==.*signature
# Should use constant-time comparison

# Static IV/nonce
(iv|nonce|IV|NONCE)\s*=\s*(b['"]|['"]|0x|\[0)
```

## SSRF

```
# User-controlled URL in HTTP requests
fetch\(.*req\.|fetch\(.*request\.|fetch\(.*user
axios\(.*req\.|axios\.get\(.*req\.|axios\.post\(.*req\.
requests\.get\(.*request\.|requests\.post\(.*request\.
http\.Get\(.*user|http\.Get\(.*req\.|http\.NewRequest\(.*user
urllib\.request\.urlopen\(.*request
HttpClient.*user|WebClient.*user
```

## Deserialization

```
# Unsafe deserialization
pickle\.load|pickle\.loads
yaml\.load\b(?!.*safe_load|.*SafeLoader|.*FullLoader)
shelve\.open|marshal\.loads
ObjectInputStream|readObject\(|readUnshared\(
unserialize\(
JsonConvert\.DeserializeObject(?!.*typeof|.*<)
```

## File Operations

```
# Path traversal
filepath\.Join\(.*req\.|filepath\.Join\(.*r\.URL
path\.join\(.*req\.|path\.resolve\(.*req\.
os\.path\.join\(.*request\.|open\(.*request\.
sendFile\(.*req\.params|serveFile\(.*req\.

# Unrestricted file upload
# Look for file upload handlers without:
# - Content-type validation
# - File extension validation
# - File size limits
multer\(\)|upload\.single|upload\.array
# Check for missing fileFilter, limits configuration
```

## Infrastructure as Code

```
# Terraform
Action\s*=\s*["']\*|Resource\s*=\s*["']\*
cidr_blocks\s*=\s*\["0\.0\.0\.0/0"\]
acl\s*=\s*["']public
storage_encrypted\s*=\s*false

# Kubernetes
privileged:\s*true
runAsUser:\s*0
allowPrivilegeEscalation:\s*true
hostNetwork:\s*true|hostPID:\s*true|hostIPC:\s*true
image:.*:latest

# Docker
FROM\s+\S+:latest
USER\s+root
ENV\s+\S*(PASSWORD|SECRET|KEY|TOKEN)\s*=
```

## Security Headers & CORS

```
# Missing/weak headers
Access-Control-Allow-Origin.*\*
origin.*req\.headers\.origin
unsafe-inline|unsafe-eval
X-Powered-By

# Cookie issues
Set-Cookie(?!.*[Ss]ecure)
Set-Cookie(?!.*[Hh]ttp[Oo]nly)
SameSite\s*=\s*None(?!.*[Ss]ecure)
```

## Supply Chain

```
# Lockfile issues
"integrity":\s*"sha1-

# GitHub Actions
uses:.*@v[0-9]
uses:.*@main|uses:.*@master
uses:.*@latest
permissions:\s*write-all

# CI dangerous patterns
npm install(?!.*--ci|.*ci\b)
curl.*\|.*sh|wget.*\|.*sh
```

## Error Handling & Logging

```
# Swallowed errors
catch\s*\(.*\)\s*\{\s*\}
except:\s*pass|except\s+Exception.*pass
catch\s*\{.*\}.*//.*ignore|catch\s*\{.*\}.*//.*suppress

# Information leakage in errors
stack|stackTrace|stack_trace
err\.message|error\.message
# In production error responses

# Sensitive data in logs
log\.(info|debug|warn|error).*password|log\.(info|debug|warn|error).*token
logger\.(info|debug|warn|error).*password|logger\.(info|debug|warn|error).*secret
console\.log.*password|console\.log.*token|console\.log.*secret
```

---

## Usage Guide

1. Run these patterns against the target codebase using `Grep`
2. Group results by category
3. Manually verify each match — many patterns will have false positives
4. Check context: is the matched code reachable from user input?
5. Classify confirmed findings by severity
6. Cross-reference with OWASP Top 10 and CWE

**Important:** These patterns catch common cases. They are NOT exhaustive. Always perform manual code review in addition to pattern-based scanning.
