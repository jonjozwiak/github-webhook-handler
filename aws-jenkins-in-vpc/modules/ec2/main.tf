data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    #values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.bastion_instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.bastion_sg_id]

  tags = {
    Name = "jenkins-bastion"
  }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.jenkins_instance_type
  key_name               = var.key_name
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.jenkins_sg_id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y wget git
              sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              # Disable tmp mount in AL2023 as it is only 1GB and breaks Jenkins agent
              sudo systemctl disable tmp.mount
              sudo systemctl stop tmp.mount
              sudo systemctl mask tmp.mount
              sudo yum upgrade -y
              sudo yum install java-17-amazon-corretto -y
              sudo yum install jenkins -y
              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              # Installing python only for my sample app
              sudo yum install python3 python3-pip -y
              EOF

  tags = {
    Name = "jenkins-server"
  }
}
