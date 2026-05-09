# Cryptography Security Patterns

## Approved Algorithms

| Purpose | Approved | Deprecated / Broken |
|---------|----------|---------------------|
| Password hashing | Argon2id, bcrypt (cost>=12), scrypt, PBKDF2 (>=600k iter) | MD5, SHA-1, SHA-256 (unsalted), plaintext |
| Symmetric encryption | AES-256-GCM, ChaCha20-Poly1305 | DES, 3DES, RC4, Blowfish, AES-ECB |
| Asymmetric encryption | RSA-2048+ (OAEP), ECDSA P-256+ | RSA-1024, DSA |
| Hashing (non-password) | SHA-256, SHA-384, SHA-512, BLAKE2/BLAKE3 | MD5, SHA-1 |
| Key exchange | ECDH (X25519), DH-2048+ | DH-1024 |
| TLS | TLS 1.2 (strong ciphers only), TLS 1.3 | SSL 2/3, TLS 1.0, TLS 1.1 |
| CSPRNG | OS-provided (`crypto.randomBytes`, `secrets`, `crypto/rand`) | `Math.random()`, `rand()`, `random.random()` |
| MAC | HMAC-SHA256, Poly1305 | HMAC-MD5, HMAC-SHA1 |

---

## Common Mistakes

### 1. Weak password hashing

```python
# VULNERABLE
hashlib.md5(password.encode()).hexdigest()
hashlib.sha256(password.encode()).hexdigest()

# SECURE
from argon2 import PasswordHasher
ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)
hash = ph.hash(password)
```

### 2. ECB mode (identical blocks → identical ciphertext)

```python
# VULNERABLE — pattern-preserving encryption
cipher = AES.new(key, AES.MODE_ECB)

# SECURE — authenticated encryption
cipher = AES.new(key, AES.MODE_GCM, nonce=os.urandom(12))
ciphertext, tag = cipher.encrypt_and_digest(plaintext)
```

### 3. IV/nonce reuse

```python
# VULNERABLE — same nonce for every encryption
NONCE = b'\x00' * 12
cipher = AES.new(key, AES.MODE_GCM, nonce=NONCE)

# SECURE — unique nonce per operation
nonce = os.urandom(12)  # Random 96-bit nonce
cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
# Store nonce with ciphertext: nonce + ciphertext + tag
```

**AES-GCM nonce reuse** is catastrophic: it exposes the authentication key and allows ciphertext forgery.

### 4. Hardcoded keys

```javascript
// VULNERABLE
const ENCRYPTION_KEY = 'supersecretkey123456789012345678';
const cipher = crypto.createCipheriv('aes-256-gcm', ENCRYPTION_KEY, iv);

// SECURE
const ENCRYPTION_KEY = Buffer.from(process.env.ENCRYPTION_KEY, 'hex');
// Or use KMS: AWS KMS, HashiCorp Vault, GCP KMS
```

### 5. Non-CSPRNG for security values

```javascript
// VULNERABLE — predictable
const token = Math.random().toString(36).substring(2);
const otp = Math.floor(Math.random() * 1000000);

// SECURE
const token = crypto.randomBytes(32).toString('hex');
const otp = crypto.randomInt(100000, 999999);
```

```python
# VULNERABLE
import random
token = ''.join(random.choices(string.ascii_letters, k=32))

# SECURE
import secrets
token = secrets.token_hex(32)
otp = secrets.randbelow(900000) + 100000
```

### 6. Timing attacks on comparison

```javascript
// VULNERABLE — early return reveals length of match
if (providedMac === expectedMac) { ... }

// SECURE — constant-time comparison
const crypto = require('crypto');
if (crypto.timingSafeEqual(Buffer.from(providedMac), Buffer.from(expectedMac))) { ... }
```

```python
# SECURE
import hmac
if hmac.compare_digest(provided_mac, expected_mac): ...
```

### 7. Encryption without authentication

```python
# VULNERABLE — AES-CBC without MAC (padding oracle attacks)
cipher = AES.new(key, AES.MODE_CBC, iv)
ciphertext = cipher.encrypt(pad(plaintext))

# SECURE — use AEAD mode
cipher = AES.new(key, AES.MODE_GCM, nonce=os.urandom(12))
ciphertext, tag = cipher.encrypt_and_digest(plaintext)
# Verify tag on decryption
```

**Rule:** Always use AEAD (Authenticated Encryption with Associated Data): AES-GCM or ChaCha20-Poly1305.

### 8. Custom/homemade crypto

```python
# VULNERABLE — XOR "encryption"
def encrypt(data, key):
    return bytes(a ^ b for a, b in zip(data, itertools.cycle(key)))

# SECURE — use established library
from cryptography.fernet import Fernet
key = Fernet.generate_key()
cipher = Fernet(key)
encrypted = cipher.encrypt(plaintext)
```

**Rule:** Never implement your own cryptographic algorithms. Use well-audited libraries: `libsodium`, `cryptography` (Python), `crypto` (Node/Go), Tink.

---

## Key Management

### Requirements
1. **Never hardcode keys** in source code or configuration files
2. **Use KMS** for production: AWS KMS, GCP Cloud KMS, Azure Key Vault, HashiCorp Vault
3. **Rotate keys** periodically — support key versioning
4. **Separate keys** by environment (dev/staging/prod)
5. **Minimum key lengths**: AES-256, RSA-2048, ECDSA P-256

### Key derivation from passwords

```javascript
// When deriving encryption key from password (not for password storage)
const key = crypto.pbkdf2Sync(password, salt, 600000, 32, 'sha256');
// Or use scrypt
const key = crypto.scryptSync(password, salt, 32, { N: 2**17, r: 8, p: 1 });
```

---

## Detection Patterns

Search for these in code:
- `md5(`, `MD5.`, `hashlib.md5`, `crypto.createHash('md5')`
- `sha1(`, `SHA1`, `hashlib.sha1`, `crypto.createHash('sha1')`
- `DES`, `RC4`, `Blowfish`, `ECB`
- `Math.random()`, `random.random()`, `rand()` in security contexts
- `AES` without `GCM` or authenticated mode
- `==` comparing hashes, MACs, or tokens (instead of constant-time)
- Hardcoded base64 strings that look like keys (32+ chars)
- Static IV/nonce values (e.g., `nonce = b'\x00' * 12`)
