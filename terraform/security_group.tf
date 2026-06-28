resource "aws_security_group" "k3s_demo" {
  name        = "k3s-demo-sg"
  description = "Security group for the DevSecOps K3s demo instance"

  ingress {
    description = "SSH access for manual debugging, restricted to my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "k3s-demo-sg"
    Project = "devsecops-k3s-demo"
  }
}
