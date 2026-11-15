provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fyp-grading"
      ManagedBy = "opentofu"
      Env       = var.environment
    }
  }
}
