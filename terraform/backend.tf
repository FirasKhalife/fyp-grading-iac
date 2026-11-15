# Partial configuration: the bucket name and region are supplied at init time.
#   tofu init -backend-config=backend.hcl      (copy backend.hcl.example first)
# CI and local checks use `tofu init -backend=false`, so no AWS access is needed.
terraform {
  backend "s3" {
    key          = "fyp-grading/demo/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # native S3 locking, no DynamoDB table needed
  }
}
