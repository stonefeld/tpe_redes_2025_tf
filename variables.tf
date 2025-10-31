variable "project_name" {
  type        = string
  description = "The name of the project"
  default     = "the-store"
}

variable "environment" {
  type        = string
  description = "The environment of the project"
  default     = "dev"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to the public SSH key file for EC2 access"
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the private SSH key file for EC2 access"
  default     = "~/.ssh/id_rsa"
}

variable "remote_cidr" {
  type        = string
  description = "Remote LAN CIDR (e.g., LAN B) reachable over the VPN tunnel"
  default     = "10.2.0.0/16"
}

variable "enable_site_to_site" {
  type        = bool
  description = "Enable site-to-site routing via the OpenVPN gateway instance"
  default     = true
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for this site's VPC (LAN A or LAN B)"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  description = "List of public subnet CIDRs"
  default     = ["10.0.1.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "List of private subnet CIDRs"
  default     = ["10.0.2.0/24"]
}

variable "lan_role" {
  type        = string
  description = "Role of this site in S2S: 'server' (LAN A) or 'client' (LAN B)"
  default     = "server"
  validation {
    condition     = contains(["server", "client"], var.lan_role)
    error_message = "lan_role must be either 'server' or 'client'"
  }
}

variable "peer_gateway_common_name" {
  type        = string
  description = "Common Name to use for the peer site gateway client certificate"
  default     = "lanB-gw"
}
