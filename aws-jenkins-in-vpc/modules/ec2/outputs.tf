output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "jenkins_private_ip" {
  description = "Private IP address of the Jenkins instance"
  value       = aws_instance.jenkins.private_ip
}