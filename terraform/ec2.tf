data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "k3s_demo" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.k3s_demo.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_instance_profile.name

  user_data = <<-EOF2
    #!/bin/bash
    set -e

    export DEBIAN_FRONTEND=noninteractive

    apt-get -o DPkg::Lock::Timeout=120 update
    apt-get -o DPkg::Lock::Timeout=120 install -y unzip curl

    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install

    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

    echo "PUBLIC_IP resolved to: $PUBLIC_IP"
    curl -sfL https://get.k3s.io | sh -s - --tls-san "$PUBLIC_IP" --disable metrics-server --disable servicelb --kube-apiserver-arg=max-requests-inflight=50 --kube-controller-manager-arg=node-monitor-period=60s --kube-controller-manager-arg=node-monitor-grace-period=180s

    sleep 30

    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
    helm repo update
    helm install sealed-secrets -n kube-system --set-string fullnameOverride=sealed-secrets-controller sealed-secrets/sealed-secrets --kubeconfig /etc/rancher/k3s/k3s.yaml

    KUBECONFIG_CONTENT=$(cat /etc/rancher/k3s/k3s.yaml)
    KUBECONFIG_CONTENT=$(echo "$KUBECONFIG_CONTENT" | sed "s/127.0.0.1/$PUBLIC_IP/")

    aws ssm put-parameter \
      --name "/k3s-demo/kubeconfig" \
      --value "$KUBECONFIG_CONTENT" \
      --type "SecureString" \
      --region eu-north-1 \
      --overwrite
  EOF2

  tags = {
    Name    = "k3s-demo-instance"
    Project = "devsecops-k3s-demo"
  }
}

output "instance_public_ip" {
  value = aws_instance.k3s_demo.public_ip
}
