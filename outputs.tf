# OpenVPN Server Outputs
output "openvpn_public_ip" {
  description = "Public IP address of the OpenVPN server"
  value       = aws_instance.openvpn.public_ip
}

output "openvpn_public_dns" {
  description = "Public DNS name of the OpenVPN server"
  value       = aws_instance.openvpn.public_dns
}

output "ssh_connection_command" {
  description = "SSH command to connect to the OpenVPN server"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.openvpn.public_ip}"
}

output "ssh_key_name" {
  description = "Name of the AWS key pair used for SSH access"
  value       = aws_key_pair.openvpn.key_name
}

output "openvpn_port" {
  description = "OpenVPN server port"
  value       = "1194"
}

output "openvpn_protocol" {
  description = "OpenVPN protocol"
  value       = "UDP"
}
