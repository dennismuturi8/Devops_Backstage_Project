# KBUCCI Technologies — Backstage Internal Developer Portal

A production-grade deployment of [Spotify Backstage](https://backstage.io) on a self-managed Kubernetes cluster. This project implements a full GitOps pipeline using GitHub Actions, ArgoCD, MetalLB, NGINX Ingress, CloudNativePG, Sealed Secrets, and Let's Encrypt TLS — provisioned entirely via Terraform and Ansible.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Prerequisites](#4-prerequisites)
5. [Infrastructure Provisioning](#5-infrastructure-provisioning)
6. [Ansible Configuration](#6-ansible-configuration)
7. [Secrets Management with Sealed Secrets](#7-secrets-management-with-sealed-secrets)
8. [Manifest Structure and ArgoCD Apps](#8-manifest-structure-and-argocd-apps)
9. [CI/CD Pipeline](#9-cicd-pipeline)
10. [Accessing the Application from a Browser](#10-accessing-the-application-from-a-browser)
11. [ArgoCD UI Access](#11-argocd-ui-access)
12. [Database — CloudNativePG](#12-database--cloudnativepg)
13. [TLS Certificates — Let's Encrypt](#13-tls-certificates--lets-encrypt)
14. [MetalLB Load Balancer](#14-metallb-load-balancer)
15. [Health Checks and Verification](#15-health-checks-and-verification)
16. [Troubleshooting](#16-troubleshooting)
17. [Day-2 Operations](#17-day-2-operations)
18. [Security Considerations](#18-security-considerations)
19. [File Reference](#19-file-reference)

---

## 1. Project Overview

This repository contains everything needed to deploy Backstage as a production-ready Internal Developer Portal (IDP). The stack is fully declarative — infrastructure, Kubernetes resources, TLS certificates, and database are all defined as code and managed through Git.

**What gets deployed:**

- **Backstage** — The IDP application, running as a containerised workload on Kubernetes
- **PostgreSQL** — Managed by the CloudNativePG operator with automatic failover support
- **NGINX Ingress Controller** — Routes external HTTP/HTTPS traffic into the cluster
- **MetalLB** — Provides LoadBalancer IP addresses on bare-metal / on-prem clusters
- **Cert-Manager** — Automates TLS certificate issuance and renewal via Let's Encrypt
- **ArgoCD** — GitOps controller that continuously syncs Git state to the cluster
- **Sealed Secrets** — Encrypts Kubernetes Secrets so they can be safely stored in Git

**How it flows end-to-end:**

```
Developer pushes code
        ↓
GitHub Actions (test → build → security scan → push image)
        ↓
Manifest updated with new image SHA
        ↓
ArgoCD detects change → syncs to cluster
        ↓
Backstage pod rolling update
        ↓
Live at https://kbucci.com
```

---

## 2. Architecture

```
Internet
    │
    ▼
DNS: kbucci.com → MetalLB External IP
    │
    ▼
MetalLB LoadBalancer (Layer 2, bare-metal)
    │
    ▼
NGINX Ingress Controller (ingress-nginx namespace)
    │  TLS terminated here by cert-manager / Let's Encrypt
    ▼
Backstage Service (ClusterIP, port 80 → 7007)
    │
    ▼
Backstage Pod (dennismuturi8/backstage:<sha>)
    │
    ▼
CloudNativePG Cluster (backstage-db, port 5432)
```

**Namespace layout:**

| Namespace | What lives there |
|---|---|
| `backstage` | Backstage Deployment, Service, Ingress, CNPG Cluster, Sealed Secret |
| `ingress-nginx` | NGINX Ingress Controller, LoadBalancer Service |
| `metallb-system` | MetalLB controller, speaker, IPAddressPool |
| `cert-manager` | Cert-Manager controller, webhook, cainjector, ClusterIssuer |
| `cnpg-system` | CloudNativePG operator |
| `argocd` | ArgoCD server, application controller, repo server |
| `kube-system` | Sealed Secrets controller |

---

## 3. Repository Structure

```
DevOps_Backstage_Project/
│
├── .github/
│   └── workflows/
│       └── gitops-app.yaml          # CI/CD pipeline (test → build → deploy)
│
├── Infra/
│   ├── Ansible/
│   │   └── plybk.yaml               # Installs all cluster components
│   └── Terraform/
│       └── main.tf                  # Provisions EC2 nodes
│
├── manifest/
│   ├── backstage/                   # ArgoCD App 1 — namespace: backstage
│   │   ├── backstage-namespace.yaml
│   │   ├── backstage_deploy.yaml
│   │   ├── backstage_svc.yaml
│   │   ├── backstage-ingress.yaml
│   │   ├── cnpg-cluster.yaml
│   │   └── sealed-db-credentials.yaml  ← safe to commit (encrypted)
│   ├── ingress/                     # ArgoCD App 2 — namespace: ingress-nginx
│   │   └── ingress-nginx-lb.yaml
│   ├── metallb/                     # ArgoCD App 3 — namespace: metallb-system
│   │   └── metallb-config.yaml
│   └── certmanager/                 # ArgoCD App 4 — namespace: cert-manager
│       └── letsencrypt.yaml
│
├── packages/
│   ├── app/                         # Backstage React frontend
│   └── backend/                     # Backstage Node.js backend
│
├── plugins/                         # Custom Backstage plugins
│
├── argocd-apps.yaml                 # Registers all 4 ArgoCD Applications (apply once)
├── seal-secret.sh                   # Script to encrypt secret.yaml → sealed-db-credentials.yaml
├── .gitignore
├── app-config.yaml                  # Backstage base configuration
├── app-config.production.yaml       # Production overrides
├── Dockerfile
├── package.json
└── README.md
```

**Files that must NEVER be committed:**

```
secret.yaml                 # Plaintext DB password — local use only
sealed-secrets-pub.pem      # Public cert from cluster — local use only
Infra/Ansible/inventory.ini # Auto-generated by manage.sh, contains IPs and SSH key paths
*.tfstate / *.tfvars        # Terraform state — may contain sensitive output values
.env / .env.*               # Any environment files
```

All of the above are covered in `.gitignore`. Run `git status` and verify before every push.

---

## 4. Prerequisites

### Local machine

| Tool | Minimum version | Install |
|---|---|---|
| Terraform | 1.5+ | https://developer.hashicorp.com/terraform/install |
| Ansible | 2.14+ | `pip install ansible` |
| kubectl | 1.28+ | https://kubernetes.io/docs/tasks/tools |
| kubeseal | 0.24+ | See Section 7 |
| jq | any | `sudo apt install jq` / `brew install jq` |
| Docker | 24+ | https://docs.docker.com/engine/install |

### Cloud / infrastructure

- AWS account with EC2 permissions (or adjust `main.tf` for your provider)
- A registered domain name pointing to the external IP assigned by MetalLB
- Port 80 and 443 open inbound on your nodes' security group (required for Let's Encrypt)
- SSH key pair for Ansible to access the nodes

### GitHub

The following repository secrets must be set before the first push to `main`. Go to **Settings → Secrets and variables → Actions** in your GitHub repo:

| Secret name | Description |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not your password) |
| `GIT_USERNAME` | Your GitHub username |
| `GIT_EMAIL` | Your GitHub email address |
| `GIT_TOKEN` | GitHub Personal Access Token with `repo` scope |

---

## 5. Infrastructure Provisioning

The `manage.sh` script in `Infra/` orchestrates Terraform and Ansible in sequence.

### Provision everything from scratch

```bash
cd Infra
bash manage.sh up
```

This runs three phases automatically:

**Phase 1 — Terraform:** Provisions EC2 instances (control plane + workers), outputs their IPs and SSH key path.

**Phase 2 — Inventory generation:** Builds `Infra/Ansible/inventory.ini` dynamically from Terraform outputs. This file is gitignored — it is regenerated on every `manage.sh up`.

**Phase 3 — Ansible:** Connects to the nodes and installs the full cluster stack (see Section 6).

### Destroy everything

```bash
cd Infra
bash manage.sh down
```

Tears down all EC2 instances and removes the Ansible inventory.

### Re-run Ansible only (no infra changes)

Useful when you've updated `plybk.yaml` and want to re-apply without reprovisioning:

```bash
cd Infra
bash manage.sh ansible
```

### Terraform outputs used by Ansible

`manage.sh` reads these from Terraform automatically:

```
control_plane_ip  → IP of the kubeadm control plane node
worker_ips        → JSON array of worker node IPs
ssh_user          → OS user for SSH (typically "ubuntu")
ssh_key_path      → Path to the private key file
```

Make sure your `main.tf` defines these outputs or `manage.sh` will fail at the extraction step.

---

## 6. Ansible Configuration

The Ansible playbook (`Infra/Ansible/plybk.yaml`) runs on the control plane node and installs the following components in order:

| Step | Component | Method |
|---|---|---|
| 1 | Python3, pip, curl, git, Helm | apt + shell |
| 2 | NGINX Ingress Controller | `kubectl apply` (bare-metal manifest) |
| 3 | ArgoCD | `kubectl apply --server-side` |
| 4 | MetalLB | `kubectl apply` |
| 5 | Cert-Manager | Helm (`jetstack/cert-manager v1.13.3`) |
| 6 | CloudNativePG operator | Helm (`cnpg/cloudnative-pg`) |
| 7 | Sealed Secrets controller | Helm (`sealed-secrets/sealed-secrets v2.15.3`) |
| 8 | User kubeconfig setup | copies `/etc/kubernetes/admin.conf` → `/home/ubuntu/.kube/config` |
| 9 | ArgoCD bootstrap | applies `argocd-apps.yaml` from the repo |

After step 7, the playbook automatically fetches the Sealed Secrets public certificate and saves it to `/home/ubuntu/sealed-secrets-pub.pem`. Copy this to your local machine before generating sealed secrets (see Section 7).

### After Ansible completes — copy your kubeconfig locally

```bash
scp ubuntu@<CONTROL_PLANE_IP>:/home/ubuntu/.kube/config ~/.kube/config

# Verify
kubectl get nodes
# All nodes should show: STATUS = Ready
```

---

## 7. Secrets Management with Sealed Secrets

This project uses **Bitnami Sealed Secrets** to safely store encrypted Kubernetes Secrets in Git. The Sealed Secrets controller (installed by Ansible in `kube-system`) is the only entity that can decrypt them — using a private key that never leaves the cluster.

### How it works

```
secret.yaml (plaintext, local only)
        │
        ▼  kubeseal --cert sealed-secrets-pub.pem
sealed-db-credentials.yaml (encrypted, safe to commit)
        │
        ▼  ArgoCD syncs to cluster
Sealed Secrets controller decrypts → real Kubernetes Secret
        │
        ▼  sync-wave: "2"
CloudNativePG reads secret → bootstraps Postgres DB
```

### Step 1 — Install kubeseal on your local machine

```bash
# Linux (amd64)
KUBESEAL_VERSION=0.24.0
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# macOS
brew install kubeseal

# Verify
kubeseal --version
```

### Step 2 — Copy the public certificate from your cluster

After `manage.sh up` completes, the Ansible playbook saves the cert to the control plane. Copy it to your local machine:

```bash
scp ubuntu@<CONTROL_PLANE_IP>:/home/ubuntu/sealed-secrets-pub.pem ./sealed-secrets-pub.pem
```

> This file is gitignored. Keep it locally. You will need it any time you rotate the password or create new sealed secrets.

Alternatively, fetch it live from the cluster at any time:

```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > sealed-secrets-pub.pem
```

### Step 3 — Create your plaintext secret (locally only)

Create a file named `secret.yaml` in the repo root. **This file is gitignored and must never be committed.**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backstage-db-credentials
  namespace: backstage
type: kubernetes.io/basic-auth
stringData:
  username: backstage
  password: "YourActualStrongPasswordHere!"
```

Rules for a strong password:
- Minimum 20 characters
- Mix of uppercase, lowercase, numbers, and symbols
- No `@` or `/` characters (can break connection strings in some configs)

### Step 4 — Seal the secret

Run the provided script from the repo root:

```bash
bash seal-secret.sh
```

This uses `sealed-secrets-pub.pem` to encrypt `secret.yaml` and writes the result to `manifest/backstage/sealed-db-credentials.yaml`.

The output file looks like this — the encrypted values are completely useless without the cluster's private key:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: backstage-db-credentials
  namespace: backstage
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  encryptedData:
    username: AgB3k9xM...   # encrypted — safe to commit
    password: AgCmP2qX...   # encrypted — safe to commit
  template:
    metadata:
      name: backstage-db-credentials
      namespace: backstage
    type: kubernetes.io/basic-auth
```

### Step 5 — Commit and push the sealed secret

```bash
git add manifest/backstage/sealed-db-credentials.yaml
git commit -m "chore: add sealed db credentials"
git push origin main
```

ArgoCD will sync the `SealedSecret` to the cluster. The Sealed Secrets controller will decrypt it and create a standard Kubernetes `Secret` named `backstage-db-credentials` in the `backstage` namespace. CloudNativePG will then read it (sync-wave 2) to bootstrap the database.

### Rotating the password

To change the database password at any time:

1. Edit `secret.yaml` locally with the new password
2. Run `bash seal-secret.sh` to regenerate the sealed file
3. Commit and push the updated `sealed-db-credentials.yaml`
4. ArgoCD syncs → controller decrypts → new Secret created
5. Restart the Backstage deployment to pick up the new credentials:
   ```bash
   kubectl rollout restart deployment/backstage -n backstage
   ```

### Verifying the secret was decrypted correctly

```bash
# Check the SealedSecret status
kubectl get sealedsecret backstage-db-credentials -n backstage

# Check the resulting plain Secret exists
kubectl get secret backstage-db-credentials -n backstage

# Inspect the decoded values (base64 decoded)
kubectl get secret backstage-db-credentials -n backstage \
  -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get secret backstage-db-credentials -n backstage \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## 8. Manifest Structure and ArgoCD Apps

The `manifest/` folder is split into four subfolders — one per ArgoCD Application. This avoids namespace conflicts that would occur if all manifests were in a single flat folder with a single destination namespace.

### ArgoCD Application mapping

| ArgoCD App name | Git path | Destination namespace |
|---|---|---|
| `backstage` | `manifest/backstage/` | `backstage` |
| `ingress-nginx-config` | `manifest/ingress/` | `ingress-nginx` |
| `metallb-config` | `manifest/metallb/` | `metallb-system` |
| `cert-manager-config` | `manifest/certmanager/` | `cert-manager` |

### Sync waves (deployment order within the backstage app)

Within `manifest/backstage/`, ArgoCD respects sync-wave annotations to enforce resource creation order:

| Wave | Resource | Why |
|---|---|---|
| `1` | `sealed-db-credentials.yaml` | Secret must exist before the DB can bootstrap |
| `2` | `cnpg-cluster.yaml` | DB must exist before Backstage can connect |
| (default) | All other resources | Namespace, Deployment, Service, Ingress |

### Bootstrapping ArgoCD (one-time manual step)

After `manage.sh up`, the Ansible playbook applies `argocd-apps.yaml` automatically. If you ever need to re-apply it manually:

```bash
kubectl apply -f argocd-apps.yaml
```

This registers all four Applications with ArgoCD. From that point on, every `git push` to the `manifest/` subfolders triggers an automatic sync.

---

## 9. CI/CD Pipeline

The pipeline lives in `.github/workflows/gitops-app.yaml` and runs on every push to `main` (excluding changes to the `manifest/` folder itself to prevent infinite loops).

### Stage 1 — Quality Gate

Runs on all pushes and pull requests:

- Sets up Node.js 20.18.0 with Corepack and Yarn 4.4.1
- Installs build dependencies (`build-essential`, `python3`)
- Runs `yarn lint:all` — fails the pipeline on lint errors
- Runs `yarn test` — fails the pipeline on test failures

### Stage 2 — Build, Scan & Push

Runs only on pushes to `main` (not PRs):

- Builds the Docker image tagged with the Git commit SHA
- Runs **Trivy** security scan — fails on CRITICAL or HIGH unfixed CVEs in OS packages and libraries
- Pushes the image to Docker Hub as `dennismuturi8/backstage:<commit-sha>`

### Stage 3 — GitOps Update

Runs after Stage 2 succeeds:

- Checks out the repo with the `GIT_TOKEN` secret
- Uses `sed` to replace the image tag in `manifest/backstage/backstage_deploy.yaml`
- Commits the change with message `chore(deploy): update backstage to <sha> [skip ci]`
- Pushes to `main` — the `[skip ci]` tag prevents the pipeline from retriggering

ArgoCD polls Git every 3 minutes and detects the manifest change, triggering a rolling update of the Backstage pod.

### Viewing pipeline runs

Go to your GitHub repo → **Actions** tab. Each run shows all three stages. Click any stage to see the full logs.

---

## 10. Accessing the Application from a Browser

### Prerequisites for browser access

Before the app is reachable in a browser, all of the following must be true:

1. MetalLB has assigned an external IP to the NGINX Ingress LoadBalancer service
2. Your domain `kbucci.com` has an A record pointing to that IP
3. Cert-Manager has issued a valid TLS certificate for the domain
4. The Backstage pod is running and healthy
5. Port 443 (and port 80 for HTTP redirect) is open on your cluster's firewall/security group

### Step 1 — Find the external IP

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Look at the `EXTERNAL-IP` column. If it shows `<pending>`, MetalLB has not assigned an IP yet — see the MetalLB troubleshooting section.

Example output:
```
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
ingress-nginx-controller   LoadBalancer   10.96.45.12     192.168.1.200   80:32080/TCP,443:32443/TCP
```

Your external IP is `192.168.1.200`.

### Step 2 — Configure DNS

Log in to your domain registrar or DNS provider and create an A record:

```
Type:  A
Host:  kbucci.com   (or @ for the root domain)
Value: 192.168.1.200   ← your MetalLB external IP
TTL:   300 (5 minutes — low TTL during setup)
```

If you also want `www.kbucci.com` to work, add a second A record or a CNAME pointing to `kbucci.com`.

Verify DNS propagation (may take 1–15 minutes):

```bash
dig kbucci.com +short
# Should return: 192.168.1.200

# Or use an online tool:
# https://dnschecker.org
```

### Step 3 — Wait for the TLS certificate

Cert-Manager automatically requests a certificate from Let's Encrypt once the Ingress is created and DNS resolves correctly.

```bash
# Watch certificate issuance
kubectl get certificate -n backstage -w
```

The `READY` column will flip from `False` to `True` once the certificate is issued. This typically takes 1–3 minutes after DNS propagates.

If it stays `False` for more than 5 minutes:

```bash
kubectl describe certificaterequest -n backstage
kubectl describe challenge -n backstage
```

The most common cause is DNS not yet propagated, or port 80 being blocked by a firewall rule.

### Step 4 — Open in browser

Once the certificate is ready, navigate to:

```
https://kbucci.com
```

You should see the Backstage welcome screen with a valid, browser-trusted TLS certificate. The padlock icon in your browser confirms TLS is working.

HTTP requests are automatically redirected to HTTPS by the NGINX Ingress annotation `ssl-redirect: "true"`.

### What if you don't have a public domain yet?

For local or private network testing, you can bypass DNS by adding a hosts file entry on your machine:

```bash
# Linux / macOS
sudo nano /etc/hosts

# Add this line (replace with your actual MetalLB IP):
192.168.1.200   kbucci.com
```

Then open `https://kbucci.com` in your browser. You will see a certificate warning because Let's Encrypt cannot validate a domain that only resolves locally — click "Proceed anyway" for testing purposes. For production, you need a real public DNS record.

---

## 11. ArgoCD UI Access

ArgoCD provides a web interface to view and manage all deployed applications.

### Access via port-forward

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open your browser at: `https://localhost:8080`

Accept the self-signed certificate warning (this is normal for the ArgoCD UI accessed via port-forward).

### Get the initial admin password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login credentials:
- **Username:** `admin`
- **Password:** the output of the command above

### Change the admin password (recommended)

Once logged in, go to **User Info** (top right) → **Update Password**.

Or via CLI:

```bash
argocd login localhost:8080 --username admin --insecure
argocd account update-password
```

### What you'll see in the ArgoCD UI

Four applications will appear, each with a health status:

- `backstage` — shows the Deployment, Service, Ingress, CNPG Cluster, SealedSecret
- `ingress-nginx-config` — shows the LoadBalancer Service
- `metallb-config` — shows the IPAddressPool and L2Advertisement
- `cert-manager-config` — shows the ClusterIssuer

Each app shows a sync status (`Synced` / `OutOfSync`) and a health status (`Healthy` / `Degraded` / `Progressing`). Click any app to see the individual resource tree with live status.

---

## 12. Database — CloudNativePG

Backstage requires a PostgreSQL database. This project uses the **CloudNativePG (CNPG)** operator, which manages the full lifecycle of the database — provisioning, configuration, health monitoring, and automatic failover.

### How it works

The CNPG operator is installed in `cnpg-system` by Ansible. It watches for `Cluster` custom resources in any namespace. When ArgoCD syncs `cnpg-cluster.yaml` into the `backstage` namespace, the operator:

1. Creates the Postgres pod(s)
2. Provisions a PersistentVolumeClaim for data storage
3. Reads `backstage-db-credentials` secret to set up the database user and password
4. Creates a `backstage-db-app` secret (used by the Backstage Deployment to connect)

### Auto-created connection secret

After the CNPG Cluster is healthy, a secret named `backstage-db-app` is automatically created in the `backstage` namespace. This is what the Backstage Deployment reads for its database connection:

```bash
kubectl get secret backstage-db-app -n backstage -o yaml
```

The Backstage Deployment references it like this (already configured in `backstage_deploy.yaml`):

```yaml
env:
- name: POSTGRES_HOST
  value: "backstage-db-rw.backstage.svc"
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: backstage-db-app
      key: username
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: backstage-db-app
      key: password
```

### Checking database health

```bash
# Check the CNPG Cluster status
kubectl get cluster backstage-db -n backstage

# Detailed status including primary election and replication
kubectl describe cluster backstage-db -n backstage

# Check the Postgres pod is running
kubectl get pods -n backstage -l cnpg.io/cluster=backstage-db

# Connect to the database directly
kubectl exec -it backstage-db-1 -n backstage -- psql -U backstage -d backstage
```

### Scaling for high availability

The current configuration uses `instances: 1` (suitable for development). For production with multiple worker nodes, set `instances: 3` in `cnpg-cluster.yaml`. CNPG will automatically elect a primary and configure two read replicas with streaming replication.

```yaml
spec:
  instances: 3   # edit in manifest/backstage/cnpg-cluster.yaml
```

Commit the change and ArgoCD will sync it, triggering CNPG to provision the additional instances.

---

## 13. TLS Certificates — Let's Encrypt

TLS is handled automatically by Cert-Manager using the Let's Encrypt ACME protocol with an HTTP-01 challenge.

### How certificate issuance works

1. ArgoCD syncs `letsencrypt.yaml` → creates the `letsencrypt-prod` ClusterIssuer
2. ArgoCD syncs `backstage-ingress.yaml` → Ingress has `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation
3. Cert-Manager sees the annotation and creates a `CertificateRequest`
4. Cert-Manager creates a temporary Ingress rule to serve the ACME challenge at `http://kbucci.com/.well-known/acme-challenge/<token>`
5. Let's Encrypt's servers hit that URL to verify you control the domain
6. Let's Encrypt issues the certificate
7. Cert-Manager stores it in the `backstage-tls` Secret in the `backstage` namespace
8. NGINX Ingress picks up the secret and serves it for HTTPS connections

### Testing with staging first (recommended)

Let's Encrypt enforces rate limits: 5 failed certificate requests per domain per hour. To avoid hitting this during setup, test with the staging issuer first:

In `manifest/backstage/backstage-ingress.yaml`, temporarily change the annotation:

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-staging   # ← staging first
```

Commit and push. Wait for a certificate to be issued (it will show `READY: True` but browsers won't trust it — that is expected). Once confirmed working, switch back to `letsencrypt-prod` and push again.

### Certificate auto-renewal

Cert-Manager automatically renews certificates 30 days before expiry. No manual action is ever required.

```bash
# Check certificate expiry
kubectl get certificate backstage-tls -n backstage -o jsonpath='{.status.notAfter}'
```

---

## 14. MetalLB Load Balancer

MetalLB provides LoadBalancer-type Services on bare-metal and on-premises clusters where a cloud provider load balancer is not available.

### Configuration

MetalLB is configured in `manifest/metallb/metallb-config.yaml`:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: backstage-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.210   # ← edit to match your LAN
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: backstage-l2
  namespace: metallb-system
```

### Choosing your IP range

The IP range must be:
- In the same subnet as your cluster nodes (e.g., if nodes are `192.168.1.x`, use `192.168.1.y-192.168.1.z`)
- Not currently assigned to any device on the network
- Not in your router's DHCP pool (check your router's DHCP range and pick addresses outside it)

To find your node subnet:

```bash
# Run on the control plane node
ip addr show
# Look for your primary interface (usually eth0 or ens3)
# e.g. inet 192.168.1.10/24 → you're on the 192.168.1.0/24 subnet
```

### Verifying MetalLB assigned an IP

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# EXTERNAL-IP should show an IP from your pool, not <pending>

kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

---

## 15. Health Checks and Verification

Run these checks in order after a fresh deployment to confirm everything is healthy.

### Cluster nodes

```bash
kubectl get nodes
# All nodes: STATUS = Ready
```

### All system pods

```bash
kubectl get pods -A
# No pods should be in CrashLoopBackOff or Error state
```

### Sealed Secrets

```bash
kubectl get sealedsecret backstage-db-credentials -n backstage
# Should exist and show no errors

kubectl get secret backstage-db-credentials -n backstage
# Real secret created by the controller
```

### Database

```bash
kubectl get cluster backstage-db -n backstage
# STATUS = Cluster in healthy state

kubectl get pods -n backstage -l cnpg.io/cluster=backstage-db
# STATUS = Running
```

### MetalLB IP assignment

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# EXTERNAL-IP = an IP from your pool (not <pending>)
```

### TLS certificate

```bash
kubectl get certificate backstage-tls -n backstage
# READY = True
```

### Backstage pod

```bash
kubectl get pods -n backstage -l app=backstage
# STATUS = Running, RESTARTS = 0

kubectl logs -f deployment/backstage -n backstage
# No ERROR lines, should show "Listening on port 7007"
```

### Application health endpoint

```bash
curl https://kbucci.com/healthcheck
# Expected response: {"status":"ok"}
```

### Ingress routing

```bash
kubectl describe ingress backstage-ingress -n backstage
# Should show: backend = backstage:80, TLS = backstage-tls
```

### ArgoCD sync status

```bash
kubectl get application -n argocd
# All apps: SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

---

## 16. Troubleshooting

### `EXTERNAL-IP` stuck on `<pending>`

MetalLB is not assigning an IP. Common causes:

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system
# All should be Running

# Check if IPAddressPool was synced by ArgoCD
kubectl get ipaddresspool -n metallb-system

# If not, apply manually:
kubectl apply -f manifest/metallb/metallb-config.yaml

# Check MetalLB speaker logs
kubectl logs -n metallb-system -l component=speaker
```

### Backstage pod in `CrashLoopBackOff`

```bash
kubectl logs -n backstage deployment/backstage --previous
```

Common causes:
- Database not ready yet — wait for `kubectl get cluster backstage-db -n backstage` to show healthy, then the pod will recover automatically
- Wrong DB connection env vars — check `backstage-db-app` secret exists and contains the right values
- `app-config.production.yaml` has wrong `baseUrl` — must match your actual domain

### Certificate stuck at `READY: False`

```bash
kubectl describe certificaterequest -n backstage
kubectl describe challenge -n backstage
```

Common causes:
- DNS not propagated yet — run `dig kbucci.com` and wait until it returns your MetalLB IP
- Port 80 blocked — Let's Encrypt must reach `http://kbucci.com/.well-known/acme-challenge/` on port 80. Check your security group / firewall rules
- Rate limited — if you've had 5 failures, wait 1 hour before retrying. Use the staging issuer while debugging

### ArgoCD shows `OutOfSync`

```bash
# Click the app in the ArgoCD UI for details, or:
kubectl describe application backstage -n argocd
```

Common causes:
- YAML syntax error in a manifest — run `kubectl apply --dry-run=client -f <file>` locally to catch errors before pushing
- Namespace mismatch — resource namespace in the YAML doesn't match the ArgoCD app's destination namespace
- CRD not yet installed — e.g., CNPG Cluster applied before the CNPG operator was ready

### `503 Service Unavailable` on the browser

```bash
# Check if the endpoint is populated (pod is matched by service selector)
kubectl get endpoints backstage -n backstage
# Should show an IP:port, not <none>

# Check the pod is actually running
kubectl get pods -n backstage

# Check the ingress is routing to the correct service and port
kubectl describe ingress backstage-ingress -n backstage
```

### SealedSecret not decrypting

```bash
kubectl describe sealedsecret backstage-db-credentials -n backstage
# Look at Events section for decryption errors
```

Common causes:
- The sealed secret was encrypted for a different cluster — you must re-seal using `kubeseal --fetch-cert` from the current cluster
- Controller name mismatch — verify with `kubectl get deployment -n kube-system | grep sealed`

---

## 17. Day-2 Operations

### Deploy a new version of Backstage

Push code to `main`. GitHub Actions will:
1. Run tests and lint
2. Build and scan the new Docker image
3. Push to Docker Hub
4. Update `manifest/backstage/backstage_deploy.yaml` with the new image SHA
5. ArgoCD detects the manifest change and rolls out the new pod

No manual steps are required after the initial setup.

### Scale the Backstage deployment

```bash
# Temporarily (will be reverted by ArgoCD selfHeal)
kubectl scale deployment backstage --replicas=3 -n backstage

# Permanently — edit manifest/backstage/backstage_deploy.yaml
# Change: replicas: 1 → replicas: 3
# Commit and push
```

### View live logs

```bash
kubectl logs -f deployment/backstage -n backstage
```

### Roll back to a previous version

In the ArgoCD UI, click the `backstage` app → **History and Rollback** → select a previous sync → **Rollback**.

Or via Git — revert the image tag change in `backstage_deploy.yaml` and push.

### Access the database directly

```bash
# Open a psql shell on the primary CNPG instance
kubectl exec -it backstage-db-1 -n backstage -- psql -U backstage -d backstage

# Run a query
\dt         # list tables
\q          # quit
```

### Force an ArgoCD sync

```bash
kubectl annotate application backstage -n argocd \
  argocd.argoproj.io/refresh=normal

# Or hard refresh (clears cache):
argocd app get backstage --refresh
```

### Update a cluster component (e.g. Cert-Manager)

Edit the Helm version in `plybk.yaml` and run:

```bash
cd Infra
bash manage.sh ansible
```

---

## 18. Security Considerations

### Secrets

- Database credentials are encrypted in Git using Sealed Secrets — the plaintext is never stored in the repository
- The `secret.yaml` template is gitignored — verified by `.gitignore` and enforced by team process
- The Sealed Secrets private key never leaves the cluster. If the cluster is destroyed, a new key is generated and all existing sealed secrets must be re-sealed
- Rotate the database password periodically by editing `secret.yaml`, re-running `seal-secret.sh`, and pushing the updated sealed file

### Container image security

- Every build is scanned by Trivy before the image is pushed to Docker Hub
- The pipeline is configured to fail on unfixed CRITICAL and HIGH severity CVEs in OS packages and libraries
- Images are tagged with the Git commit SHA — no mutable `latest` tags in production

### Network

- Backstage is exposed only via HTTPS (port 443). Port 80 only accepts Let's Encrypt challenges and immediately redirects to HTTPS
- Internal cluster communication stays within Kubernetes Services — Backstage connects to Postgres via the CNPG ClusterIP Service, never via an external address
- NGINX Ingress terminates TLS and forwards plain HTTP internally

### Kubernetes RBAC

- ArgoCD operates with least-privilege access scoped to the namespaces it manages
- The Sealed Secrets controller requires access to decrypt SealedSecrets cluster-wide but only creates Secrets in the namespaces where SealedSecrets are defined

---

## 19. File Reference

A complete reference of every file in the repository, its purpose, and whether it is committed to Git.

| File | Location | Purpose | Committed? |
|---|---|---|---|
| `gitops-app.yaml` | `.github/workflows/` | GitHub Actions CI/CD pipeline | ✅ Yes |
| `plybk.yaml` | `Infra/Ansible/` | Ansible playbook — installs all cluster components | ✅ Yes |
| `inventory.ini` | `Infra/Ansible/` | Ansible inventory — auto-generated by manage.sh | ❌ No (gitignored) |
| `main.tf` | `Infra/Terraform/` | Terraform — provisions EC2 nodes | ✅ Yes |
| `manage.sh` | `Infra/` | Orchestrates Terraform + Ansible | ✅ Yes |
| `backstage-namespace.yaml` | `manifest/backstage/` | Creates the backstage namespace | ✅ Yes |
| `backstage_deploy.yaml` | `manifest/backstage/` | Backstage Deployment (image tag updated by CI) | ✅ Yes |
| `backstage_svc.yaml` | `manifest/backstage/` | ClusterIP Service — routes to Backstage pod | ✅ Yes |
| `backstage-ingress.yaml` | `manifest/backstage/` | Ingress — routes kbucci.com to the Service | ✅ Yes |
| `cnpg-cluster.yaml` | `manifest/backstage/` | CloudNativePG Cluster — creates Postgres DB | ✅ Yes |
| `sealed-db-credentials.yaml` | `manifest/backstage/` | Encrypted DB credentials — generated by seal-secret.sh | ✅ Yes |
| `ingress-nginx-lb.yaml` | `manifest/ingress/` | LoadBalancer Service for NGINX Ingress | ✅ Yes |
| `metallb-config.yaml` | `manifest/metallb/` | MetalLB IPAddressPool + L2Advertisement | ✅ Yes |
| `letsencrypt.yaml` | `manifest/certmanager/` | ClusterIssuer for Let's Encrypt (prod + staging) | ✅ Yes |
| `argocd-apps.yaml` | repo root | Registers all 4 ArgoCD Applications — applied once manually | ✅ Yes |
| `seal-secret.sh` | repo root | Script to encrypt secret.yaml using kubeseal | ✅ Yes |
| `.gitignore` | repo root | Blocks sensitive files from being committed | ✅ Yes |
| `secret.yaml` | repo root (local only) | Plaintext DB password template — NEVER commit | ❌ No (gitignored) |
| `sealed-secrets-pub.pem` | local only | Sealed Secrets public cert — copied from cluster | ❌ No (gitignored) |
| `app-config.yaml` | repo root | Backstage base configuration | ✅ Yes |
| `app-config.production.yaml` | repo root | Backstage production overrides | ✅ Yes |
| `Dockerfile` | repo root | Builds the Backstage container image | ✅ Yes |
| `catalog-info.yaml` | repo root | Backstage catalog entry for this repository | ✅ Yes |
| `package.json` | repo root | Node.js workspace root — Yarn workspaces config | ✅ Yes |

---

*Maintained by KBUCCI Technologies. For questions or issues, open a GitHub Issue or contact the platform team.*
