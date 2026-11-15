variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "az_count" {
  description = "Number of AZs; each gets one public and one private subnet."
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Create one shared NAT gateway for outbound access from private subnets."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention of VPC flow logs in CloudWatch."
  type        = number
  default     = 365
}

variable "flow_log_kms_key_arn" {
  description = "KMS key that encrypts the flow-log group."
  type        = string
}
