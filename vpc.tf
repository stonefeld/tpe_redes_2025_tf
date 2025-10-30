module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = var.project_name
  cidr = "10.0.0.0/16"
  azs = ["us-east-1a"]
  private_subnets = ["10.0.2.0/24"]
  public_subnets = ["10.0.1.0/24"]
}