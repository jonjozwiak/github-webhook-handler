provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "security_groups" {
  source = "./modules/security_groups"

  vpc_id                      = module.vpc.vpc_id
  bastion_ingress_cidr_blocks = var.bastion_ingress_cidr_blocks
}

module "ec2" {
  source = "./modules/ec2"

  vpc_id                  = module.vpc.vpc_id
  public_subnet_id        = module.vpc.public_subnet_ids[0]
  private_subnet_id       = module.vpc.private_subnet_ids[0]
  bastion_sg_id           = module.security_groups.bastion_sg_id
  jenkins_sg_id           = module.security_groups.jenkins_sg_id
  key_name                = var.key_name
  bastion_instance_type   = var.bastion_instance_type
  jenkins_instance_type   = var.jenkins_instance_type
}

output "bastion_public_ip" {
  value = module.ec2.bastion_public_ip
}

output "jenkins_private_ip" {
  value = module.ec2.jenkins_private_ip
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

