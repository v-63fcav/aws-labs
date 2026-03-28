variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "aws-networking-lab"
}

variable "instance_type" {
  description = "EC2 instance type for all test instances"
  type        = string
  default     = "t3.micro"
}

# -----------------------------------------------------------------------------
# Remote state — the only cross-layer input.
# Injected via TF_VAR_state_bucket in CI or a .tfvars file locally.
# -----------------------------------------------------------------------------
variable "state_bucket" {
  description = "S3 bucket storing the Terraform remote state"
  type        = string
}
