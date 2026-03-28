# =============================================================================
# VPC PEERING: vpc-shared ↔ vpc-app-a
# =============================================================================
# VPC Peering creates a direct, private network link between two VPCs.
# Unlike TGW, peering is:
#   - Free (no hourly charge, only data transfer costs)
#   - Not transitive (A↔B and B↔C does NOT give A↔C)
#   - Limited to 1:1 connections (doesn't scale for many VPCs)
#
# In this lab, we peer shared↔app-a IN ADDITION to the TGW connection.
# This demonstrates a real-world pattern: using peering for critical low-latency
# paths while TGW handles the broader mesh.
#
# KEY LEARNING: Route priority via longest prefix match
# vpc-app-a has two routes that could match shared's CIDR:
#   - 10.0.0.0/8  → TGW   (added in transit-gateway.tf)
#   - 10.0.0.0/16 → Peering (added below)
# Because /16 is more specific than /8, peering wins. This is how AWS route
# tables work: longest prefix match always takes priority.
# =============================================================================

resource "aws_vpc_peering_connection" "shared_to_app_a" {
  vpc_id      = aws_vpc.shared.id
  peer_vpc_id = aws_vpc.app_a.id
  auto_accept = true # Works because both VPCs are in the same account + region

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = { Name = "${var.project_name}-peer-shared-app-a" }
}

# -----------------------------------------------------------------------------
# Routes for peering: vpc-shared → vpc-app-a (10.1.0.0/16)
# Added to all 3 route tables in vpc-shared so every subnet tier can use peering
# -----------------------------------------------------------------------------
resource "aws_route" "shared_public_to_app_a_peer" {
  route_table_id            = aws_route_table.shared_public.id
  destination_cidr_block    = var.vpc_cidrs["app_a"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app_a.id
}

resource "aws_route" "shared_private_to_app_a_peer" {
  route_table_id            = aws_route_table.shared_private.id
  destination_cidr_block    = var.vpc_cidrs["app_a"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app_a.id
}

resource "aws_route" "shared_isolated_to_app_a_peer" {
  route_table_id            = aws_route_table.shared_isolated.id
  destination_cidr_block    = var.vpc_cidrs["app_a"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app_a.id
}

# -----------------------------------------------------------------------------
# Routes for peering: vpc-app-a → vpc-shared (10.0.0.0/16)
# The /16 peering route is MORE SPECIFIC than the /8 TGW route, so traffic
# to vpc-shared will prefer the peering path. This is longest prefix match.
# -----------------------------------------------------------------------------
resource "aws_route" "app_a_public_to_shared_peer" {
  route_table_id            = aws_route_table.app_a_public.id
  destination_cidr_block    = var.vpc_cidrs["shared"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app_a.id
}

resource "aws_route" "app_a_private_to_shared_peer" {
  route_table_id            = aws_route_table.app_a_private.id
  destination_cidr_block    = var.vpc_cidrs["shared"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app_a.id
}

resource "aws_route" "app_a_isolated_to_shared_peer" {
  route_table_id            = aws_route_table.app_a_isolated.id
  destination_cidr_block    = var.vpc_cidrs["shared"]
  vpc_peering_connection_id = aws_vpc_peering_connection.shared_to_app_a.id
}
