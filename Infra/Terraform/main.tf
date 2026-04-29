
module "network" {
source =  "./Modules/Network"
vpc_cidr = var.vpc_cidr
}


module "security" {
source = "./Modules/Security"
vpc_id = module.network.vpc_id
}


module "compute" {
source = "./Modules/Compute"
subnet_id = module.network.subnet_id
security_group_id = module.security.k8s_sg_id
key_name = var.key_name
instance_type = var.instance_type
} 


/*resource "aws_s3_bucket""kbucci" {
  bucket = "kbucci-bucket-438438438"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}*/
