terraform {
    backend "s3" {
        bucket = "kbucci-bucket-438438438"
        key    = "kbucci/terraform.tfstate"
        region = "us-east-1"
        encrypt = true
    }
}