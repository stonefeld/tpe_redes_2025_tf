# Security group for OpenVPN server
resource "aws_security_group" "openvpn" {
  name_prefix = "${var.project_name}-openvpn-"
  vpc_id      = module.vpc.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # OpenVPN access
  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-openvpn-sg"
  }
}

# Key pair for SSH access
resource "aws_key_pair" "openvpn" {
  key_name   = "${var.project_name}-openvpn-key"
  public_key = file(var.ssh_public_key_path)
}

# EC2 instance for OpenVPN server
resource "aws_instance" "openvpn" {
  ami                         = "ami-0360c520857e3138f" # Ubuntu 24.04 LTS
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.openvpn.key_name
  vpc_security_group_ids      = [aws_security_group.openvpn.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  user_data_base64 = base64encode(templatefile("${path.module}/openvpn-setup.sh", {
    project_name = var.project_name
  }))

  tags = {
    Name = "${var.project_name}-openvpn-server"
  }
}


