variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "bastion_ingress_cidr_blocks" {
  description = "CIDR blocks for bastion ingress"
  type        = list(string)
}