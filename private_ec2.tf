resource "aws_security_group" "private_ec2" {
  name_prefix = "${var.project_name}-private-ec2-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.8.0.0/24"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  dynamic "ingress" {
    for_each = var.enable_site_to_site ? [1] : []
    content {
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = [var.remote_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-private-ec2-sg"
  }
}

resource "aws_instance" "private_ec2" {
  ami                         = "ami-0360c520857e3138f"
  instance_type               = "t3.medium"
  key_name                    = aws_key_pair.openvpn.key_name
  vpc_security_group_ids      = [aws_security_group.private_ec2.id]
  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false

  user_data = file("${path.module}/setup-the-store.sh")

  tags = {
    Name = "${var.project_name}-private-ec2"
  }
}
