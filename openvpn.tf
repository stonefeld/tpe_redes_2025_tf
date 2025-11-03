locals {
  openvpn_user_data_template = var.lan_role == "server" ? "${path.module}/openvpn-server.sh" : "${path.module}/openvpn-client.sh"
}

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

  # Nginx access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all traffic from remote LAN CIDR for site-to-site
  dynamic "ingress" {
    for_each = var.enable_site_to_site ? [1] : []
    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [var.remote_cidr]
    }
  }

  # Allow all traffic from private subnet (for VPN site-to-site routing)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnets
  }

  # Allow all traffic from VPN client subnet (10.8.0.0/24) for client-to-site
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.8.0.0/24"]
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
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.openvpn.key_name
  vpc_security_group_ids      = [aws_security_group.openvpn.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  source_dest_check           = false

  user_data_base64 = base64encode(templatefile(local.openvpn_user_data_template, {
    project_name             = var.project_name,
    local_cidr               = var.vpc_cidr,
    remote_cidr              = var.remote_cidr,
    peer_gateway_common_name = var.peer_gateway_common_name
  }))

  tags = {
    Name = "${var.project_name}-openvpn-server"
  }
}

# Route remote LAN CIDR to the OpenVPN gateway ENI from the private route table (site-to-site)
data "aws_network_interface" "openvpn_primary_eni" {
  id = aws_instance.openvpn.primary_network_interface_id
}

resource "aws_route" "private_to_remote_over_vpn" {
  count                  = var.enable_site_to_site ? 1 : 0
  route_table_id         = module.vpc.private_route_table_ids[0]
  destination_cidr_block = var.remote_cidr
  network_interface_id   = data.aws_network_interface.openvpn_primary_eni.id
}

# Route VPN client subnet (10.8.0.0/24) through OpenVPN server for client-to-site access
resource "aws_route" "private_to_vpn_clients" {
  route_table_id         = module.vpc.private_route_table_ids[0]
  destination_cidr_block = "10.8.0.0/24"
  network_interface_id   = data.aws_network_interface.openvpn_primary_eni.id
}

