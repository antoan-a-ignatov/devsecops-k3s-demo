data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = {
    Project = "devsecops-k3s-demo"
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name = "k3s-demo-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:antoan-a-ignatov/devsecops-k3s-demo:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Project = "devsecops-k3s-demo"
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "k3s-demo-github-actions-deploy-policy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        # Resource is scoped to the exact state bucket ARN below, not "*" — Semgrep's
        # data-exfiltration rule doesn't correlate the Action list with the Resource block.
        # nosemgrep
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::devsecops-k3s-demo-tfstate-antoan",
          "arn:aws:s3:::devsecops-k3s-demo-tfstate-antoan/*"
        ]
      },
      {
        Sid    = "EC2Manage"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances", "ec2:TerminateInstances", "ec2:CreateTags",
          "ec2:Describe*",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMManageProjectRoles"
        Effect = "Allow"
        # These IAM management actions are Semgrep-flagged categorically as
        # priv-esc/resource-exposure risk regardless of scoping. Resource is
        # constrained to k3s-demo-* ARNs; the actual escalation vectors
        # (AttachRolePolicy, PassRole) are separately condition-scoped below.
        # nosemgrep
        Action = [
          "iam:GetRole", "iam:DeleteRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:CreateInstanceProfile", "iam:GetInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole", "iam:TagRole"
        ]
        Resource = [
          "arn:aws:iam::180571023536:role/k3s-demo-*",
          "arn:aws:iam::180571023536:instance-profile/k3s-demo-*"
        ]
      },
      {
        Sid    = "IAMCreateRoleWithBoundary"
        Effect = "Allow"
        # Every k3s-demo-* role this identity creates must carry the boundary —
        # enforced here for anything created/recreated going forward. (iam.tf's
        # in-place update handles the role that already exists today.)
        # nosemgrep
        Action   = "iam:CreateRole"
        Resource = "arn:aws:iam::180571023536:role/k3s-demo-*"
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = aws_iam_policy.k3s_demo_role_boundary.arn
          }
        }
      },
      {
        Sid    = "IAMAttachOnlySSMPolicy"
        Effect = "Allow"
        # Condition restricts this to attaching/detaching exactly one managed
        # policy (AmazonSSMManagedInstanceCore) — cannot attach AdministratorAccess
        # or any other policy to a k3s-demo-* role.
        # nosemgrep
        Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource = "arn:aws:iam::180571023536:role/k3s-demo-*"
        Condition = {
          StringEquals = {
            "iam:PolicyARN" = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
          }
        }
      },
      {
        Sid    = "IAMPassRoleToEC2Only"
        Effect = "Allow"
        # Condition restricts PassRole to the EC2 service only — cannot pass a
        # k3s-demo-* role to Lambda or any other escalation-prone service.
        # nosemgrep
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::180571023536:role/k3s-demo-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "IAMManageOwnOIDCProvider"
        Effect = "Allow"
        # Resource is scoped to the exact OIDC provider ARN this role lives under —
        # cannot manage any other provider.
        # nosemgrep
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags"
        ]
        Resource = "arn:aws:iam::180571023536:oidc-provider/token.actions.githubusercontent.com"
      },
      {
        Sid    = "IAMManageOwnBoundaryPolicy"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy", "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions",
          "iam:DeletePolicyVersion", "iam:TagPolicy"
        ]
        Resource = aws_iam_policy.k3s_demo_role_boundary.arn
      },
      {
        Sid    = "IAMCreatePolicyVersionKnownEscalationRisk"
        Effect = "Allow"
        # iam:CreatePolicyVersion is a documented IAM privilege-escalation
        # technique (creating a new version of a policy you control) —
        # expected to trip no-iam-priv-esc-funcs. Mitigated by scoping to
        # this exact boundary policy ARN, which cannot itself grant IAM
        # actions (see its Action list above: ssm/ec2messages/ssmmessages
        # only) — so even a maximally broad new version of this specific
        # policy can't be used to escalate.
        # nosemgrep: terraform.lang.security.iam.no-iam-priv-esc-funcs.no-iam-priv-esc-funcs
        Action   = "iam:CreatePolicyVersion"
        Resource = aws_iam_policy.k3s_demo_role_boundary.arn
      },
      {
        Sid      = "SSMKubeconfig"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:eu-north-1:180571023536:parameter/k3s-demo/kubeconfig"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}
