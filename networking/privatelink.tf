# =============================================================================
# AWS PRIVATELINK
# =============================================================================
# PrivateLink enables you to expose a service from one VPC to consumers in
# another VPC WITHOUT any network-level connectivity (no TGW, no peering,
# no internet). The consumer only gets access to the specific service port —
# not to the underlying VPC network.
#
# How it works:
#
# PRODUCER SIDE (vpc-app-b):
#   1. An internal NLB fronts the service (HTTP server on app-b-private)
#   2. An Endpoint Service wraps the NLB and makes it available via PrivateLink
#   3. The producer controls who can connect (acceptance_required, principals)
#
# CONSUMER SIDE (vpc-vendor):
#   1. An Interface VPC Endpoint is created pointing to the Endpoint Service
#   2. This creates an ENI in the consumer's subnet with a private IP
#   3. The consumer accesses the service via the endpoint's DNS name
#   4. Traffic flows: Consumer ENI → AWS backbone → NLB → backend instances
#
# KEY INSIGHT: vpc-vendor has NO TGW, NO peering, NO internet. Yet it can
# access the HTTP service in vpc-app-b. This is the power of PrivateLink —
# service-level access without network-level connectivity.
#
# Real-world use cases:
#   - SaaS providers exposing services to customers in their own VPCs
#   - Multi-tenant architectures with strict network isolation
#   - Cross-account service exposure without VPC peering
# =============================================================================

# -----------------------------------------------------------------------------
# PRODUCER: Network Load Balancer (NLB) in vpc-app-b
# NLB is required for PrivateLink — ALB is not supported.
# The NLB forwards TCP traffic on port 80 to the app-b-private instance.
# -----------------------------------------------------------------------------

resource "aws_lb" "privatelink" {
  name               = "${var.project_name}-pl-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.app_b_private.id]

  tags = { Name = "${var.project_name}-privatelink-nlb" }
}

resource "aws_lb_target_group" "privatelink" {
  name     = "${var.project_name}-pl-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.app_b.id

  health_check {
    protocol            = "TCP"
    port                = 80
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = { Name = "${var.project_name}-privatelink-tg" }
}

# NOTE: Target group attachment is in the compute layer (ec2.tf)
# because it references the EC2 instance created there.

resource "aws_lb_listener" "privatelink" {
  load_balancer_arn = aws_lb.privatelink.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.privatelink.arn
  }
}

# -----------------------------------------------------------------------------
# PRODUCER: VPC Endpoint Service
# This wraps the NLB and makes it available as a PrivateLink service.
# acceptance_required = false for lab simplicity. In production, set to true
# to manually approve each consumer connection.
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint_service" "app_b" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.privatelink.arn]

  tags = { Name = "${var.project_name}-privatelink-service" }
}

# -----------------------------------------------------------------------------
# CONSUMER: Interface VPC Endpoint in vpc-vendor
# This creates an ENI in the vendor's isolated subnet. The vendor accesses
# the service by hitting this ENI's DNS name on port 80.
# -----------------------------------------------------------------------------

resource "aws_security_group" "vendor_privatelink" {
  name_prefix = "${var.project_name}-vendor-pl-"
  vpc_id      = aws_vpc.vendor.id
  description = "Allow HTTP to PrivateLink endpoint in vpc-vendor"

  ingress {
    description = "HTTP from vpc-vendor"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidrs["vendor"]]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-vendor-privatelink-sg" }
}

resource "aws_vpc_endpoint" "vendor_privatelink" {
  vpc_id              = aws_vpc.vendor.id
  service_name        = aws_vpc_endpoint_service.app_b.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false # Custom service — no public DNS to override

  subnet_ids         = [aws_subnet.vendor_isolated.id]
  security_group_ids = [aws_security_group.vendor_privatelink.id]

  tags = { Name = "${var.project_name}-vendor-privatelink-vpce" }
}
