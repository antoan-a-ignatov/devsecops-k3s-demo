# DevSecOps K3s Migration Demo

A small multi-tier app, migrated from Docker Compose to K3s, built to show practical DevSecOps work: containerization, orchestration, secrets handling, and security-hardened deployments.

This is a work in progress. CI/CD pipelines and more security tooling (SAST, image scanning, signing) are being added over the next few days. See the Roadmap section for what's coming.

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

All three tiers run as separate Deployments and Services on a single-node K3s cluster (WSL2/Ubuntu). The database password comes from a Kubernetes Secret, not a hardcoded value.

## What this project shows

| Skill/Technology | What's in this repo |
|---|---|
| Docker and Docker Compose | 3-tier app, built and tested locally with Compose first |
| Compose to Kubernetes migration | Converted with Kompose, then reviewed and fixed by hand (details below) |
| K3s | Real deployment, debugging, and one full incident recovery |
| Container hardening | Multi-stage Dockerfiles, non-root users, dropped Linux capabilities, K8s securityContext |
| Secrets management | A plaintext password introduced by the automated conversion, caught and replaced with a proper Secret |
| Network security | NetworkPolicy limiting database access to the API pod only, tested with live traffic |
| Deployment automation basics | Liveness/readiness probes and resource limits on every container |
| CI/CD security gates | Gitleaks, Semgrep, and Trivy as real pipeline gates, with documented triage of every finding |
| Troubleshooting | A real K3s cluster failure, diagnosed and fixed (see below) |

## Quick start

You'll need a K3s cluster, kubectl, and Docker.

```bash
# build the images
docker build -t api:latest ./app/api
docker build -t frontend:latest ./app/frontend

# import into K3s's containerd store (no registry yet, that's coming with the CI/CD pipeline)
docker save -o api.tar api:latest && sudo k3s ctr images import api.tar
docker save -o frontend.tar frontend:latest && sudo k3s ctr images import frontend.tar
rm api.tar frontend.tar

# create the db secret (not committed to the repo, see Secrets section)
kubectl create secret generic db-credentials \
  --from-literal=DB_PASSWORD='your-password-here' \
  --dry-run=client -o yaml | kubectl apply -f -

# deploy
kubectl apply -f k8s/

# check it's up
kubectl get pods
kubectl get ingress
```

Find K3s node's IP with `kubectl get nodes -o wide` and open it in a browser.

## Secrets

`k8s/db-secret.yaml` is gitignored on purpose. A Kubernetes Secret is base64-encoded, not encrypted, so committing it as-is wouldn't really be safe, it would just look safe. Sealed Secrets are on the roadmap to fix this properly.

## Security hardening

- **Non-root containers.** API and database run as their real non-root UIDs (checked by hand), enforced with `runAsNonRoot`.
- **CI exception, documented.** Semgrep's `run-as-non-root` rule flags `frontend-deployment.yaml` for not setting `runAsNonRoot` at the pod level. This is excluded in the CI pipeline (`--exclude-rule`) rather than fixed, because it's correct as-is, see the Nginx startup explanation above. Documented here since Semgrep's exact match line made an inline YAML comment impractical.
- **Dropped capabilities.** Every container drops all Linux capabilities by default, then adds back only what it actually needs. Nginx needs `NET_BIND_SERVICE`, `CHOWN`, `SETUID`, and `SETGID` for its normal startup sequence (it binds port 80 as root, then drops to an unprivileged user). Dropping everything with no exceptions broke it on the first try, which was a good reminder that these controls need to be applied per container.
- **Resource limits.** Every container has CPU and memory requests and limits.
- **Health probes.** Liveness and readiness checks on all three tiers, HTTP for frontend and API, a `pg_isready` exec probe for Postgres.
- **Network policy.** Only the API pod can reach the database on port 5432. Worth noting: K3s's default Flannel CNI doesn't enforce NetworkPolicy on its own, but K3s ships a separate kube-router-based controller that does, so this works out of the box without installing anything.

## Security findings from the pipeline, and how each was handled

Running real scanners against real code and real base images surfaced genuine findings. Each one is documented here rather than quietly fixed or suppressed, since triaging findings properly is the actual point of a DevSecOps pipeline, not just having green checkmarks.

### Semgrep (SAST)

**Finding: `python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host`**
Flagged `app.run(host="0.0.0.0", port=5000)` in the Flask API. This rule exists because binding to all interfaces can over-expose an app on a shared host. Assessed as a false positive in this specific context: the container runs in its own isolated Kubernetes pod network namespace, not a shared host, and binding to `0.0.0.0` is required for the Service/Ingress to reach the container at all. Suppressed inline with a `nosemgrep` comment and a written explanation directly above the line in `app.py`.

**Finding: `yaml.kubernetes.security.run-as-non-root.run-as-non-root`**
Flagged `frontend-deployment.yaml` for not setting `runAsNonRoot` at the pod level. This is correct as written and intentional: the official `nginx:alpine` image's master process must start as root to bind port 80 (a privileged port), then drops to the unprivileged `nginx` user internally on its own. Forcing `runAsNonRoot: true` here would prevent the pod from starting at all. Excluded at the pipeline level with `--exclude-rule` in the Semgrep CI step, since the rule's match location made an inline comment impractical, documented here instead.

### Trivy (container image scanning)

Three images are scanned, and each one needed a different response, which is itself worth noting: there's no single correct way to handle a CVE finding, the right move depends entirely on the finding's actual status.

**API image (python:3.12-slim)**: 11 findings, all in OS-level packages the application doesn't use directly (perl-base, libncursesw6, libsqlite3-0, ncurses), bundled by Debian regardless of what the app needs. Every finding had a Trivy status of `affected` or `fix_deferred`, meaning no patched version exists yet anywhere upstream. Handled with Trivy's `ignore-unfixed: true` flag, which filters out findings with no available fix while still gating on anything that does have one. Switching to Alpine to avoid these packages entirely was considered and rejected: psycopg2-binary ships glibc-only wheels, and Alpine's musl libc would likely force a slower, more fragile build from source for no real security gain.

**Frontend image (nginx:1.27-alpine)**: 33 findings (OpenSSL, libxml2, libpng, zlib, musl, and others), all with Trivy status `fixed` and real fixed versions listed. This meant the base image itself was simply out of date relative to currently available Alpine packages. Fixed by adding `RUN apk update && apk upgrade --no-cache` to the Dockerfile, pulling current patched packages at build time instead of relying on whatever was frozen into the image at publish time. Result: clean scan, zero findings.

**Database image (postgres:16-alpine, official, unmodified)**: 16 findings, all in the Go standard library bundled inside the image by its upstream maintainers (crypto/tls, net/url, crypto/x509), including one CRITICAL TLS certificate validation bug. Unlike the other two images, these can't be fixed with apk upgrade (the Go runtime isn't an Alpine package) and there's no Dockerfile of our own to patch, since this is the official image used as-is. The postgres:16-alpine tag is actively maintained and rebuilt regularly, so this isn't a case of using a stale tag, it's simply how current the bundled Go toolchain is right now upstream. Marked `continue-on-error: true` in the pipeline: findings are scanned and visible in CI output, but don't block deploys, since blocking indefinitely on something neither buildable nor patchable by us isn't a meaningful gate. This is tracked as a known, accepted, monitored risk pending an upstream image update, not an oversight.

### Gitleaks (secrets detection)

No findings. Worth stating explicitly rather than leaving silent: the database password was deliberately never committed to git history at any point, it exists only in a gitignored .env file locally and as a Kubernetes Secret in the cluster, which is exactly the scenario Gitleaks is designed to verify.

## Migrating from Compose to K3s

Kompose got most of the way there automatically, but it needed review and fixes, not just a blind `kubectl apply`:

1. **Plaintext password.** Kompose resolved the `.env` variable from the Compose file at conversion time and wrote the actual password straight into the generated Deployment YAML. Caught this immediately and replaced it with a Secret.
2. **Missing Services.** Kompose only creates a Service for containers that had a `ports:` block in the original Compose file. The API and database never needed one in Compose (they just used Docker's internal DNS), so Kompose skipped them. Added both manually.
3. **No registry yet.** Kompose assumes your images come from a registry. For now, images are built locally and imported straight into K3s with `imagePullPolicy: Never`. That changes once the CI/CD pipeline starts pushing to GHCR.

## One incident worth mentioning

Partway through, the K3s cluster started crash-looping after a WSL2 restart, failing an internal RBAC bootstrap step with a deliberately vague error message. Ruled out disk space and a corrupted datastore, then traced it to an outdated WSL2 kernel. Fixed with `wsl --update`, a clean K3s reinstall, and a kubeconfig refresh.

## Roadmap

- CI/CD pipeline (GitHub Actions, mirrored in Azure DevOps and GitLab CI/CD) with SAST, dependency scanning, and image scanning
- Helm chart
- Sealed Secrets
- Cosign image signing
- SBOM generation
- Policy enforcement with OPA or Kyverno
- Staging and production namespaces with a real promotion flow
- A deployment to AKS to prove the cloud migration path

## Stack (so far)

Docker, Docker Compose, Kompose, Kubernetes, K3s, Traefik, PostgreSQL, Flask, Nginx, GitHub Actions, GHCR, Gitleaks, Semgrep, Trivy
