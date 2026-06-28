variable "my_ip" {
  description = "Your public IP, for restricting SSH access. Defaults to no access; set explicitly only when you need to SSH in."
  type        = string
  default     = "127.0.0.1/32"
}

# NOTE: opened broadly (0.0.0.0/0) by the CD pipeline only for the brief
# window needed to run kubectl apply, then immediately tightened back to
# closed in the same workflow run (see .github/workflows/ci.yml). Access
# is still gated by the kubeconfig's client certificate in Parameter Store,
# not by network restriction, during that open window. This is a deliberate
# tradeoff for a short-lived demo instance, not a production-appropriate
# posture.
variable "k3s_api_cidrs" {
  description = "CIDR blocks allowed to reach the K3s API port. Defaults to closed."
  type        = list(string)
  default     = ["127.0.0.1/32"]
}
