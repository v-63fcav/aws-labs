# =============================================================================
# S3 TEST BUCKET
# =============================================================================
# A simple S3 bucket with a test object. Used to validate that the S3 Gateway
# Endpoint works from isolated subnets (zero internet access).
#
# Test command (from shared-isolated):
#   aws s3 ls s3://<bucket-name>
#   aws s3 cp s3://<bucket-name>/test.txt -
#
# If this works from an isolated subnet, it proves the Gateway Endpoint is
# routing S3 traffic privately without internet access.
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "test" {
  bucket        = "${var.project_name}-test-${random_id.bucket_suffix.hex}"
  force_destroy = true # Lab bucket — allow terraform destroy to clean up

  tags = { Name = "${var.project_name}-test-bucket" }
}

resource "aws_s3_bucket_public_access_block" "test" {
  bucket = aws_s3_bucket.test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "test_file" {
  bucket  = aws_s3_bucket.test.id
  key     = "test.txt"
  content = <<-EOF
    SUCCESS! You accessed this S3 object via the S3 Gateway Endpoint.
    This traffic never left the AWS network — no internet gateway or
    NAT gateway was involved.

    Bucket: ${aws_s3_bucket.test.id}
    Region: ${data.aws_region.current.name}
  EOF

  tags = { Name = "gateway-endpoint-test-file" }
}
