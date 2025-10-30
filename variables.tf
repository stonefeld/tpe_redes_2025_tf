variable "project_name" {
  type = string
  description = "The name of the project"
  default = "the-store"
}

variable "environment" {
  type = string
  description = "The environment of the project"
  default = "dev"
}

variable "ssh_public_key_path" {
  type = string
  description = "Path to the public SSH key file for EC2 access"
  default = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  type = string
  description = "Path to the private SSH key file for EC2 access"
  default = "~/.ssh/id_rsa"
}