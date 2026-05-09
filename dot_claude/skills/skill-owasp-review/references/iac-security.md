# Infrastructure-as-Code Security

## Terraform

### Overpermissive IAM

```hcl
# VULNERABLE — full admin access
resource "aws_iam_role_policy" "admin" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# SECURE — scoped permissions
resource "aws_iam_role_policy" "app" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::my-bucket/*"
    }]
  })
}
```

### Public S3 bucket

```hcl
# VULNERABLE
resource "aws_s3_bucket" "data" {
  acl = "public-read"
}

# SECURE
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### Open security groups

```hcl
# VULNERABLE — SSH/RDP open to internet
resource "aws_security_group_rule" "ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# SECURE — restricted to internal network
resource "aws_security_group_rule" "ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/8"]
}
```

### Unencrypted storage

```hcl
# VULNERABLE — no encryption
resource "aws_rds_instance" "db" {
  storage_encrypted = false
}

# SECURE
resource "aws_rds_instance" "db" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.db.arn
}
```

### State file security
Terraform state stores secrets in plaintext. Use:
- Remote backend with encryption (S3 + SSE-KMS)
- State locking (DynamoDB)
- Restricted access to state bucket
- Never commit `.tfstate` files

### Detection patterns
```
Action.*["']?\*["']?              # Wildcard IAM actions
Resource.*["']?\*["']?            # Wildcard IAM resources
cidr_blocks.*0\.0\.0\.0/0        # Open to internet
acl.*public                      # Public access
storage_encrypted\s*=\s*false    # Unencrypted storage
```

**Tools:** `tfsec`, `checkov`, `trivy config`, `terrascan`

---

## Kubernetes

### Privileged containers

```yaml
# VULNERABLE
spec:
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      privileged: true
      runAsUser: 0

# SECURE
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:v1.2.3@sha256:abc123def...
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    resources:
      limits:
        memory: "256Mi"
        cpu: "500m"
      requests:
        memory: "128Mi"
        cpu: "250m"
```

### Missing network policies

```yaml
# SECURE — default deny all ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

Without NetworkPolicies, all pods can communicate freely — lateral movement is trivial.

### RBAC misconfigurations

```yaml
# VULNERABLE — cluster-admin for a service account
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-admin
subjects:
- kind: ServiceAccount
  name: app-sa
roleRef:
  kind: ClusterRole
  name: cluster-admin  # Full cluster access

# SECURE — scoped role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
  namespace: my-app
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
```

### Detection patterns
```
privileged:\s*true
runAsUser:\s*0
allowPrivilegeEscalation:\s*true
readOnlyRootFilesystem:\s*false
image:.*:latest
capabilities:(?!.*drop.*ALL)
hostNetwork:\s*true
hostPID:\s*true
hostIPC:\s*true
cluster-admin
```

**Tools:** `kubesec`, `kube-bench`, `trivy`, `polaris`, `OPA/Gatekeeper`

---

## Docker

### Dockerfile security

```dockerfile
# VULNERABLE
FROM ubuntu:latest                    # Mutable tag
RUN apt-get install -y curl wget vim  # Unnecessary packages
COPY . /app                           # Copies secrets, .git, etc.
ENV DB_PASSWORD=supersecret           # Secret in layer
USER root                            # Runs as root

# SECURE
FROM ubuntu:22.04@sha256:abc123... AS builder
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*
COPY --chown=1000:1000 app/ /app/
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup appuser
USER appuser
HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1
# Use build secrets for sensitive data
RUN --mount=type=secret,id=db_password \
    cat /run/secrets/db_password > /dev/null
```

### .dockerignore

Must exclude:
```
.git
.env
*.pem
*.key
credentials*
node_modules
__pycache__
.terraform
*.tfstate
```

### Docker Compose security

```yaml
# VULNERABLE
services:
  db:
    image: postgres
    environment:
      POSTGRES_PASSWORD: mysecret  # Secret in compose file
    ports:
      - "5432:5432"               # Exposed to host

# SECURE
services:
  db:
    image: postgres:16@sha256:abc123...
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    ports:
      - "127.0.0.1:5432:5432"    # Localhost only
    read_only: true
    tmpfs:
      - /tmp
      - /var/run/postgresql
```

### Detection patterns
```
FROM\s+\S+:latest
FROM\s+\S+(?!.*@sha256)          # No digest pinning
USER\s+root
ENV\s+.*(PASSWORD|SECRET|KEY|TOKEN)
COPY\s+\.\s+                     # Copy everything
apt-get install(?!.*--no-install-recommends)
```

**Tools:** `hadolint`, `trivy`, `dockle`, `snyk container`
