# =============================================================================
# TRANSIT GATEWAY (TGW)
# =============================================================================
# A Transit Gateway acts as a regional network hub that interconnects VPCs
# (and on-premises networks). Instead of creating N*(N-1)/2 peering connections,
# you attach each VPC to the TGW and it handles routing between them.
#
# In this lab, 3 VPCs are attached: shared, app-a, app-b.
# vpc-vendor is intentionally NOT attached — it stays isolated and only
# accesses services via PrivateLink.
#
# TGW uses route tables to decide where to forward traffic. With
# default_route_table_association and default_route_table_propagation enabled,
# all attachments share a single route table and automatically propagate their
# CIDR routes — creating a full mesh between all attached VPCs.
# =============================================================================

resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.project_name} Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  # DNS support allows instances in attached VPCs to resolve public DNS
  # hostnames of instances in other attached VPCs to their private IPs
  dns_support = "enable"

  tags = { Name = "${var.project_name}-tgw" }
}

# -----------------------------------------------------------------------------
# TGW VPC Attachments
# Each attachment connects a VPC to the TGW. The subnet specified is where
# the TGW places its Elastic Network Interface (ENI). We use the isolated
# subnet since TGW ENIs don't need internet access.
# -----------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "shared" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared.id
  subnet_ids         = [aws_subnet.shared_isolated.id]

  dns_support = "enable"

  tags = { Name = "${var.project_name}-tgw-attach-shared" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "app_a" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.app_a.id
  subnet_ids         = [aws_subnet.app_a_isolated.id]

  dns_support = "enable"

  tags = { Name = "${var.project_name}-tgw-attach-app-a" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "app_b" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.app_b.id
  subnet_ids         = [aws_subnet.app_b_isolated.id]

  dns_support = "enable"

  tags = { Name = "${var.project_name}-tgw-attach-app-b" }
}

# -----------------------------------------------------------------------------
# VPC Route Table entries → TGW
# Each VPC needs routes pointing cross-VPC traffic (10.0.0.0/8) to the TGW.
# These routes go in ALL route tables (public, private, isolated) so that
# instances in any subnet tier can reach other VPCs.
# -----------------------------------------------------------------------------

# vpc-shared routes → TGW (all 3 route tables)
resource "aws_route" "shared_public_to_tgw" {
  route_table_id         = aws_route_table.shared_public.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.shared]
}

resource "aws_route" "shared_private_to_tgw" {
  route_table_id         = aws_route_table.shared_private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.shared]
}

resource "aws_route" "shared_isolated_to_tgw" {
  route_table_id         = aws_route_table.shared_isolated.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.shared]
}

# vpc-app-a routes → TGW (all 3 route tables)
resource "aws_route" "app_a_public_to_tgw" {
  route_table_id         = aws_route_table.app_a_public.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_a]
}

resource "aws_route" "app_a_private_to_tgw" {
  route_table_id         = aws_route_table.app_a_private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_a]
}

resource "aws_route" "app_a_isolated_to_tgw" {
  route_table_id         = aws_route_table.app_a_isolated.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_a]
}

# vpc-app-b routes → TGW (all 3 route tables)
resource "aws_route" "app_b_public_to_tgw" {
  route_table_id         = aws_route_table.app_b_public.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_b]
}

resource "aws_route" "app_b_private_to_tgw" {
  route_table_id         = aws_route_table.app_b_private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_b]
}

resource "aws_route" "app_b_isolated_to_tgw" {
  route_table_id         = aws_route_table.app_b_isolated.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.app_b]
}
