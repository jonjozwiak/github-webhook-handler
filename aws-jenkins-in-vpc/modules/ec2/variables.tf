variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "public_subnet_id" {
  description = "The ID of the public subnet"
  type        = string
}

variable "private_subnet_id" {
  description = "The ID of the private subnet"
  type        = string
}

variable "bastion_sg_id" {
  description = "The ID of the bastion security group"
  type        = string
}

variable "jenkins_sg_id" {
  description = "The ID of the Jenkins security group"
  type        = string
}

variable "key_name" {
  description = "The name of the EC2 key pair"
  type        = string
}

variable "bastion_instance_type" {
  description = "The instance type for the bastion host"
  type        = string
}

variable "jenkins_instance_type" {
  description = "The instance type for the Jenkins instance"
  type        = string
}