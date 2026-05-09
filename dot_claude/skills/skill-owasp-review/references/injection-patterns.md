# Injection Vulnerability Patterns

## SQL Injection (CWE-89)

### Vulnerable patterns

```javascript
// String concatenation
const query = `SELECT * FROM users WHERE name = '${userInput}'`;
const query = "SELECT * FROM users WHERE id = " + userId;
```

```python
# f-string / format in SQL
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
cursor.execute("SELECT * FROM users WHERE name = '%s'" % name)
```

```go
// Sprintf in SQL
query := fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", userInput)
db.Query(query)
```

```java
// String concatenation
String query = "SELECT * FROM users WHERE id = " + userId;
Statement stmt = conn.createStatement();
stmt.executeQuery(query);
```

### Secure patterns

```javascript
// Parameterized query
const results = await db.query('SELECT * FROM users WHERE name = $1', [userInput]);
```

```python
# Parameterized
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

```go
// Parameterized
db.Query("SELECT * FROM users WHERE name = $1", userInput)
```

```java
// PreparedStatement
PreparedStatement stmt = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
stmt.setInt(1, userId);
```

### Detection
Search for string interpolation/concatenation near SQL keywords: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `FROM`, `WHERE`.

---

## OS Command Injection (CWE-78)

### Vulnerable patterns

```python
os.system(f"convert {filename} output.png")
subprocess.call(f"ls {path}", shell=True)
subprocess.Popen(cmd, shell=True)
```

```javascript
const { exec } = require('child_process');
exec(`grep ${userInput} /var/log/app.log`);
```

```go
exec.Command("sh", "-c", "echo " + userInput)
```

```java
Runtime.getRuntime().exec("cmd /c " + userInput);
```

### Secure patterns

```python
subprocess.run(["convert", filename, "output.png"], check=True)  # No shell=True
```

```javascript
const { execFile } = require('child_process');
execFile('grep', [userInput, '/var/log/app.log']);  // Array form, no shell
```

```go
exec.Command("echo", userInput)  // Direct args, no shell
```

**Rule:** Never pass user input through a shell. Use array-based APIs. If shell is unavoidable, validate input against strict allowlist (`^[a-zA-Z0-9_.-]+$`).

---

## Cross-Site Scripting — XSS (CWE-79)

### Stored XSS
User input saved to database, rendered to other users without encoding.

### Reflected XSS
User input from URL/form reflected back in response without encoding.

### DOM-based XSS
Client-side JavaScript inserts user input into DOM unsafely.

### Vulnerable patterns

```javascript
// Server-side reflected
res.send(`<h1>Results for: ${req.query.q}</h1>`);

// React - bypassing auto-escaping
<div dangerouslySetInnerHTML={{ __html: userContent }} />

// DOM-based
document.getElementById('output').innerHTML = location.hash.slice(1);

// jQuery
$('#output').html(userInput);
```

### Secure patterns

```javascript
// Server-side: encode output
const escapeHtml = require('escape-html');
res.send(`<h1>Results for: ${escapeHtml(req.query.q)}</h1>`);

// React: use textContent (default behavior)
<div>{userContent}</div>

// If HTML rendering needed: sanitize
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userContent) }} />

// DOM: use textContent
document.getElementById('output').textContent = userInput;
```

**Context-aware encoding rules:**
- HTML body: HTML entity encode (`<` → `&lt;`)
- HTML attribute: attribute encode + quote attributes
- JavaScript context: JS encode or JSON.stringify
- URL parameter: URL encode (`encodeURIComponent`)
- CSS context: CSS encode (avoid user input in CSS entirely if possible)

---

## Template Injection (SSTI) (CWE-94)

### Vulnerable patterns

```python
# Jinja2 with user-controlled template
template = Template(user_input)  # User sends: {{ config.items() }}
output = template.render()

# Flask
@app.route('/greet')
def greet():
    return render_template_string(f"Hello {request.args['name']}")
```

### Secure patterns

```python
# Pass user input as data, not template
return render_template('greet.html', name=request.args['name'])

# If dynamic templates needed: sandbox
from jinja2.sandbox import SandboxedEnvironment
env = SandboxedEnvironment()
template = env.from_string(template_str)
```

**Detection:** `Template(user`, `render_template_string(.*request`, `render_template_string(.*f"`.

---

## Path Traversal (CWE-22)

### Vulnerable patterns

```javascript
app.get('/files/:name', (req, res) => {
  res.sendFile(path.join('/uploads', req.params.name));  // ../../../etc/passwd
});
```

```go
http.ServeFile(w, r, filepath.Join("/uploads", r.URL.Path))
```

```python
with open(os.path.join('/data', user_filename)) as f:
    return f.read()
```

### Secure patterns

```javascript
const safeName = path.basename(req.params.name);  // Strip directory components
const fullPath = path.resolve('/uploads', safeName);
if (!fullPath.startsWith('/uploads/')) {
  return res.status(400).send('Invalid path');
}
res.sendFile(fullPath);
```

```go
cleanPath := filepath.Clean(userPath)
fullPath := filepath.Join("/uploads", filepath.Base(cleanPath))
if !strings.HasPrefix(fullPath, "/uploads/") {
    http.Error(w, "invalid path", 400)
    return
}
```

**Rule:** Use `path.basename()` / `filepath.Base()` to strip directory traversal. Always verify the resolved path starts with the expected base directory.

---

## LDAP Injection (CWE-90)

### Vulnerable pattern
```java
String filter = "(&(uid=" + username + ")(password=" + password + "))";
```

### Secure pattern
```java
// Escape special LDAP characters: * ( ) \ NUL
String safeUser = LdapEncoder.filterEncode(username);
String filter = "(&(uid=" + safeUser + ")(password=" + safePass + "))";
```

---

## NoSQL Injection

### Vulnerable pattern (MongoDB)
```javascript
// User sends: { "$gt": "" } as username
const user = await db.users.findOne({
  username: req.body.username,  // Object injection
  password: req.body.password
});
```

### Secure pattern
```javascript
// Type-check inputs
if (typeof req.body.username !== 'string' || typeof req.body.password !== 'string') {
  return res.status(400).json({ error: 'Invalid input' });
}
// Or use mongo-sanitize
const sanitize = require('mongo-sanitize');
const user = await db.users.findOne({
  username: sanitize(req.body.username),
  password: sanitize(req.body.password)
});
```

**Detection:** MongoDB queries using `req.body` or `req.query` directly without type validation; `$where`, `$regex` with user input.
