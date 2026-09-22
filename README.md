# DevSecOps K3s Migration Demo

## Project Status

[![Build Status](https://img.shields.io/github/actions/workflow/status/antoan-a-ignatov/devsecops-k3s-demo/ci.yml?style=flat-square&label=Build)](https://github.com/antoan-a-ignatov/devsecops-k3s-demo/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/antoan-a-ignatov/devsecops-k3s-demo?style=flat-square)](https://github.com/antoan-a-ignatov/devsecops-k3s-demo/releases) [![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/) [![K3s](https://img.shields.io/badge/K3s-FF6C37?style=flat-square&logo=kubernetes&logoColor=white)](https://k3s.io/) [![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://developer.hashicorp.com/terraform) [![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white)](https://docs.github.com/actions) [![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat-square&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
* **Current Version:** v1.2.0
* **Status:** Functional cloud deployment complete
* **Last Improvements:** GitHub OIDC Federation; IAM Permissions Boundary

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
| Secrets management | Pipeline-injected Kubernetes Secrets from GitHub Secrets; CI-to-AWS authentication via GitHub OIDC federation, no long-lived AWS credentials stored anywhere |
| Network security | NetworkPolicy restricting database access to the API pod only, enforced by the K3s embedded kube-router controller |
| Supply-chain security | All GitHub Actions pinned to immutable 40-character commit SHAs |
| Deployment automation | Liveness and readiness probes along with resource requests and limits applied to every container |
| Troubleshooting | Real K3s cluster failures diagnosed and resolved systematically |

## Architecture
All three tiers run as separate Deployments and Services on K3s. In the CI/CD environment, the cluster is provisioned on a t3.small EC2 instance via Terraform. The kubeconfig is pushed to AWS Systems Manager Parameter Store so the pipeline can execute deployments without exposing the K3s API publicly during the build process. Locally, the cluster runs within WSL2.

```mermaid
flowchart TD

    DEV[Developer]

    DEV -->|Push| GITHUB[GitHub Repository]

    GITHUB -->|Trigger| GHA[GitHub Actions]

    subgraph SECURITY["CI Security Scans"]
        GITLEAKS[Gitleaks]
        SEMGREP[Semgrep]
        TRIVY[Trivy]
    end

    GHA --> GITLEAKS
    GHA --> SEMGREP
    GHA --> TRIVY

    GHA -->|Build & Push Images| GHCR[GitHub Container Registry]
    GHA -->|Provision Infrastructure| TF[Terraform]

    TF --> EC2[AWS EC2 Instance]
    EC2 --> K3S[K3s Cluster]

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

    FRONTEND --> API
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
* **CI/CD and Automation:** GitHub Actions, Helm
* **Security Scanning:** Gitleaks, Semgrep, Trivy
* **Infrastructure as Code:** Terraform
* **Cloud Platform:** AWS (EC2, S3, IAM OIDC Federation, IAM Permissions Boundaries, Systems Manager Parameter Store)
* **Container Registry:** GitHub Container Registry (GHCR)

### Technologies Evaluated
* **Sealed Secrets:** Evaluated and implemented during development, but deliberately excluded from the final production architecture due to the ephemeral nature of the cluster.

## Infrastructure
The cloud cluster is completely managed via Terraform, including the EC2 instance, security groups, IAM roles, and instance profiles. The IAM role is tightly scoped, allowing it to only write the kubeconfig to a single AWS Systems Manager Parameter Store path. State is stored in an S3 bucket so that local runs and the pipeline maintain a unified view of the active infrastructure.

The automated boot script performs the following tasks:
* Installs the AWS CLI, K3s (with control-plane flags tuned for resource-constrained environments), and Helm.
* Pushes the kubeconfig to Parameter Store using IMDSv2 for secure metadata retrieval.
* Substitutes the public IP into the kubeconfig before uploading so external automated tools can establish a connection.

The instance is short-lived by design, provisioned specifically for a demo or a pipeline run and then destroyed immediately after.

![Application](docs/images/instance.png)
![Application](docs/images/instance-monitoring.png)
![Application](docs/images/instance-kubectl.png)

## CI/CD Pipeline
The pipeline triggers on every push to main and every pull request. Stages execute sequentially, with each stage acting as a quality gate for the next. 

The deployment job provisions a fresh EC2 instance or reuses an existing one via Terraform, waits for K3s to finish booting, and verifies that the kubeconfig IP matches the new instance before attempting a connection. It then creates the database Secret from a GitHub Secret and applies the Kubernetes manifests. 

Authentication to AWS uses GitHub's OIDC provider rather than static credentials: the `deploy` job requests a short-lived identity token (`permissions: id-token: write`), which GitHub exchanges with AWS STS for temporary credentials scoped to a single IAM role. No AWS access key ever exists in this repository.

The K3s API port (6443) is opened to all traffic exclusively for the duration of this step. It is immediately closed by a final cleanup step running with an absolute execution rule, ensuring security enforcement even if the deployment fails. Images are tagged with both the latest tag and the exact commit SHA, linking every deployed artifact directly to an auditable point in git history.

![Application](docs/images/github-action.png)

## Security

### Security Architecture
* **Network Isolation:** A NetworkPolicy restricts database access to the API pod only. This prevents lateral movement if the API pod is compromised. It is enforced natively out of the box by the embedded kube-router controller in K3s and validated via live traffic testing.
* **API Exposure Mitigation:** The K3s API port (6443) is closed by default in the AWS security group. The deployment job opens access to all traffic only during the deployment step, tightening it down immediately afterward. This approach addresses the limitation where GitHub hosted runner IP ranges exceed AWS security group rule limits. The API remains fully protected by client certificate authentication via the kubeconfig, which serves as the actual access control.

### Hardening
* **Privilege Escalation Prevention:** Application containers utilize explicit `securityContext` configurations to prevent privilege escalation. API and database containers run as verified non-root UIDs, which was confirmed by direct image inspection. All Linux capabilities are dropped by default, and only essential ones are added back.
* **Nginx Special Handling:** The Nginx master process must start as root to bind to port 80 before dropping privileges internally. This prevents the enforcement of a pod-level non-root requirement during startup. To maintain security, necessary capabilities (NET_BIND_SERVICE, CHOWN, SETUID, SETGID) are explicitly added back, while all other capabilities remain dropped.
* **Postgres Volume Access:** K3s uses local-path-provisioner, backing volumes with plain hostPath directories on the node. Because the fsGroup setting does not apply to hostPath volumes, a root-owned directory causes Postgres initialization to fail. An init container running as root modifies the directory ownership via chown before the main Postgres container starts, allowing Postgres to run securely as a non-root user.
* **Supply-Chain Hardening:** All actions within the GitHub Actions workflow are pinned to immutable 40-character commit SHAs instead of mutable tags, preventing untrusted upstream modifications from compromising the pipeline. Human-readable tags are preserved alongside the SHAs as comments.
* **Resource Constraints:** Every container is configured with explicit CPU and memory requests and limits to ensure stability and prevent resource exhaustion on the cluster.
* **CI Identity Least Privilege:** The GitHub Actions OIDC role's IAM policy is scoped as tightly as AWS's API allows. S3 state access, SSM parameter access, and IAM role/instance-profile management are all constrained to exact resource ARNs. `iam:AttachRolePolicy`/`DetachRolePolicy` is further restricted with a `Condition` to the single managed policy this project actually uses (`AmazonSSMManagedInstanceCore`), and `iam:PassRole` is restricted to the EC2 service only, both close specific, nameable privilege-escalation paths (attaching a broader policy to a role it created, or passing that role to an unintended service). EC2 instance and security-group mutation actions (`RunInstances`, `CreateSecurityGroup`, etc.) remain unscoped by resource, the same documented tradeoff as the K3s API exposure above: AWS does not support tag-based conditions on these actions before the resource exists, so per-resource scoping isn't available.
* **IAM Permissions Boundary:** `k3s-demo-instance-role` carries a boundary scoped to the `ssm`, `ec2messages`, and `ssmmessages` action families, capping its effective permissions regardless of what gets attached or inlined onto it later. AWS computes effective access as the intersection of a role's policy and its boundary, never the union. `iam:CreateRole` is condition-scoped to require the same boundary on any newly created `k3s-demo-*` role. Verified with the AWS IAM Policy Simulator, not just a green pipeline: an intentionally broad inline policy (`s3:*`) was attached via `iam:PutRolePolicy` (which succeeds, as expected: that action was never restricted) and confirmed to evaluate as `implicitDeny` via `simulate-principal-policy`, proving the boundary actually constrains effective access.

### Secrets Management
The database password is kept securely as a GitHub Secret and injected directly as a Kubernetes Secret by the pipeline during deployment. It is never written to disk within the repository or exposed in git history. This model introduces a trade-off: the secret must be regenerated during every infrastructure recreation cycle, due to utilizing ephemeral infrastructure patterns.

CI-to-AWS authentication originally used a long-lived IAM user's access keys, stored as GitHub Secrets. That user was created manually in the AWS console before any Terraform infrastructure existed, has `AdministratorAccess` attached via an IAM group, and was never tracked in this repo's Terraform state, entirely out-of-band from the rest of the project's IaC-managed identities.
This was replaced with GitHub OIDC federation: an IAM OIDC identity provider and a purpose-built IAM role (`k3s-demo-github-actions-deploy`), both defined in `terraform/oidc.tf`. The role's trust policy is scoped to this exact repository and the `main` branch via the GitHub OIDC token's `sub` claim, so a pull-request-triggered run cannot assume it. The role ARN itself is stored as a GitHub repository *Variable*.

### Pipeline Findings
Running active security scanners against the application code, Kubernetes manifests, GitHub Actions workflows, and container images surfaced genuine findings which were investigated, documented, and either remediated or accepted based on their impact and the project's goals.

#### Semgrep (SAST)
* `python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host`: Flagged the use of `app.run(host="0.0.0.0")` in the Flask API. This was assessed as a false positive in this specific environment, as the container operates in an isolated pod network namespace and binding to all interfaces is required for the Kubernetes Service to route traffic to it. This finding is suppressed inline with a `nosemgrep` comment and a documented explanation.
* `yaml.kubernetes.security.run-as-non-root.run-as-non-root`: Flagged `frontend-deployment.yaml` for missing a pod-level non-root setting. This is intentional, as the Nginx master process requires root access to bind port 80. This rule is excluded at the pipeline level using `--exclude-rule`, with the rationale documented here due to YAML syntax layout constraints.
* `github-actions-mutable-action-tag`: Flagged actions using mutable version tags. This was resolved by pinning all actions to their definitive commit SHAs.
* `terraform.lang.security.iam.no-iam-data-exfiltration`: Flagged the S3 state-access actions (`GetObject`, `PutObject`, `ListBucket`) in the OIDC role's policy. False positive: the rule checks for the presence of these actions without correlating them against the `Resource` block, which is scoped to the exact state bucket ARN, not `"*"`. Suppressed inline with `nosemgrep`.
* `terraform.lang.security.iam.no-iam-priv-esc-funcs` and `terraform.lang.security.iam.no-iam-resource-exposure`: Flagged every IAM role/policy management action in the OIDC role's policy (`CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `PassRole`, and related actions needed to manage the role's own OIDC provider and inline policies). These rules fire on the presence of these action strings categorically; they don't evaluate whether a `Condition` block mitigates the risk. Genuinely mitigated where AWS's IAM condition keys allow it (see Security hardening, above); suppressed inline where the rule's pattern-matching can't see that mitigation. One suppression syntax detail worth noting: Semgrep's documented comma-delimited multi-rule-ID format (`nosemgrep: rule-1, rule-2`) proved unreliable in practice, inconsistently dropping one of the two rule IDs across repeated identical attempts; switched to a bare `nosemgrep` (no rule ID) on these lines instead.

#### Trivy (Container Image Scanning)
* **API Image (`python:3.12-slim`):** Identified 11 findings in base Debian OS packages (perl, ncurses, sqlite) that the application does not consume. These carried an affected or deferred status with no upstream patches available. They were handled using `ignore-unfixed: true`, ensuring the pipeline blocks only on actionable vulnerabilities. Alpine was rejected as an alternative because `psycopg2-binary` uses glibc-only wheels, which would make Alpine builds slow and fragile.
* **Frontend Image (`nginx:1.27-alpine`):** Detected 33 findings in standard libraries (OpenSSL, libxml2, libpng, zlib) due to an outdated base image. This was resolved by adding `RUN apk update && apk upgrade --no-cache` to the Dockerfile to pull current patched packages during the build phase, resulting in a clean scan.
* **Database Image (`postgres:16-alpine`):** Found 16 vulnerabilities embedded within the Go standard library by upstream maintainers, including a critical TLS issue. These cannot be patched via package managers and exist inside the official unmodified image. The step uses `continue-on-error: true` to prevent blocking deployments on unfixable upstream bugs, tracking this as an accepted operational risk.
* **IAM findings on the Permissions Boundary implementation:** Adding the boundary policy and its supporting statements surfaced the same category of finding as the original OIDC work: `no-iam-data-exfiltration` and `no-iam-resource-exposure` fired on the boundary policy's service-level wildcard actions (`ssm:*`, `ec2messages:*`, `ssmmessages:*`) and on the statements managing the boundary policy resource itself. Each was evaluated individually. The wildcard-action finding specifically got a documented, non-obvious justification: the unscoped `ssm:*` read access it flags isn't new exposure introduced by this project, it mirrors the AWS-managed `AmazonSSMManagedInstanceCore` policy already attached to the same role; the boundary's actual security contribution is capping everything *outside* that family, not narrowing what's already there. `iam:CreatePolicyVersion` on the boundary's own management statement got a separate, specific suppression: it's a documented IAM privilege-escalation technique (creating a new version of a policy you control), mitigated here by that policy being unable to grant IAM actions itself: a maximally broad new version of it still can't be used to escalate.

#### Gitleaks (Secrets Detection)
* **Status:** Zero findings. Verifies that no sensitive credentials or database passwords entered git history at any point during development.

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
Migrating CI/CD to OIDC federation surfaced a gap: an IAM role needs explicit permission to read and manage *itself* and its own dependencies during a full `terraform apply` refresh: `iam:GetOpenIDConnectProvider` on its own OIDC provider, `iam:ListRolePolicies` and `iam:ListAttachedRolePolicies` on its own role.

### Permissions boundary vs. attachment restriction
Early framing of this problem risked conflating "restrict which policies can be attached to a role" (achievable with `Condition` keys, already done for `AttachRolePolicy`/`PassRole`) with "restrict what a role can inline onto itself" (`PutRolePolicy`, which takes an arbitrary policy document as a parameter, and no condition key can inspect its contents). A Permissions Boundary solves the second case differently: it doesn't gate the *write*, it gates the *effect*. Getting this distinction right up front shaped the whole design: it meant realizing the same `Condition`-context-key gap already hit once with `AttachRolePolicy`/`PassRole` would recur on `iam:CreateRole`'s `iam:PermissionsBoundary` condition if left in a combined statement, so it was split out.

### Verifying a security control
A successful `terraform apply` after adding the boundary only proves the legitimate path (the EC2 instance provisioning and writing its SSM parameter) still works. It says nothing about whether the escalation path is actually closed. That required a separate check using `aws iam simulate-principal-policy`, to evaluates a role's effective permissions rather than whether the API call succeeded.


## Planned Improvements
* Implement image signing using Cosign.
* Generate Software Bill of Materials (SBOM) tracking using `trivy sbom`.
* Package application manifests into a unified Helm chart.
* Enforce admission policies using Open Policy Agent (OPA) or Kyverno.
* Design a structured promotion flow spanning distinct staging and production namespaces.
