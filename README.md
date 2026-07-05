# DevSecOps K3s Migration Demo

A three-tier application migrated from Docker Compose to K3s, with a fully automated CI/CD pipeline implementing real DevSecOps controls: secrets detection, SAST, container image scanning, supply-chain pinning, and cloud deployment via Terraform-provisioned infrastructure. Built as a portfolio project to demonstrate practical DevSecOps engineering, not just tooling familiarity.

## Architecture

```
Browser
   |
   v
Traefik Ingress (built into K3s)
   |
   v
frontend (Nginx, static HTML)
   |
   v   K8s Service DNS
api (Flask)
   |
   v   NetworkPolicy restricts this hop to api only
db (PostgreSQL 16)
```

All three tiers run as separate Deployments and Services on K3s. In CI/CD, the cluster is provisioned on a `t3.small` EC2 instance via Terraform, with the kubeconfig pushed to AWS Systems Manager Parameter Store so the pipeline can deploy without exposing the K3s API publicly during the build. Locally, the cluster runs in WSL2.

## What this project demonstrates

| Area | Implementation |
|---|---|
| Docker and Docker Compose | 3-tier app built and validated locally with Compose before migration |
| Compose to Kubernetes migration | Converted with Kompose, then reviewed and corrected by hand |
| K3s | Full deployment, debugging, and incident recovery on a real cluster |
| Cloud deployment | EC2 provisioned per pipeline run via Terraform, destroyed after demo |
| CI/CD pipeline | GitHub Actions: secrets scan → SAST → build → image scan → deploy |
| Container hardening | Multi-stage Dockerfiles, non-root users, dropped Linux capabilities, K8s `securityContext` |
| Secrets management | Pipeline-injected Kubernetes Secrets from GitHub Secrets, never committed to git |
| Network security | NetworkPolicy restricting database access to the API pod only, enforced by K3s's embedded kube-router controller |
| Supply-chain security | All GitHub Actions pinned to immutable 40-character commit SHAs |
| Deployment automation | Liveness/readiness probes and resource requests/limits on every container |
| Troubleshooting | Real K3s cluster failures diagnosed and resolved (see below) |

## CI/CD Pipeline

The pipeline runs on every push to `main` and every pull request. Stages run sequentially, each gating the next.

```
detect-secrets (Gitleaks)
       |
      sast (Semgrep)
       |
  build-and-push (Docker → GHCR)
       |
   scan-images (Trivy × 3)
       |
     deploy (Terraform + kubectl)
       |
   tighten (close K3s API port)
```

The deploy job provisions a fresh EC2 instance (or reuses an existing one) via Terraform, waits for K3s to finish booting, verifies the kubeconfig IP matches the new instance before attempting any connection, creates the database Secret from a GitHub Secret, then applies the Kubernetes manifests. The K3s API port (6443) is opened to `0.0.0.0/0` only for the duration of this step, then immediately tightened back to closed by a final step that runs with `if: always()`, meaning it runs even if the deploy itself fails.

Images are tagged with both `:latest` and the exact commit SHA, tying every deployed artifact to a specific, auditable point in git history.

## Infrastructure

The cloud cluster is entirely Terraform-managed: EC2 instance, security group, IAM role (scoped to only write the kubeconfig to a single SSM Parameter Store path), and instance profile. State is stored in S3 so both local runs and the pipeline share the same view of what exists.

The boot script installs the AWS CLI, K3s (with a few control-plane flags tuned for a resource-constrained instance), and the Sealed Secrets controller via Helm. It then pushes the kubeconfig to Parameter Store using IMDSv2 for metadata retrieval, substituting the public IP into the kubeconfig before pushing so external tools can actually use it.

The instance is intended to be short-lived: provisioned for a demo or pipeline run, then destroyed. This is by design, not a limitation. It does mean some tooling choices that work well for long-lived clusters (notably Sealed Secrets) were deliberately not used here.

## Secrets management

The database password lives in a GitHub Secret and is injected as a Kubernetes Secret by the pipeline at deploy time. It is never written to any file in this repository and is not present anywhere in git history.

This means it has to be recreated on every fresh cluster, which is a real tradeoff of the ephemeral infrastructure pattern. Sealed Secrets was evaluated as an alternative but rejected for this specific setup: Sealed Secrets encrypts with the controller's public key, and the private key is generated fresh each time the controller starts in a new cluster. Every destroy-and-recreate cycle would require re-sealing all secrets, which negates the benefit in an ephemeral context. Sealed Secrets is the right tool when clusters are long-lived (Argo CD, Flux, production GitOps workflows). The decision to use GitHub Secrets instead is documented here rather than left implicit.

## Security hardening

**Container hardening.** API and database containers run as verified non-root UIDs (confirmed by inspecting the image, not assumed from the Dockerfile). All Linux capabilities are dropped by default, with only what each container actually needs added back. Nginx is the interesting case: its master process must start as root to bind port 80, then drops to an unprivileged user internally, so `runAsNonRoot` cannot be enforced at the pod level without breaking startup. The capabilities it needs (`NET_BIND_SERVICE`, `CHOWN`, `SETUID`, `SETGID`) are added back explicitly, everything else stays dropped.

**Postgres volume permissions.** K3s uses `local-path-provisioner` for storage, which backs volumes with plain `hostPath` directories on the node. The `fsGroup` setting in Kubernetes `securityContext` does not apply to `hostPath` volumes, a known limitation. An init container running as root is used to `chown` the data directory before the main Postgres container starts, so Postgres can initialize correctly without running as root itself.

**NetworkPolicy.** Only the API pod can reach the database on port 5432. K3s's default CNI (Flannel) does not enforce NetworkPolicy itself, but K3s ships a separate kube-router-based controller that does, so policies are enforced out of the box. Verified with live traffic tests.

**Supply-chain pinning.** All `uses:` references in the GitHub Actions workflow are pinned to full 40-character commit SHAs rather than mutable version tags. This prevents a compromised or modified upstream action from silently affecting the pipeline. The human-readable tag is preserved as a comment alongside each SHA.

**K3s API exposure.** The K3s API port (6443) is closed by default in the EC2 security group (`127.0.0.1/32`). The deploy job opens it to `0.0.0.0/0` only for the duration of the deployment step, then tightens it back regardless of whether the deploy succeeded or failed. This is a deliberate tradeoff: GitHub's hosted runners publish hundreds of IPv4 ranges that exceed AWS's per-security-group rule limit, making per-range allowlisting impractical. The API is still protected by client certificate authentication via the kubeconfig, which is the actual access control. The open window is bounded and documented, not overlooked.

**Resource limits.** Every container has CPU and memory requests and limits. On a `t3.small` instance, K3s's control plane itself consumes a significant portion of available CPU at steady state (the documented minimum for a K3s server node is 2 cores and 2 GB RAM). This is noted honestly rather than glossed over.

## Security findings from the pipeline

Running real scanners against real code and real base images surfaced genuine findings. Each one is documented here because triaging findings properly is the actual skill being demonstrated, not just having green checkmarks.

### Semgrep (SAST)

**`python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host`**
Flagged `app.run(host="0.0.0.0")` in the Flask API. Assessed as a false positive in context: the container runs in its own isolated pod network namespace, and binding to all interfaces is required for the Kubernetes Service to reach it. Suppressed inline with a `nosemgrep` comment and written explanation.

**`yaml.kubernetes.security.run-as-non-root.run-as-non-root`**
Flagged `frontend-deployment.yaml` for not setting `runAsNonRoot` at the pod level. Intentional: Nginx's master process must start as root to bind port 80. Forcing `runAsNonRoot` would prevent the pod from starting. Excluded at the pipeline level with `--exclude-rule`. The Semgrep rule's match location made an inline YAML comment impractical, so the rationale is documented here instead.

**`github-actions-mutable-action-tag`**
Flagged all `uses:` references using version tags instead of commit SHAs. Fixed by pinning every action to its full SHA. This is a real supply-chain control, not just a Semgrep compliance checkbox.

### Trivy (container image scanning)

Three images are scanned. Each needed a different response, which is the point.

**API image (`python:3.12-slim`):** 11 findings in OS-level packages bundled by Debian (perl, ncurses, sqlite) that the application never uses. All have Trivy status `affected` or `fix_deferred`, meaning no upstream patch exists yet. Handled with `ignore-unfixed: true`, which passes the gate while still blocking on anything that does have a fix. Switching to Alpine was considered and rejected: `psycopg2-binary` ships glibc-only wheels, making Alpine builds slower and more fragile for no real security gain.

**Frontend image (`nginx:1.27-alpine`):** 33 findings (OpenSSL, libxml2, libpng, zlib, and others), all with status `fixed` and real fixed versions available. The base image was simply behind on Alpine package updates. Fixed with `RUN apk update && apk upgrade --no-cache` in the Dockerfile, pulling current patched packages at build time. Result: clean scan.

**Database image (`postgres:16-alpine`):** 16 findings in the Go standard library bundled by the image's upstream maintainers, including a CRITICAL TLS bug. These cannot be fixed with `apk upgrade` (the Go runtime is not an Alpine package), and there is no custom Dockerfile to patch since this is the official unmodified image. Marked `continue-on-error: true`: findings are visible in CI output but do not block deploys, because blocking indefinitely on something we cannot build or patch is not a meaningful gate. Tracked as a known, accepted risk pending an upstream rebuild.

### Gitleaks (secrets detection)

No findings. The database password was never committed to git at any point, not even temporarily, which is exactly what Gitleaks is designed to verify.

## Migrating from Compose to K3s

Kompose handles the mechanical conversion, but the output needs real review before applying.

1. **Plaintext password.** Kompose resolved the `.env` variable at conversion time and wrote the actual password into the generated Deployment YAML. Caught before the first commit and replaced with a Kubernetes Secret.
2. **Missing Services.** Kompose only creates a Service for containers with a `ports:` block. The API and database used Docker's internal DNS in Compose and had no explicit ports, so Kompose skipped their Services entirely. Both were added manually.
3. **Image pull policy.** Kompose assumes images come from a registry. Local images were imported directly into K3s's containerd store with `imagePullPolicy: Never` during initial testing. In the full pipeline, images are built and pushed to GHCR, and the manifests reference those registry images.

## Incidents and non-obvious decisions

**K3s crash-loop on WSL2 restart.** Partway through development, K3s entered a crash-loop after a WSL2 restart, failing an internal RBAC bootstrap step with a vague error message. Ruled out disk space and datastore corruption. Root cause was an outdated WSL2 kernel. Fixed with `wsl --update`, a clean K3s reinstall, and a kubeconfig refresh.

**CPU credit exhaustion on `t3.micro`.** Initial testing used a free-tier `t3.micro` (1 vCPU, 1 GB RAM). K3s's own control plane consumed roughly 75% CPU at steady state, well above the burstable instance's sustainable baseline. CPU credits drained over extended testing sessions, causing SSM agent hibernation and kubectl commands queuing indefinitely. Switched to `t3.small` (2 vCPU, 2 GB RAM), which matches K3s's documented minimum server requirements.

**Sealed Secrets and ephemeral clusters.** Sealed Secrets was implemented, committed, and then removed. The controller generates a new key pair on every fresh install. With a destroy-and-recreate deployment pattern, every sealed secret becomes permanently undecryptable after each cluster rebuild. The right tool for the right context: Sealed Secrets works well with long-lived clusters and GitOps controllers like Argo CD or Flux. It was replaced with pipeline-injected secrets from GitHub Secrets, which suits the ephemeral infrastructure model.

**`hostPath` volumes and `fsGroup`.** The Kubernetes `fsGroup` security context setting does not apply to `hostPath`-backed volumes, which is what K3s's `local-path-provisioner` uses. Postgres's init process needs to `chown` its data directory and fails with `Operation not permitted` when run as a non-root user against a root-owned directory. Solved with an init container that runs as root, fixes the directory ownership, then exits before the main Postgres container starts.

## Planned additions

- Cosign image signing
- SBOM generation via `trivy sbom`
- Helm chart packaging
- OIDC federation for AWS authentication (replacing long-lived access keys in GitHub Secrets)
- OPA or Kyverno admission policy enforcement
- Staging and production namespace promotion flow

## Stack

Docker, Docker Compose, Kompose, Kubernetes, K3s, Traefik, PostgreSQL 16, Flask, Nginx, GitHub Actions, GHCR, Gitleaks, Semgrep, Trivy, Terraform, AWS EC2, AWS SSM Parameter Store, Helm, Sealed Secrets (evaluated, not used in final implementation)
