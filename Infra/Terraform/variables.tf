variable "aws_region" {
default = "us-east-1"
}


variable "key_name" {
description = "Existing EC2 keypair"
type = string
}


variable "instance_type" {
description = "EC2 instance type"
type        = string
}


variable "vpc_cidr" {
description = "CIDR block for the VPC"
type        = string
}

variable "private_key_path" {
  description = "Path to the private key file for SSH access"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for the EC2 instances"
  type        = string
}