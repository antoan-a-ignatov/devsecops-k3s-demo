variable "my_ip" {
  description = "Your public IP, for restricting SSH access. Defaults to no access; set explicitly only when you need to SSH in."
  type        = string
  default     = "127.0.0.1/32"
}
