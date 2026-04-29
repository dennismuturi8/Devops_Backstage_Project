resource "aws_vpc" "KBUCCI_VPC" {
cidr_block = var.vpc_cidr
enable_dns_support = true
enable_dns_hostnames = true
tags = {
Name = "KBUCCI_VPC"
}
}

# Fetch available availability zones
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_subnet" "KBUCCI_VPC_Subnet" {
vpc_id = aws_vpc.KBUCCI_VPC.id
cidr_block = "10.0.2.0/24"
availability_zone = data.aws_availability_zones.available.names[0]
map_public_ip_on_launch = true
tags = {
Name = "KBUCCI_VPC_Subnet"
}
}


resource "aws_internet_gateway" "KBUCCI_VPC_Internet_Gateway" {
vpc_id = aws_vpc.KBUCCI_VPC.id

tags = {
Name = "KBUCCI_VPC_Internet_Gateway"
}
}


resource "aws_route_table" "KBUCCI_VPC_Route_Table" {
vpc_id = aws_vpc.KBUCCI_VPC.id
route {
cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.KBUCCI_VPC_Internet_Gateway.id
}
}


resource "aws_route_table_association" "KBUCCI_VPC_Route_Table_Association" {
subnet_id = aws_subnet.KBUCCI_VPC_Subnet.id
route_table_id = aws_route_table.KBUCCI_VPC_Route_Table.id
}


# modules/network/variables.tf
variable "vpc_cidr" {}


# modules/network/outputs.tf
output "vpc_id" {
value = aws_vpc.KBUCCI_VPC.id
}


output "subnet_id" {
value = aws_subnet.KBUCCI_VPC_Subnet.id
}