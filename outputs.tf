output "openvpn_public_ip" {
  description = "Public IP address of the OpenVPN server"
  value       = aws_instance.openvpn.public_ip
}

output "openvpn_public_dns" {
  description = "Public DNS name of the OpenVPN server"
  value       = aws_instance.openvpn.public_dns
}

output "openvpn_private_ip" {
  description = "Private IP address of the OpenVPN server"
  value       = aws_instance.openvpn.private_ip
}

output "ssh_connection_command" {
  description = "SSH command to connect to the OpenVPN server"
  value       = "ssh ubuntu@${aws_instance.openvpn.public_ip}"
}

output "ssh_agent_command" {
  description = "Add the private key to the SSH agent"
  value       = "ssh-add ${var.ssh_private_key_path}"
}

output "cluster_private_ip" {
  description = "Private IP address of the private EC2 instance"
  value       = aws_instance.cluster.private_ip
}

output "cluster_private_dns" {
  description = "Private DNS name of the private EC2 instance"
  value       = aws_instance.cluster.private_dns
}

output "cluster_ssh_command" {
  description = "SSH command to connect to the private EC2 instance"
  value       = "ssh -J ubuntu@${aws_instance.openvpn.public_ip} ubuntu@${aws_instance.cluster.private_ip}"
}
