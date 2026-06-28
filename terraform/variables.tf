variable "my_ip" {
  description = "Your public IP, for restricting SSH access. Defaults to no access; set explicitly only when you need to SSH in."
  type        = string
  default     = "127.0.0.1/32"
}

variable "github_actions_cidrs" {
  description = "GitHub Actions runner IP ranges, for K3s API access from CD pipeline"
  type        = list(string)
  default     = ["127.0.0.1/32"]
}
