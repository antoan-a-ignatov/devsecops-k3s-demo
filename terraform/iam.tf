resource "aws_iam_role" "k3s_instance_role" {
  name = "k3s-demo-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = "devsecops-k3s-demo"
  }
}

resource "aws_iam_role_policy" "k3s_ssm_write" {
  name = "k3s-demo-ssm-write"
  role = aws_iam_role.k3s_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:PutParameter"
        Resource = "arn:aws:ssm:eu-north-1:*:parameter/k3s-demo/kubeconfig"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k3s_instance_profile" {
  name = "k3s-demo-instance-profile"
  role = aws_iam_role.k3s_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.k3s_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
