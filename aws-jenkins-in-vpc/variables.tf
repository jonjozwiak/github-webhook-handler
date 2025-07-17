variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "key_name" {
  description = "Name of the EC2 key pair"
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host"
  default     = "t3a.nano"
}

variable "jenkins_instance_type" {
  description = "Instance type for the Jenkins instance"
  default     = "t3a.small"
}

variable "bastion_ingress_cidr_blocks" {
  description = "CIDR blocks for bastion ingress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
