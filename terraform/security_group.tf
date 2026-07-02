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
  ingress {
    description = "K3s API access, opened temporarily by CD pipeline, see variables.tf for tradeoff explanation"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.k3s_api_cidrs
  }
  ingress {
    description = "HTTP access to the application frontend via Traefik Ingress, open to everyone by design"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
