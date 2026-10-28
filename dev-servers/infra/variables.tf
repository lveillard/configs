variable "ssh_source_ip" {
  type        = string
  default     = ""
  description = "Workstation IPv4 allowed on public port 22 while bootstrapping a box; leave empty afterwards."
}
