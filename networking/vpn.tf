# =============================================================================
# SITE-TO-SITE VPN (Simulated Direct Connect)
# =============================================================================
# AWS Direct Connect (DX) provides a dedicated physical network connection
# from your on-premises data center to AWS. Since DX requires physical
# infrastructure (a cross-connect at a DX location), we simulate the
# same pattern using a Site-to-Site VPN attached to the Transit Gateway.
#
# The architecture is identical:
#   - Both DX and VPN can attach to a Transit Gateway
#   - Both use the same TGW route table for traffic forwarding
#   - Both provide private connectivity to all VPCs attached to the TGW
#
# To convert this to real Direct Connect, you would:
#   1. Replace aws_customer_gateway + aws_vpn_connection with:
#      - aws_dx_connection (or use a hosted connection from a partner)
#      - aws_dx_gateway
#      - aws_dx_gateway_association (to the TGW)
#   2. The TGW attachment and routing remains the same
#
# This resource is OPTIONAL (gated by var.create_vpn) because:
#   - VPN costs ~$0.05/hr even with tunnel DOWN
#   - The tunnel will never come UP without a real remote endpoint
#   - It's primarily useful for examining the resource structure
#
# The Customer Gateway IP (198.51.100.1) is from RFC 5737 — a documentation-
# reserved range that will never route on the public internet.
# =============================================================================

resource "aws_customer_gateway" "simulated_onprem" {
  count = var.create_vpn ? 1 : 0

  bgp_asn    = 65000 # Private ASN for the simulated on-premises router
  ip_address = "198.51.100.1"
  type       = "ipsec.1"

  tags = { Name = "${var.project_name}-simulated-onprem-cgw" }
}

resource "aws_vpn_connection" "simulated_dx" {
  count = var.create_vpn ? 1 : 0

  customer_gateway_id = aws_customer_gateway.simulated_onprem[0].id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  # Static routing for simplicity (real DX typically uses BGP)
  static_routes_only = true

  tags = { Name = "${var.project_name}-simulated-dx-vpn" }
}
