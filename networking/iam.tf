# -----------------------------------------------------------------------------
# IAM Role for SSM Session Manager
# All EC2 instances use this role to enable SSM access without SSH keys or
# bastion hosts. The AmazonSSMManagedInstanceCore policy grants the minimum
# permissions needed for SSM Agent to communicate with the SSM service.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ssm" {
  name = "${var.project_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 read-only access so we can test the S3 Gateway Endpoint
resource "aws_iam_role_policy_attachment" "s3_readonly" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.project_name}-ssm-profile"
  role = aws_iam_role.ssm.name
}
