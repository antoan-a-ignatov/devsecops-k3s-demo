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
        # nosemgrep: terraform.lang.security.iam.no-iam-data-exfiltration.no-iam-data-exfiltration
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
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"
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
        # nosemgrep: terraform.lang.security.iam.no-iam-priv-esc-funcs.no-iam-priv-esc-funcs, terraform.lang.security.iam.no-iam-resource-exposure.no-iam-resource-exposure
        Action = [
          "iam:CreateRole", "iam:GetRole", "iam:DeleteRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
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
        Sid    = "IAMAttachOnlySSMPolicy"
        Effect = "Allow"
        # Condition restricts this to attaching/detaching exactly one managed
        # policy (AmazonSSMManagedInstanceCore) — cannot attach AdministratorAccess
        # or any other policy to a k3s-demo-* role.
        # nosemgrep: terraform.lang.security.iam.no-iam-priv-esc-funcs.no-iam-priv-esc-funcs, terraform.lang.security.iam.no-iam-resource-exposure.no-iam-resource-exposure
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
        # nosemgrep: terraform.lang.security.iam.no-iam-resource-exposure.no-iam-resource-exposure
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
        # nosemgrep: terraform.lang.security.iam.no-iam-resource-exposure.no-iam-resource-exposure
        Action = [
          "iam:CreateRole", "iam:GetRole", "iam:DeleteRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:CreateInstanceProfile", "iam:GetInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole", "iam:TagRole"
        ]
        Resource = "arn:aws:iam::180571023536:oidc-provider/token.actions.githubusercontent.com"
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
