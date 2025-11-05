resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-private-ec2-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all traffic from client-to-site VPN subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.8.0.0/24"]
  }

  # Allow all traffic from remote site-to-site subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.remote_cidr]
  }

  # Allow ICMP (ping) from VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # dynamic "ingress" {
  #   for_each = var.enable_site_to_site ? [1] : []
  #   content {
  #     from_port   = 0
  #     to_port     = 0
  #     protocol    = "-1"
  #     cidr_blocks = [var.remote_cidr]
  #   }
  # }

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

resource "aws_instance" "cluster" {
  ami                         = "ami-0360c520857e3138f"
  instance_type               = "t2.medium"
  key_name                    = aws_key_pair.openvpn.key_name
  vpc_security_group_ids      = [aws_security_group.cluster.id]
  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false

  root_block_device {
    volume_size           = 50   # GiB
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = file("${path.module}/setup-the-store.sh")

  tags = {
    Name = "${var.project_name}-private-ec2"
  }
}
