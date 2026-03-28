# =============================================================================
# EC2 INSTANCES & SECURITY GROUPS
# =============================================================================
# 6 test instances across 4 VPCs, each in a specific subnet tier to
# demonstrate different connectivity patterns.
#
# All instances use:
#   - Amazon Linux 2023 (SSM Agent pre-installed)
#   - IAM Instance Profile for SSM Session Manager (no SSH keys needed)
#   - t3.micro (free-tier eligible for 1 instance, ~$0.01/hr otherwise)
#
# Access all instances via:
#   aws ssm start-session --target <instance-id>
# =============================================================================

# -----------------------------------------------------------------------------
# SECURITY GROUPS
# -----------------------------------------------------------------------------
# Each VPC gets a security group that allows:
#   - ICMP (ping) from all internal VPCs (10.0.0.0/8) for connectivity testing
#   - HTTPS (443) outbound for SSM Agent communication
#   - All outbound traffic for general testing (curl, etc.)
# -----------------------------------------------------------------------------

resource "aws_security_group" "shared_instances" {
  name_prefix = "${var.project_name}-shared-ec2-"
  vpc_id      = local.net.vpc_shared_id
  description = "Security group for EC2 instances in vpc-shared"

  # ICMP from all internal VPCs for ping testing
  ingress {
    description = "ICMP from internal networks"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # HTTP for inbound testing on public instance (Test A2)
  ingress {
    description = "HTTP from anywhere (public instance inbound test)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-shared-ec2-sg" }
}

resource "aws_security_group" "app_a_instances" {
  name_prefix = "${var.project_name}-app-a-ec2-"
  vpc_id      = local.net.vpc_app_a_id
  description = "Security group for EC2 instances in vpc-app-a"

  ingress {
    description = "ICMP from internal networks"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-a-ec2-sg" }
}

resource "aws_security_group" "app_b_instances" {
  name_prefix = "${var.project_name}-app-b-ec2-"
  vpc_id      = local.net.vpc_app_b_id
  description = "Security group for EC2 instances in vpc-app-b"

  ingress {
    description = "ICMP from internal networks"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # HTTP for the PrivateLink service (NLB health checks + traffic)
  ingress {
    description = "HTTP from internal networks (PrivateLink service)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-b-ec2-sg" }
}

resource "aws_security_group" "vendor_instances" {
  name_prefix = "${var.project_name}-vendor-ec2-"
  vpc_id      = local.net.vpc_vendor_id
  description = "Security group for EC2 instances in vpc-vendor"

  ingress {
    description = "ICMP from internal networks"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-vendor-ec2-sg" }
}

# -----------------------------------------------------------------------------
# EC2 INSTANCES
# -----------------------------------------------------------------------------

# 1. shared-public: Public subnet, has public IP, tests IGW inbound/outbound
resource "aws_instance" "shared_public" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.net.subnet_shared_public_id
  iam_instance_profile   = local.net.ssm_instance_profile_name
  vpc_security_group_ids = [aws_security_group.shared_instances.id]

  # Simple HTTP server for inbound testing (Test A2)
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    echo "<h1>shared-public instance</h1><p>VPC: vpc-shared | Subnet: public | $(hostname -I)</p>" > /var/www/html/index.html
    systemctl enable --now httpd
  EOF

  tags = { Name = "${var.project_name}-shared-public" }
}

# 2. shared-isolated: Isolated subnet, no internet, tests VPC Endpoints
resource "aws_instance" "shared_isolated" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.net.subnet_shared_isolated_id
  iam_instance_profile   = local.net.ssm_instance_profile_name
  vpc_security_group_ids = [aws_security_group.shared_instances.id]

  tags = { Name = "${var.project_name}-shared-isolated" }
}

# 3. app-a-private: Private subnet, NAT outbound, tests peering priority
resource "aws_instance" "app_a_private" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.net.subnet_app_a_private_id
  iam_instance_profile   = local.net.ssm_instance_profile_name
  vpc_security_group_ids = [aws_security_group.app_a_instances.id]

  tags = { Name = "${var.project_name}-app-a-private" }
}

# 4. app-a-isolated: Isolated subnet, tests centralized SSM endpoints via TGW
resource "aws_instance" "app_a_isolated" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.net.subnet_app_a_isolated_id
  iam_instance_profile   = local.net.ssm_instance_profile_name
  vpc_security_group_ids = [aws_security_group.app_a_instances.id]

  tags = { Name = "${var.project_name}-app-a-isolated" }
}

# 5. app-b-private: Private subnet, runs HTTP server for PrivateLink
resource "aws_instance" "app_b_private" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.net.subnet_app_b_private_id
  iam_instance_profile   = local.net.ssm_instance_profile_name
  vpc_security_group_ids = [aws_security_group.app_b_instances.id]

  # HTTP server that will be exposed via NLB → PrivateLink
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    cat > /var/www/html/index.html <<'HTML'
    <h1>PrivateLink Service</h1>
    <p>You are accessing this service from vpc-app-b via AWS PrivateLink.</p>
    <p>This proves that PrivateLink provides service-level access without
    network-level connectivity between VPCs.</p>
    <p>Instance: app-b-private | VPC: vpc-app-b | Subnet: private</p>
    HTML
    systemctl enable --now httpd
  EOF

  tags = { Name = "${var.project_name}-app-b-private" }
}

# 6. vendor-isolated: Fully isolated, only PrivateLink access
resource "aws_instance" "vendor_isolated" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = local.net.subnet_vendor_isolated_id
  iam_instance_profile   = local.net.ssm_instance_profile_name
  vpc_security_group_ids = [aws_security_group.vendor_instances.id]

  tags = { Name = "${var.project_name}-vendor-isolated" }
}

# -----------------------------------------------------------------------------
# PRIVATELINK: Target Group Attachment
# Links the app-b-private EC2 instance to the NLB target group created in
# the networking layer. This is here because it depends on both layers.
# -----------------------------------------------------------------------------

resource "aws_lb_target_group_attachment" "privatelink" {
  target_group_arn = local.net.privatelink_target_group_arn
  target_id        = aws_instance.app_b_private.id
  port             = 80
}
