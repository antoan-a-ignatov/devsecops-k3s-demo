# DevSecOps K3s Migration Demo

## Project Status

[![Build Status](https://img.shields.io/github/actions/workflow/status/antoan-a-ignatov/devsecops-k3s-demo/ci.yml?style=flat-square&label=Build)](https://github.com/antoan-a-ignatov/devsecops-k3s-demo/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/antoan-a-ignatov/devsecops-k3s-demo?style=flat-square)](https://github.com/antoan-a-ignatov/devsecops-k3s-demo/releases) [![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/) [![K3s](https://img.shields.io/badge/K3s-FF6C37?style=flat-square&logo=kubernetes&logoColor=white)](https://k3s.io/) [![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform) [![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white)](https://docs.github.com/actions) [![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat-square&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
* **Current Version:** v1.3.0
* **Status:** Functional cloud deployment complete
* **Last Improvements:** GitHub OIDC Federation; IAM Permissions Boundary; commit-SHA deployments; read-only CI identity layer

<img src="docs/images/frontend.png" width="347">

<img src="docs/images/api-health.png" width="347">


## Introduction
This project demonstrates the migration of an application from Docker Compose to Kubernetes (K3s) while applying modern DevSecOps practices: infrastructure as code, automated security scanning, supply-chain hardening, and cloud-native deployment. The architecture consists of a three-tier application migrated from Docker Compose to K3s. The CI/CD pipeline enforces real DevSecOps controls at every stage: secrets detection and SAST, then container image scanning and supply-chain pinning, then OIDC-federated cloud authentication and Terraform-provisioned deployment.

## Table of Contents
1. [Skills Demonstrated](#skills-demonstrated)
2. [Architecture](#architecture)
3. [Repository Structure](#repository-structure)
4. [Docker Compose to K3s Migration](#docker-compose-to-k3s-migration)
5. [Technology Stack](#technology-stack)
6. [Infrastructure](#infrastructure)
7. [CI/CD Pipeline](#cicd-pipeline)
8. [Security](#security)
9. [Engineering Challenges and Design Decisions](#engineering-challenges-and-design-decisions)
10. [Planned Improvements](#planned-improvements)

## Skills Demonstrated

| Area | Implementation |
| :--- | :--- |
| Docker and Docker Compose | Three-tier application built and validated locally with Compose before migration |
| Compose to Kubernetes migration | Converted with Kompose, then reviewed and corrected manually by hand |
| K3s | Full deployment, debugging, and incident recovery on a real cluster |
| Cloud deployment | EC2 instance provisioned per pipeline run via Terraform, destroyed after demo completion |
| CI/CD pipeline | GitHub Actions orchestrating a sequential flow from secrets scanning and SAST to build, image scanning, and deployment |
| Container hardening | Multi-stage Dockerfiles, non-root users, dropped Linux capabilities, and Kubernetes securityContext configurations |
| Secrets management | Pipeline-injected Kubernetes Secrets from GitHub Secrets; CI-to-AWS authentication via GitHub OIDC federation, no long-lived AWS credentials stored in the repository or in GitHub |
| Network security | NetworkPolicy restricting database access to the API pod only, enforced by the K3s embedded kube-router controller |
| Supply-chain security | All GitHub Actions pinned to immutable 40-character commit SHAs |
| Deployment automation | Liveness and readiness probes along with resource requests and limits applied to every container |
| Troubleshooting | Real K3s cluster failures diagnosed and resolved systematically |

## Architecture
All three tiers run as separate Deployments and Services on K3s. In the CI/CD environment, the cluster is provisioned on a t3.small EC2 instance via Terraform. The kubeconfig is pushed to AWS Systems Manager Parameter Store so the pipeline can retrieve it without SSH access; the K3s API port is only opened for the duration of the deploy step (see Security). Locally, the cluster runs within WSL2.

```mermaid
flowchart TD

    DEV[Developer]

    DEV -->|Push| GITHUB[GitHub Repository]

    GITHUB -->|Trigger| GHA[GitHub Actions]

    subgraph PIPELINE["Pipeline stages, run in sequence"]
        GITLEAKS[Gitleaks] --> SEMGREP[Semgrep] --> BUILD[Build and push images] --> TRIVY[Trivy image scan] --> DEPLOY[Deploy]
    end

    GHA --> GITLEAKS

    BUILD -->|Push| GHCR[GitHub Container Registry]
    TRIVY -.->|Pull and scan| GHCR

    DEPLOY -->|OIDC token| STS[AWS STS]
    STS -->|Temporary credentials| DEPLOY
    DEPLOY -->|terraform apply| TF[Terraform]

    TF --> EC2[AWS EC2 Instance]
    EC2 --> K3S[K3s Cluster]

    EC2 -->|Write kubeconfig| SSM[SSM Parameter Store]
    DEPLOY -->|Read kubeconfig| SSM
    DEPLOY -->|kubectl apply| K3S

    GHCR -->|Pull Images| K3S

    subgraph CLUSTER["K3s Cluster"]
        TRAEFIK[Traefik Ingress]
        FRONTEND[Frontend]
        API[API]
        DB[(PostgreSQL)]
    end

    INTERNET((Internet)) --> TRAEFIK

    TRAEFIK --> FRONTEND
    TRAEFIK --> API

    API --> DB
```

## Repository Structure
The project repository uses the following directory layout:

```text
.
├── .github/
│   └── workflows/          # GitHub Actions CI/CD pipeline
├── app/                    # Application source code
├── docs/
│   └── images/             # README screenshots and diagrams
├── k8s/                    # Kubernetes manifests
├── terraform/              # Infrastructure as Code
├── .gitignore
├── docker-compose.yml      # Original Docker Compose deployment
└── README.md
```

## Docker Compose to K3s Migration
While Kompose handles the mechanical conversion process, the generated output required human review and manual corrections before deployment:

1. **Plaintext Password Exposure:** Kompose resolved the environment variables at conversion time and wrote the actual plaintext password into the generated Deployment manifest. This was caught before the first commit and replaced with a proper Kubernetes Secret reference.
2. **Missing Kubernetes Services:** Kompose only creates a Service for containers that contain an explicit ports block. The API and database tiers relied on internal Docker DNS within Compose and lacked explicit ports, causing Kompose to skip Service generation entirely. These Services were added manually.
3. **Image Pull Policy Adjustments:** Kompose assumes images always originate from a remote registry. Local images were imported directly into the containerd store of K3s using imagePullPolicy: Never during early local testing. In the automated pipeline, images are built, pushed to GHCR, and the production manifests reference those registry images.

## Technology Stack

### Technologies Used
* **Containerization and Orchestration:** Docker, Docker Compose, Kompose, Kubernetes, K3s
* **Ingress and Networking:** Traefik
* **Application and Database:** Flask, Nginx, PostgreSQL 16
* **CI/CD and Automation:** GitHub Actions
* **Security Scanning:** Gitleaks, Semgrep, Trivy
* **Infrastructure as Code:** Terraform
* **Cloud Platform:** AWS (EC2, S3, IAM OIDC Federation, IAM Permissions Boundaries, Systems Manager Parameter Store)
* **Container Registry:** GitHub Container Registry (GHCR)

### Technologies Evaluated
* **Sealed Secrets:** Evaluated and implemented during development, but deliberately excluded from the final production architecture due to the ephemeral nature of the cluster.

## Infrastructure
The cloud cluster is completely managed via Terraform, including the EC2 instance, security groups, IAM roles, and instance profiles. The instance's IAM role is limited to writing the kubeconfig to a single AWS Systems Manager Parameter Store path, plus the AWS-managed `AmazonSSMManagedInstanceCore` policy, and is capped by a permissions boundary (see Hardening). State is stored in an S3 bucket so that local runs and the pipeline maintain a unified view of the active infrastructure.

The automated boot script performs the following tasks:
* Installs the AWS CLI and K3s (with control-plane flags tuned for resource-constrained environments).
* Pushes the kubeconfig to Parameter Store using IMDSv2 for metadata retrieval. The instance enforces IMDSv2 (`http_tokens = "required"`), so the older token-less metadata API is disabled.
* Substitutes the public IP into the kubeconfig before uploading so external automated tools can establish a connection.

The instance is short-lived by design, provisioned for a demo or a pipeline run and then destroyed by hand afterwards; the pipeline does not tear it down.

![Application](docs/images/instance.png)
![Application](docs/images/instance-monitoring.png)
![Application](docs/images/instance-kubectl.png)

## CI/CD Pipeline
The pipeline triggers on every push to main and every pull request; the `deploy` job only runs for pushes to `main`. Stages execute sequentially, with each stage acting as a quality gate for the next. 

The deployment job provisions a fresh EC2 instance or reuses an existing one via Terraform, waits for K3s to finish booting, and verifies that the kubeconfig IP matches the new instance before attempting a connection. It then creates the database Secret from a GitHub Secret and applies the Kubernetes manifests. 

Authentication to AWS uses GitHub's OIDC provider rather than static credentials: the `deploy` job requests a short-lived identity token (`permissions: id-token: write`), which GitHub exchanges with AWS STS for temporary credentials scoped to a single IAM role. No AWS access key ever exists in this repository.

The K3s API port (6443) is opened to all traffic exclusively for the duration of this step. It is immediately closed by a final cleanup step running with an absolute execution rule, ensuring security enforcement even if the deployment fails. Images are tagged with both the latest tag and the exact commit SHA. The deploy step substitutes the commit SHA for `latest` in a temporary copy of the manifests before applying them, and fails if any `latest` reference to the API or frontend images remains, so every deployment runs a specific build that can be traced to a commit in git history.

![Application](docs/images/github-action.png)

## Security

### Security Architecture
* **Network Isolation:** A NetworkPolicy restricts database access to the API pod only, so a compromise of any other pod cannot reach the database directly. It is enforced natively out of the box by the embedded kube-router controller in K3s and validated via live traffic testing.
* **API Exposure Mitigation:** The K3s API port (6443) is closed by default in the AWS security group. The deployment job opens access to all traffic only during the deployment step, tightening it down immediately afterward. This approach addresses the limitation where GitHub hosted runner IP ranges exceed AWS security group rule limits. While the port is open, the API still requires client certificate authentication via the kubeconfig, which serves as the actual access control.

### Hardening
* **Privilege Escalation Prevention:** Application containers utilize explicit `securityContext` configurations to prevent privilege escalation. API and database containers run as verified non-root UIDs, which was confirmed by direct image inspection. All Linux capabilities are dropped by default, and only essential ones are added back.
* **Nginx Special Handling:** The Nginx master process must start as root to bind to port 80 before dropping privileges internally. This prevents the enforcement of a pod-level non-root requirement during startup. To maintain security, necessary capabilities (NET_BIND_SERVICE, CHOWN, SETUID, SETGID) are explicitly added back, while all other capabilities remain dropped.
* **Postgres Volume Access:** K3s uses local-path-provisioner, backing volumes with plain hostPath directories on the node. Because the fsGroup setting does not apply to hostPath volumes, a root-owned directory causes Postgres initialization to fail. An init container running as root modifies the directory ownership via chown before the main Postgres container starts, allowing Postgres to run securely as a non-root user.
* **Supply-Chain Hardening:** All actions within the GitHub Actions workflow are pinned to immutable 40-character commit SHAs instead of mutable tags, preventing untrusted upstream modifications from compromising the pipeline. Human-readable tags are preserved alongside the SHAs as comments.
* **Resource Constraints:** Every container is configured with explicit CPU and memory requests and limits to ensure stability and prevent resource exhaustion on the cluster.
* **CI Identity Least Privilege:** The GitHub Actions OIDC role's IAM policy is scoped to what the pipeline needs. S3 state access, SSM parameter access, and IAM role/instance-profile management are constrained to exact resource ARNs, and IAM write access is limited by exact name to the single instance role and instance profile this project creates. The identity layer itself (the CI role, the OIDC provider, and the permissions boundary policy) is read-only for the pipeline, so CI cannot edit its own permissions or raise the boundary that constrains the instance role; changes to those are applied by an administrator from a local machine. `iam:AttachRolePolicy`/`DetachRolePolicy` is further restricted with a `Condition` to the single managed policy this project actually uses (`AmazonSSMManagedInstanceCore`), and `iam:PassRole` is restricted to the EC2 service only; both close specific, nameable privilege-escalation paths (attaching a broader policy to a role it created, or passing that role to an unintended service). EC2 actions (`RunInstances`, `CreateSecurityGroup`, etc.) remain unscoped by resource (`Resource: "*"`). This is an accepted simplification for a single-purpose demo account, not an AWS limitation: tag-based conditions can narrow these actions and are listed under Planned Improvements.
* **IAM Permissions Boundary:** `k3s-demo-instance-role` carries a boundary scoped to the `ssm`, `ec2messages`, and `ssmmessages` action families, capping its effective permissions regardless of what gets attached or inlined onto it later. AWS computes effective access as the intersection of a role's policy and its boundary, never the union. `iam:CreateRole` is condition-scoped so the instance role can only be created with the same boundary attached, and the pipeline has no write access to the boundary policy itself (see CI Identity Least Privilege). Verified with the AWS IAM Policy Simulator, not just a green pipeline: an intentionally broad inline policy (`s3:*`) was attached via `iam:PutRolePolicy` (which succeeds, as expected: that action was never restricted) and confirmed to evaluate as `implicitDeny` via `simulate-principal-policy`, showing that the boundary constrains effective access.

### Secrets Management
The database password is kept securely as a GitHub Secret and injected directly as a Kubernetes Secret by the pipeline during deployment. It is never written to disk within the repository or exposed in git history. This model introduces a trade-off: the secret must be re-created in each new cluster by the pipeline, a consequence of the ephemeral infrastructure pattern.

CI-to-AWS authentication originally used a long-lived IAM user's access keys, stored as GitHub Secrets. That user was created manually in the AWS console before any Terraform infrastructure existed, has `AdministratorAccess` attached via an IAM group, and was never tracked in this repo's Terraform state, entirely out-of-band from the rest of the project's IaC-managed identities.

This was replaced with GitHub OIDC federation: an IAM OIDC identity provider and a purpose-built IAM role (`k3s-demo-github-actions-deploy`), both defined in `terraform/oidc.tf`. The role's trust policy is scoped to this exact repository and the `main` branch via the GitHub OIDC token's `sub` claim, so a pull-request-triggered run cannot assume it. The role ARN itself is stored as a GitHub repository *Variable*.

### Pipeline Findings
Running active security scanners against the application code, Kubernetes manifests, GitHub Actions workflows, and container images surfaced genuine findings which were investigated, documented, and either remediated or accepted based on their impact and the project's goals.

#### Semgrep (SAST)
* `python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host`: Flagged the use of `app.run(host="0.0.0.0")` in the Flask API. This was assessed as a false positive in this specific environment, as the container operates in an isolated pod network namespace and binding to all interfaces is required for the Kubernetes Service to route traffic to it. This finding is suppressed inline with a `nosemgrep` comment and a documented explanation.
* `yaml.kubernetes.security.run-as-non-root.run-as-non-root`: Flagged `frontend-deployment.yaml` for missing a pod-level non-root setting. This is intentional, as the Nginx master process requires root access to bind port 80. This rule is excluded at the pipeline level using `--exclude-rule`, with the rationale documented here due to YAML syntax layout constraints.
* `github-actions-mutable-action-tag`: Flagged actions using mutable version tags. This was resolved by pinning all actions to their definitive commit SHAs.
* `terraform.lang.security.iam.no-iam-data-exfiltration`: Flagged the S3 state-access actions (`GetObject`, `PutObject`, `ListBucket`) in the OIDC role's policy. False positive: the rule checks for the presence of these actions without correlating them against the `Resource` block, which is scoped to the exact state bucket ARN, not `"*"`. Suppressed inline with `nosemgrep`.
* `terraform.lang.security.iam.no-iam-priv-esc-funcs` and `terraform.lang.security.iam.no-iam-resource-exposure`: Flagged every IAM role/policy management action in the OIDC role's policy (`CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `PassRole`, and related actions needed to manage the instance role and its instance profile). These rules fire on the presence of these action strings categorically; they don't evaluate whether a `Condition` block mitigates the risk. Genuinely mitigated where AWS's IAM condition keys allow it (see Hardening, above); suppressed inline where the rule's pattern-matching can't see that mitigation. The suppressions use a bare `nosemgrep` with an explanatory comment above each one. A bare `nosemgrep` silences every rule on that line, including any added later, so switching to rule-specific IDs would be more precise and is a cleanup to revisit.
* **IAM findings on the Permissions Boundary:** Adding the boundary policy surfaced the same category of finding as the original OIDC work: `no-iam-data-exfiltration` and `no-iam-resource-exposure` fired on the boundary's service-level wildcard actions (`ssm:*`, `ec2messages:*`, `ssmmessages:*`) and on the statements managing the boundary policy itself. Each was evaluated individually.
* **Boundary wildcard actions:** The `ssm:*` finding was suppressed with a documented justification. The unscoped access it flags is not new exposure: it mirrors the AWS-managed `AmazonSSMManagedInstanceCore` policy already attached to the same role, and the boundary's contribution is capping everything *outside* that family, not narrowing what is already there.
* **`iam:CreatePolicyVersion` on the boundary:** This was first suppressed on the argument that the boundary policy cannot grant IAM actions itself. That argument was wrong, because whoever can publish a new version of the boundary can raise the ceiling it sets. The statement was removed instead, and the pipeline now has read-only access to the boundary policy (see Engineering Challenges).

#### Trivy (Container Image Scanning)
Counts below are point-in-time and change as the vulnerability database updates.

* **API Image (`python:3.12-slim`):** Identified 11 findings in base Debian OS packages (perl, ncurses, sqlite) that the application does not consume. These carried an affected or deferred status with no upstream patches available. They were handled using `ignore-unfixed: true`, ensuring the pipeline blocks only on actionable vulnerabilities. Alpine was rejected as an alternative because `psycopg2-binary` uses glibc-only wheels, which would make Alpine builds slow and fragile.
* **Frontend Image (`nginx:1.27-alpine`):** Detected 33 findings in standard libraries (OpenSSL, libxml2, libpng, zlib) due to an outdated base image. This was resolved by adding `RUN apk update && apk upgrade --no-cache` to the Dockerfile to pull current patched packages during the build phase, resulting in a clean scan.
* **Database Image (`postgres:16-alpine`):** As of November 2026 the scan reports 26 findings (25 HIGH, 1 CRITICAL), all in the Go standard library compiled into `usr/local/bin/gosu`, a helper binary bundled in the official image. The CRITICAL finding is a crypto/tls certificate validation issue during session resumption (CVE-2025-68121). Fixed Go versions exist, but the vulnerable code sits inside a binary in the unmodified upstream image, so it cannot be patched with a package manager and is only cleared when the maintainers rebuild the image with a newer Go toolchain. The step uses `continue-on-error: true`, so it reports findings but never blocks deployments. This is an accepted operational risk, and the step is informational, not a gate.

#### Gitleaks (Secrets Detection)
* **Status:** Zero findings across the full git history (the scan runs with `fetch-depth: 0`). While Sealed Secrets was in use, its encrypted manifest (ciphertext, not a plaintext secret) was allowlisted as a false positive; the allowlist was removed together with it.

## Engineering Challenges and Design Decisions

### K3s Crash-Loop on WSL2 Restart
During development, K3s entered a persistent crash-loop following a WSL2 restart, failing an internal RBAC bootstrap sequence with vague log output. After ruling out disk space issues and datastore corruption, the root cause was traced to an outdated WSL2 kernel. The issue was resolved by updating WSL, performing a clean reinstall of K3s, and refreshing the local kubeconfig.

### CPU Credit Exhaustion on Burstable Instances
Initial testing utilized a free-tier t3.micro instance (1 vCPU, 1 GB RAM). The K3s control plane consumed roughly 75 percent of the available CPU at steady state, rapidly exhausting the burstable instance baseline during extended testing sessions. This caused the AWS Systems Manager agent to hibernate and caused kubectl commands to hang indefinitely. The infrastructure was upgraded to a t3.small instance (2 vCPU, 2 GB RAM), matching the minimum documented resource requirements for a stable K3s server node.

### Sealed Secrets and Ephemeral Clusters
The Sealed Secrets controller was implemented and tested, but subsequently removed from the architecture. The controller generates a unique encryption key pair upon installation. In a destroy-and-recreate deployment pattern, all previously sealed secrets become permanently unreadable after a cluster rebuild. While Sealed Secrets is an excellent choice for long-lived clusters managed by GitOps engines like Argo CD or Flux, it creates unnecessary overhead in short-lived environments. The architecture shifted to pipeline-injected secrets from GitHub Secrets to align with the ephemeral infrastructure model.

### hostPath Volumes and Directory Ownership
The Kubernetes `fsGroup` setting does not apply to hostPath-backed volumes, which K3s uses by default via its `local-path-provisioner`. As a result, the Postgres initialization process failed with permission errors when running as a non-root user against a root-owned directory. This was resolved by introducing a root-configured init container that runs a chown command on the shared volume directory before handing off control to the unprivileged main Postgres container.

### Self-referential IAM permissions
Migrating CI/CD to OIDC federation surfaced a gap: an IAM role needs explicit permission to read *itself* and its own dependencies during a full `terraform apply` refresh: `iam:GetOpenIDConnectProvider` on its own OIDC provider, `iam:ListRolePolicies` and `iam:ListAttachedRolePolicies` on its own role.

### Permissions boundary vs. attachment restriction
Early framing of this problem risked conflating "restrict which policies can be attached to a role" (achievable with `Condition` keys, already done for `AttachRolePolicy`/`PassRole`) with "restrict what a role can inline onto itself" (`PutRolePolicy`, which takes an arbitrary policy document as a parameter, and no condition key can inspect its contents). A Permissions Boundary solves the second case differently: it doesn't gate the *write*, it gates the *effect*. Separately, the `iam:PermissionsBoundary` condition on `iam:CreateRole` hit the same context-key gap seen earlier with `AttachRolePolicy` and `PassRole`: the key only exists for specific actions, so a statement that mixes actions evaluates the condition as false. It was split into its own statement.

### Verifying a security control
A successful `terraform apply` after adding the boundary only proves the legitimate path (the EC2 instance provisioning and writing its SSM parameter) still works. It says nothing about whether the escalation path is actually closed. That required a separate check using `aws iam simulate-principal-policy`, which evaluates a role's effective permissions rather than whether the API call succeeded.

### The CI role could edit its own permissions
A review after the boundary work found two paths the boundary did not cover. The CI role's IAM write permissions were scoped to `role/k3s-demo-*`, a name pattern that also matched the CI role itself, so it could attach an inline policy to itself. It could also publish new versions of the boundary policy, which would raise the ceiling the boundary sets. Both were confirmed as `allowed` with `aws iam simulate-principal-policy` before the change. The fix was to scope write access by exact name to the instance role and instance profile, and to make the identity layer (the CI role, the OIDC provider, and the boundary policy) read-only for the pipeline, keeping only the read actions Terraform needs to refresh state. The same checks then returned `implicitDeny`, while the reads and the instance role management still returned `allowed`. The trade-off is that changes to those resources are now applied by an administrator from a local machine instead of by the pipeline.
## Planned Improvements
* Implement image signing using Cosign.
* Generate Software Bill of Materials (SBOM) tracking using `trivy sbom`.
* Package application manifests into a unified Helm chart.
* Enforce admission policies using Open Policy Agent (OPA) or Kyverno.
* Design a structured promotion flow spanning distinct staging and production namespaces.
* Scan images before publishing them to the registry, and publish only from `main`.
* Add HTTPS on the Traefik ingress (the application is currently served over HTTP only).
* Narrow the EC2 permissions of the CI role with tag-based conditions and restrictions on instance type and AMI.
* Replace opening the K3s API port during deploy with an SSM-based mechanism, since the instance already runs the SSM agent.
* Pin base images and the init container by digest (the `busybox` init container is currently unpinned).
* Enable state locking on the S3 backend (none is configured today).
