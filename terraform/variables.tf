variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in resource names and tags."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 chars: lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR no smaller than /20."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets over."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "instance_type" {
  description = "The whole platform (7 Spring Boot JVMs, Keycloak, Postgres, Mongo, RabbitMQ, Redis) runs as one Docker Compose stack needing about 10-12 GiB. t3.xlarge = 4 vCPU / 16 GiB."
  type        = string
  default     = "t3.xlarge"

  validation {
    condition     = can(regex("^(t3|t3a|m6i|m7i)\\.(xlarge|2xlarge)$", var.instance_type))
    error_message = "instance_type must have at least 16 GiB (t3/t3a/m6i/m7i, xlarge or 2xlarge)."
  }
}

variable "root_volume_size_gb" {
  description = "Size of the encrypted gp3 root volume in GiB."
  type        = number
  default     = 60

  validation {
    condition     = var.root_volume_size_gb >= 30 && var.root_volume_size_gb <= 500
    error_message = "root_volume_size_gb must be between 30 and 500."
  }
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that always points at the current Amazon Linux 2023 AMI."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "compose_repo_url" {
  description = "Public Git repository holding the docker-compose stack that the instance runs."
  type        = string
  default     = "https://github.com/FirasKhalife/fyp-grading-docker-compose.git"

  validation {
    condition     = startswith(var.compose_repo_url, "https://")
    error_message = "compose_repo_url must be an https:// URL."
  }
}

variable "enable_nat_gateway" {
  description = "Give the private subnet outbound internet (image pulls) through one NAT gateway."
  type        = bool
  default     = true
}
