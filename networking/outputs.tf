# -----------------------------------------------------------------------------
# Outputs consumed by the compute layer
# -----------------------------------------------------------------------------

# VPC IDs (for security groups)
output "vpc_shared_id" {
  value = aws_vpc.shared.id
}

output "vpc_app_a_id" {
  value = aws_vpc.app_a.id
}

output "vpc_app_b_id" {
  value = aws_vpc.app_b.id
}

output "vpc_vendor_id" {
  value = aws_vpc.vendor.id
}

# Subnet IDs (for EC2 instance placement)
output "subnet_shared_public_id" {
  value = aws_subnet.shared_public.id
}

output "subnet_shared_isolated_id" {
  value = aws_subnet.shared_isolated.id
}

output "subnet_app_a_private_id" {
  value = aws_subnet.app_a_private.id
}

output "subnet_app_a_isolated_id" {
  value = aws_subnet.app_a_isolated.id
}

output "subnet_app_b_private_id" {
  value = aws_subnet.app_b_private.id
}

output "subnet_vendor_isolated_id" {
  value = aws_subnet.vendor_isolated.id
}

# IAM
output "ssm_instance_profile_name" {
  value = aws_iam_instance_profile.ssm.name
}

# PrivateLink target group (compute layer attaches the EC2 instance)
output "privatelink_target_group_arn" {
  value = aws_lb_target_group.privatelink.arn
}

# S3 test bucket
output "test_bucket_name" {
  value = aws_s3_bucket.test.id
}

# PrivateLink endpoint DNS (for test commands)
output "privatelink_endpoint_dns" {
  value = try(aws_vpc_endpoint.vendor_privatelink.dns_entry[0].dns_name, "")
}
