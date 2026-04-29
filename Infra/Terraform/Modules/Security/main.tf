resource "aws_security_group" "k8s" {
vpc_id = var.vpc_id
tags = {
Name = "k8s_security_group"
}


ingress {
from_port = 22
to_port = 22
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}


ingress {
from_port = 6443
to_port = 6443
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}



ingress {
from_port = 0
to_port = 0
protocol = "-1"
self = true
}

ingress {
from_port   = 5432
to_port     = 5432
protocol    = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}

ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
  from_port   = 30700
  to_port     = 32700
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

egress {
from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"]
}



/*ingress = {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }*/


}


# modules/security/variables.tf
variable "vpc_id" {}


# modules/security/outputs.tf
output "k8s_sg_id" {
value = aws_security_group.k8s.id
}