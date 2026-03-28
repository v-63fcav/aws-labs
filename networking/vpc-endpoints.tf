# =============================================================================
# VPC ENDPOINTS
# =============================================================================
# VPC Endpoints let you access AWS services (S3, SSM, STS, etc.) without
# traversing the public internet. There are two types:
#
# 1. GATEWAY ENDPOINTS (S3, DynamoDB only)
#    - Free — no hourly charge
#    - Works via route table entries (prefix list → endpoint)
#    - Traffic stays entirely on the AWS backbone network
#    - You won't see an ENI; it's implemented at the routing layer
#
# 2. INTERFACE ENDPOINTS (all other AWS services)
#    - Cost: ~$0.01/hr per AZ per endpoint
#    - Creates an ENI in your subnet with a private IP
#    - Supports Private DNS: the public service hostname (e.g.,
#      ssm.us-east-2.amazonaws.com) resolves to the private ENI IP
#    - This means existing code/tools work without any URL changes
#
# In this lab:
#   - vpc-shared gets ALL endpoints (S3 Gateway + SSM/STS Interface)
#   - vpc-vendor gets its own SSM Interface Endpoints (it has no TGW access)
#   - vpc-app-a can access shared's endpoints via TGW (cost optimization)
# =============================================================================

# -----------------------------------------------------------------------------
# SECURITY GROUP for Interface Endpoints
# Interface Endpoints need a security group that allows HTTPS (443) inbound
# from the VPC CIDR, since all AWS API calls use HTTPS.
# -----------------------------------------------------------------------------

resource "aws_security_group" "shared_endpoints" {
  name_prefix = "${var.project_name}-shared-vpce-"
  vpc_id      = aws_vpc.shared.id
  description = "Allow HTTPS to VPC Interface Endpoints in vpc-shared"

  ingress {
    description = "HTTPS from vpc-shared"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs["shared"]]
  }

  # Also allow HTTPS from TGW-connected VPCs so they can use centralized endpoints
  ingress {
    description = "HTTPS from vpc-app-a via TGW"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs["app_a"]]
  }

  ingress {
    description = "HTTPS from vpc-app-b via TGW"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs["app_b"]]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-shared-vpce-sg" }
}

resource "aws_security_group" "vendor_endpoints" {
  name_prefix = "${var.project_name}-vendor-vpce-"
  vpc_id      = aws_vpc.vendor.id
  description = "Allow HTTPS to VPC Interface Endpoints in vpc-vendor"

  ingress {
    description = "HTTPS from vpc-vendor"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs["vendor"]]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-vendor-vpce-sg" }
}

# =============================================================================
# GATEWAY ENDPOINT: S3 (in vpc-shared)
# =============================================================================
# The S3 Gateway Endpoint is completely free and adds a route to the route
# table that directs S3 traffic to the endpoint instead of the internet.
# You can verify this by checking the route table — you'll see a prefix list
# (pl-xxxxxxxx) entry pointing to the endpoint.
#
# We attach it to the isolated route table to prove that S3 access works
# even with zero internet connectivity. Also attach to public/private for
# convenience.
# =============================================================================

resource "aws_vpc_endpoint" "shared_s3" {
  vpc_id       = aws_vpc.shared.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.shared_public.id,
    aws_route_table.shared_private.id,
    aws_route_table.shared_isolated.id,
  ]

  tags = { Name = "${var.project_name}-shared-s3-gwep" }
}

# Also add S3 Gateway Endpoints to app-a and app-b isolated subnets
resource "aws_vpc_endpoint" "app_a_s3" {
  vpc_id       = aws_vpc.app_a.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.app_a_public.id,
    aws_route_table.app_a_private.id,
    aws_route_table.app_a_isolated.id,
  ]

  tags = { Name = "${var.project_name}-app-a-s3-gwep" }
}

resource "aws_vpc_endpoint" "app_b_s3" {
  vpc_id       = aws_vpc.app_b.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"

  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.app_b_public.id,
    aws_route_table.app_b_private.id,
    aws_route_table.app_b_isolated.id,
  ]

  tags = { Name = "${var.project_name}-app-b-s3-gwep" }
}

# =============================================================================
# INTERFACE ENDPOINTS: SSM (in vpc-shared)
# =============================================================================
# SSM Session Manager requires 3 Interface Endpoints to function:
#   1. ssm              — SSM API calls
#   2. ssmmessages      — Session Manager data channel
#   3. ec2messages      — EC2 message delivery (polling)
#
# Plus STS for IAM role credential exchange:
#   4. sts              — Security Token Service
#
# With private_dns_enabled = true, the public DNS names for these services
# (e.g., ssm.us-east-2.amazonaws.com) will resolve to the private ENI IPs
# instead of public IPs. This means SSM Agent works without any configuration
# changes — it just connects to the same hostname, but the traffic stays private.
# =============================================================================

resource "aws_vpc_endpoint" "shared_ssm" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.shared_isolated.id]
  security_group_ids = [aws_security_group.shared_endpoints.id]

  tags = { Name = "${var.project_name}-shared-ssm-vpce" }
}

resource "aws_vpc_endpoint" "shared_ssmmessages" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.shared_isolated.id]
  security_group_ids = [aws_security_group.shared_endpoints.id]

  tags = { Name = "${var.project_name}-shared-ssmmessages-vpce" }
}

resource "aws_vpc_endpoint" "shared_ec2messages" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.shared_isolated.id]
  security_group_ids = [aws_security_group.shared_endpoints.id]

  tags = { Name = "${var.project_name}-shared-ec2messages-vpce" }
}

resource "aws_vpc_endpoint" "shared_sts" {
  vpc_id              = aws_vpc.shared.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.shared_isolated.id]
  security_group_ids = [aws_security_group.shared_endpoints.id]

  tags = { Name = "${var.project_name}-shared-sts-vpce" }
}

# =============================================================================
# INTERFACE ENDPOINTS: SSM (in vpc-vendor)
# =============================================================================
# vpc-vendor has NO TGW connection, so it cannot route to shared's endpoints.
# It needs its own SSM Interface Endpoints for management access.
# This demonstrates the cost of network isolation — each isolated VPC needs
# its own set of endpoints ($0.01/hr × 4 endpoints × 1 AZ = $0.04/hr).
#
# Production recommendation: connect VPCs to TGW and centralize endpoints
# in a shared services VPC to reduce this cost.
# =============================================================================

resource "aws_vpc_endpoint" "vendor_ssm" {
  vpc_id              = aws_vpc.vendor.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.vendor_isolated.id]
  security_group_ids = [aws_security_group.vendor_endpoints.id]

  tags = { Name = "${var.project_name}-vendor-ssm-vpce" }
}

resource "aws_vpc_endpoint" "vendor_ssmmessages" {
  vpc_id              = aws_vpc.vendor.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.vendor_isolated.id]
  security_group_ids = [aws_security_group.vendor_endpoints.id]

  tags = { Name = "${var.project_name}-vendor-ssmmessages-vpce" }
}

resource "aws_vpc_endpoint" "vendor_ec2messages" {
  vpc_id              = aws_vpc.vendor.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.vendor_isolated.id]
  security_group_ids = [aws_security_group.vendor_endpoints.id]

  tags = { Name = "${var.project_name}-vendor-ec2messages-vpce" }
}

resource "aws_vpc_endpoint" "vendor_sts" {
  vpc_id              = aws_vpc.vendor.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.vendor_isolated.id]
  security_group_ids = [aws_security_group.vendor_endpoints.id]

  tags = { Name = "${var.project_name}-vendor-sts-vpce" }
}
