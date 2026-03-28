# -----------------------------------------------------------------------------
# Read networking layer outputs directly from its S3 state.
# This replaces the need for 14+ TF_VAR_* passed between CI jobs.
# -----------------------------------------------------------------------------

data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "aws-labs/networking/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  net = data.terraform_remote_state.networking.outputs
}
