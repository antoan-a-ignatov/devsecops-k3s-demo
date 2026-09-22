resource "aws_iam_policy" "k3s_demo_role_boundary" {
  name = "k3s-demo-role-boundary"

  # Ceiling for any k3s-demo-* role, regardless of what gets attached/inlined
  # onto it later. Scoped at the service level (not exact-action) to match
  # what AmazonSSMManagedInstanceCore + the custom SSM write actually need,
  # without hard-coding that AWS-managed policy's exact (and occasionally
  # revised) action list.
   policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SsmFamilyOnly"
        Effect   = "Allow"
        Action   = ["ssm:*", "ec2messages:*", "ssmmessages:*"]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = "devsecops-k3s-demo"
  }
}

output "role_boundary_policy_arn" {
  value = aws_iam_policy.k3s_demo_role_boundary.arn
}
