   output "bastion_sg_id" {
     value = aws_security_group.bastion.id
   }
   output "jenkins_sg_id" {
     value = aws_security_group.jenkins.id
   }