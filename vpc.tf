module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name            = var.project_name
  cidr            = var.vpc_cidr
  azs             = ["us-east-1a"]
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
}
