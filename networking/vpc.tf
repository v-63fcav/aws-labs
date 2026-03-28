# =============================================================================
# VPC INFRASTRUCTURE
# =============================================================================
# 4 VPCs with up to 3 subnet tiers each (public, private, isolated).
# Each tier has a different route table that controls internet access:
#   - Public:   0.0.0.0/0 → IGW  (inbound + outbound internet)
#   - Private:  0.0.0.0/0 → NAT  (outbound-only internet)
#   - Isolated: no default route  (zero internet, VPC Endpoints only)
# =============================================================================

# =============================================================================
# VPC: SHARED SERVICES (10.0.0.0/16)
# Central hub — hosts VPC Endpoints, connects to all spokes via TGW and
# peering. Has all 3 subnet tiers.
# =============================================================================
resource "aws_vpc" "shared" {
  cidr_block           = var.vpc_cidrs["shared"]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc-shared" }
}

resource "aws_subnet" "shared_public" {
  vpc_id                  = aws_vpc.shared.id
  cidr_block              = local.subnets.shared.public
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-shared-public" }
}

resource "aws_subnet" "shared_private" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = local.subnets.shared.private
  availability_zone = local.az

  tags = { Name = "${var.project_name}-shared-private" }
}

resource "aws_subnet" "shared_isolated" {
  vpc_id            = aws_vpc.shared.id
  cidr_block        = local.subnets.shared.isolated
  availability_zone = local.az

  tags = { Name = "${var.project_name}-shared-isolated" }
}

resource "aws_internet_gateway" "shared" {
  vpc_id = aws_vpc.shared.id
  tags   = { Name = "${var.project_name}-shared-igw" }
}

resource "aws_eip" "shared_nat" {
  count  = var.create_nat_gateways ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.project_name}-shared-nat-eip" }
}

resource "aws_nat_gateway" "shared" {
  count         = var.create_nat_gateways ? 1 : 0
  allocation_id = aws_eip.shared_nat[0].id
  subnet_id     = aws_subnet.shared_public.id

  tags       = { Name = "${var.project_name}-shared-nat" }
  depends_on = [aws_internet_gateway.shared]
}

# --- Route Tables for vpc-shared ---

# Public: 0.0.0.0/0 → IGW
resource "aws_route_table" "shared_public" {
  vpc_id = aws_vpc.shared.id
  tags   = { Name = "${var.project_name}-shared-public-rt" }
}

resource "aws_route" "shared_public_igw" {
  route_table_id         = aws_route_table.shared_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.shared.id
}

resource "aws_route_table_association" "shared_public" {
  subnet_id      = aws_subnet.shared_public.id
  route_table_id = aws_route_table.shared_public.id
}

# Private: 0.0.0.0/0 → NAT Gateway
resource "aws_route_table" "shared_private" {
  vpc_id = aws_vpc.shared.id
  tags   = { Name = "${var.project_name}-shared-private-rt" }
}

resource "aws_route" "shared_private_nat" {
  count                  = var.create_nat_gateways ? 1 : 0
  route_table_id         = aws_route_table.shared_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.shared[0].id
}

resource "aws_route_table_association" "shared_private" {
  subnet_id      = aws_subnet.shared_private.id
  route_table_id = aws_route_table.shared_private.id
}

# Isolated: NO default route — only internal routes (TGW, peering, endpoints)
resource "aws_route_table" "shared_isolated" {
  vpc_id = aws_vpc.shared.id
  tags   = { Name = "${var.project_name}-shared-isolated-rt" }
}

resource "aws_route_table_association" "shared_isolated" {
  subnet_id      = aws_subnet.shared_isolated.id
  route_table_id = aws_route_table.shared_isolated.id
}

# =============================================================================
# VPC: APP-A (10.1.0.0/16)
# Spoke VPC for "Application Team A". Connected to TGW and directly peered
# with vpc-shared for a low-latency path. Full 3-tier subnet design.
# =============================================================================
resource "aws_vpc" "app_a" {
  cidr_block           = var.vpc_cidrs["app_a"]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc-app-a" }
}

resource "aws_subnet" "app_a_public" {
  vpc_id                  = aws_vpc.app_a.id
  cidr_block              = local.subnets.app_a.public
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-app-a-public" }
}

resource "aws_subnet" "app_a_private" {
  vpc_id            = aws_vpc.app_a.id
  cidr_block        = local.subnets.app_a.private
  availability_zone = local.az

  tags = { Name = "${var.project_name}-app-a-private" }
}

resource "aws_subnet" "app_a_isolated" {
  vpc_id            = aws_vpc.app_a.id
  cidr_block        = local.subnets.app_a.isolated
  availability_zone = local.az

  tags = { Name = "${var.project_name}-app-a-isolated" }
}

resource "aws_internet_gateway" "app_a" {
  vpc_id = aws_vpc.app_a.id
  tags   = { Name = "${var.project_name}-app-a-igw" }
}

resource "aws_eip" "app_a_nat" {
  count  = var.create_nat_gateways ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.project_name}-app-a-nat-eip" }
}

resource "aws_nat_gateway" "app_a" {
  count         = var.create_nat_gateways ? 1 : 0
  allocation_id = aws_eip.app_a_nat[0].id
  subnet_id     = aws_subnet.app_a_public.id

  tags       = { Name = "${var.project_name}-app-a-nat" }
  depends_on = [aws_internet_gateway.app_a]
}

# --- Route Tables for vpc-app-a ---

resource "aws_route_table" "app_a_public" {
  vpc_id = aws_vpc.app_a.id
  tags   = { Name = "${var.project_name}-app-a-public-rt" }
}

resource "aws_route" "app_a_public_igw" {
  route_table_id         = aws_route_table.app_a_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app_a.id
}

resource "aws_route_table_association" "app_a_public" {
  subnet_id      = aws_subnet.app_a_public.id
  route_table_id = aws_route_table.app_a_public.id
}

resource "aws_route_table" "app_a_private" {
  vpc_id = aws_vpc.app_a.id
  tags   = { Name = "${var.project_name}-app-a-private-rt" }
}

resource "aws_route" "app_a_private_nat" {
  count                  = var.create_nat_gateways ? 1 : 0
  route_table_id         = aws_route_table.app_a_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app_a[0].id
}

resource "aws_route_table_association" "app_a_private" {
  subnet_id      = aws_subnet.app_a_private.id
  route_table_id = aws_route_table.app_a_private.id
}

resource "aws_route_table" "app_a_isolated" {
  vpc_id = aws_vpc.app_a.id
  tags   = { Name = "${var.project_name}-app-a-isolated-rt" }
}

resource "aws_route_table_association" "app_a_isolated" {
  subnet_id      = aws_subnet.app_a_isolated.id
  route_table_id = aws_route_table.app_a_isolated.id
}

# =============================================================================
# VPC: APP-B (10.2.0.0/16)
# Spoke VPC for "Application Team B". Connected to TGW. Hosts the internal
# HTTP service exposed via PrivateLink to the vendor VPC.
# =============================================================================
resource "aws_vpc" "app_b" {
  cidr_block           = var.vpc_cidrs["app_b"]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc-app-b" }
}

resource "aws_subnet" "app_b_public" {
  vpc_id                  = aws_vpc.app_b.id
  cidr_block              = local.subnets.app_b.public
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-app-b-public" }
}

resource "aws_subnet" "app_b_private" {
  vpc_id            = aws_vpc.app_b.id
  cidr_block        = local.subnets.app_b.private
  availability_zone = local.az

  tags = { Name = "${var.project_name}-app-b-private" }
}

resource "aws_subnet" "app_b_isolated" {
  vpc_id            = aws_vpc.app_b.id
  cidr_block        = local.subnets.app_b.isolated
  availability_zone = local.az

  tags = { Name = "${var.project_name}-app-b-isolated" }
}

resource "aws_internet_gateway" "app_b" {
  vpc_id = aws_vpc.app_b.id
  tags   = { Name = "${var.project_name}-app-b-igw" }
}

resource "aws_eip" "app_b_nat" {
  count  = var.create_nat_gateways ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.project_name}-app-b-nat-eip" }
}

resource "aws_nat_gateway" "app_b" {
  count         = var.create_nat_gateways ? 1 : 0
  allocation_id = aws_eip.app_b_nat[0].id
  subnet_id     = aws_subnet.app_b_public.id

  tags       = { Name = "${var.project_name}-app-b-nat" }
  depends_on = [aws_internet_gateway.app_b]
}

# --- Route Tables for vpc-app-b ---

resource "aws_route_table" "app_b_public" {
  vpc_id = aws_vpc.app_b.id
  tags   = { Name = "${var.project_name}-app-b-public-rt" }
}

resource "aws_route" "app_b_public_igw" {
  route_table_id         = aws_route_table.app_b_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app_b.id
}

resource "aws_route_table_association" "app_b_public" {
  subnet_id      = aws_subnet.app_b_public.id
  route_table_id = aws_route_table.app_b_public.id
}

resource "aws_route_table" "app_b_private" {
  vpc_id = aws_vpc.app_b.id
  tags   = { Name = "${var.project_name}-app-b-private-rt" }
}

resource "aws_route" "app_b_private_nat" {
  count                  = var.create_nat_gateways ? 1 : 0
  route_table_id         = aws_route_table.app_b_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app_b[0].id
}

resource "aws_route_table_association" "app_b_private" {
  subnet_id      = aws_subnet.app_b_private.id
  route_table_id = aws_route_table.app_b_private.id
}

resource "aws_route_table" "app_b_isolated" {
  vpc_id = aws_vpc.app_b.id
  tags   = { Name = "${var.project_name}-app-b-isolated-rt" }
}

resource "aws_route_table_association" "app_b_isolated" {
  subnet_id      = aws_subnet.app_b_isolated.id
  route_table_id = aws_route_table.app_b_isolated.id
}

# =============================================================================
# VPC: VENDOR (10.3.0.0/16)
# Simulates an external vendor/partner. Intentionally ISOLATED ONLY — no IGW,
# no NAT, no TGW. Can only reach vpc-app-b's service via PrivateLink.
# Has its own SSM Interface Endpoints for management access.
# =============================================================================
resource "aws_vpc" "vendor" {
  cidr_block           = var.vpc_cidrs["vendor"]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc-vendor" }
}

resource "aws_subnet" "vendor_isolated" {
  vpc_id            = aws_vpc.vendor.id
  cidr_block        = local.subnets.vendor.isolated
  availability_zone = local.az

  tags = { Name = "${var.project_name}-vendor-isolated" }
}

# Vendor has only one route table — isolated, no internet routes at all
resource "aws_route_table" "vendor_isolated" {
  vpc_id = aws_vpc.vendor.id
  tags   = { Name = "${var.project_name}-vendor-isolated-rt" }
}

resource "aws_route_table_association" "vendor_isolated" {
  subnet_id      = aws_subnet.vendor_isolated.id
  route_table_id = aws_route_table.vendor_isolated.id
}
