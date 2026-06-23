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

| Job requirement | What's in this repo |
|---|---|
| Docker and Docker Compose | 3-tier app, built and tested locally with Compose first |
| Compose to Kubernetes migration | Converted with Kompose, then reviewed and fixed by hand (details below) |
| K3s experience | Real deployment, debugging, and one full incident recovery |
| Container hardening | Multi-stage Dockerfiles, non-root users, dropped Linux capabilities, K8s securityContext |
| Secrets management | A plaintext password introduced by the automated conversion, caught and replaced with a proper Secret |
| Network security | NetworkPolicy limiting database access to the API pod only, tested with live traffic |
| Deployment automation basics | Liveness/readiness probes and resource limits on every container |
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

Find your K3s node's IP with `kubectl get nodes -o wide` and open it in a browser.

## Secrets

`k8s/db-secret.yaml` is gitignored on purpose. A Kubernetes Secret is base64-encoded, not encrypted, so committing it as-is wouldn't really be safe, it would just look safe. Sealed Secrets are on the roadmap to fix this properly.

## Security hardening

- **Non-root containers.** API and database run as their real non-root UIDs (checked by hand, not guessed), enforced with `runAsNonRoot`.
- **Dropped capabilities.** Every container drops all Linux capabilities by default, then adds back only what it actually needs. Nginx needed `NET_BIND_SERVICE`, `CHOWN`, `SETUID`, and `SETGID` for its normal startup sequence (it binds port 80 as root, then drops to an unprivileged user). Dropping everything with no exceptions broke it on the first try, which was a good reminder that these controls need to be applied with some thought, not copy-pasted blindly.
- **Resource limits.** Every container has CPU and memory requests and limits.
- **Health probes.** Liveness and readiness checks on all three tiers, HTTP for frontend and API, a `pg_isready` exec probe for Postgres.
- **Network policy.** Only the API pod can reach the database on port 5432. Worth noting: K3s's default Flannel CNI doesn't enforce NetworkPolicy on its own, but K3s ships a separate kube-router-based controller that does, so this works out of the box without installing anything extra.

## Migrating from Compose to K3s

Kompose got most of the way there automatically, but it needed real review and fixes, not just a blind `kubectl apply`:

1. **Plaintext password.** Kompose resolved the `.env` variable from the Compose file at conversion time and wrote the actual password straight into the generated Deployment YAML. Caught this before it ever touched git history and replaced it with a Secret.
2. **Missing Services.** Kompose only creates a Service for containers that had a `ports:` block in the original Compose file. The API and database never needed one in Compose (they just used Docker's internal DNS), so Kompose skipped them. Added both manually.
3. **No registry yet.** Kompose assumes your images come from a registry. For now, images are built locally and imported straight into K3s with `imagePullPolicy: Never`. That changes once the CI/CD pipeline (Day 3) starts pushing to GHCR.

## One incident worth mentioning

Partway through, the K3s cluster started crash-looping after a WSL2 restart, failing an internal RBAC bootstrap step with a deliberately vague error message. Ruled out disk space and a corrupted datastore, then traced it to an outdated WSL2 kernel. Fixed with `wsl --update`, a clean K3s reinstall, and a kubeconfig refresh. Leaving this in the README because troubleshooting a real failure is at least as relevant to this role as anything that went smoothly.

## Roadmap

- CI/CD pipeline (GitHub Actions, mirrored in Azure DevOps and GitLab CI/CD) with SAST, dependency scanning, and image scanning
- Helm chart
- Sealed Secrets
- Cosign image signing
- SBOM generation
- Policy enforcement with OPA or Kyverno
- Staging and production namespaces with a real promotion flow
- A deployment to AKS to prove the cloud migration path

## Stack

Docker, Docker Compose, Kompose, Kubernetes, K3s, Traefik, PostgreSQL, Flask, Nginx
