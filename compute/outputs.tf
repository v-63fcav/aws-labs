# =============================================================================
# OUTPUTS
# =============================================================================
# Outputs organized by what you need for each test scenario.
# After `terraform apply`, use these values directly in your test commands.
# =============================================================================

# --- Instance IDs (for SSM Session Manager) ---

output "instance_ids" {
  description = "Instance IDs for SSM Session Manager access"
  value = {
    shared_public   = aws_instance.shared_public.id
    shared_isolated = aws_instance.shared_isolated.id
    app_a_private   = aws_instance.app_a_private.id
    app_a_isolated  = aws_instance.app_a_isolated.id
    app_b_private   = aws_instance.app_b_private.id
    vendor_isolated = aws_instance.vendor_isolated.id
  }
}

# --- Private IPs (for ping/connectivity testing) ---

output "private_ips" {
  description = "Private IPs for connectivity testing (ping, curl, traceroute)"
  value = {
    shared_public   = aws_instance.shared_public.private_ip
    shared_isolated = aws_instance.shared_isolated.private_ip
    app_a_private   = aws_instance.app_a_private.private_ip
    app_a_isolated  = aws_instance.app_a_isolated.private_ip
    app_b_private   = aws_instance.app_b_private.private_ip
    vendor_isolated = aws_instance.vendor_isolated.private_ip
  }
}

# --- Public IP (for inbound testing) ---

output "shared_public_ip" {
  description = "Public IP of shared-public instance (for inbound HTTP test A2)"
  value       = aws_instance.shared_public.public_ip
}

# --- Quick-Start Test Commands ---

output "test_commands" {
  description = "Ready-to-run test commands — copy and paste these after terraform apply"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║                     QUICK-START TEST COMMANDS                    ║
    ╚══════════════════════════════════════════════════════════════════╝

    ── SSM Session Manager Access ──────────────────────────────────────
    aws ssm start-session --target ${aws_instance.shared_public.id}      # shared-public
    aws ssm start-session --target ${aws_instance.shared_isolated.id}    # shared-isolated
    aws ssm start-session --target ${aws_instance.app_a_private.id}     # app-a-private
    aws ssm start-session --target ${aws_instance.app_a_isolated.id}    # app-a-isolated
    aws ssm start-session --target ${aws_instance.app_b_private.id}     # app-b-private
    aws ssm start-session --target ${aws_instance.vendor_isolated.id}   # vendor-isolated

    ── Test A1: Public Outbound ────────────────────────────────────────
    # From shared-public:
    curl -s ifconfig.me    # Should return the instance's public IP

    ── Test A2: Public Inbound ─────────────────────────────────────────
    # From your browser or local machine:
    curl http://${aws_instance.shared_public.public_ip}

    ── Test A3: Private Outbound ───────────────────────────────────────
    # From app-a-private:
    curl -s ifconfig.me    # Should return the NAT Gateway's IP

    ── Test A4: Isolated Blocked ───────────────────────────────────────
    # From shared-isolated:
    curl -s --connect-timeout 5 ifconfig.me   # Should timeout

    ── Test B3: TGW Spoke-to-Spoke ─────────────────────────────────────
    # From app-a-private:
    ping -c 3 ${aws_instance.app_b_private.private_ip}    # Should succeed via TGW

    ── Test C1: Peering Route Priority ─────────────────────────────────
    # From app-a-private:
    traceroute ${aws_instance.shared_public.private_ip}    # Direct hop (peering, not TGW)

    ── Test D1: S3 Gateway Endpoint ────────────────────────────────────
    # From shared-isolated (no internet!):
    aws s3 ls s3://${local.net.test_bucket_name}
    aws s3 cp s3://${local.net.test_bucket_name}/test.txt -

    ── Test D2: SSM Interface Endpoints ────────────────────────────────
    # From shared-isolated:
    nslookup ssm.${var.aws_region}.amazonaws.com   # Should resolve to 10.0.x.x

    ── Test E1: PrivateLink ────────────────────────────────────────────
    # From vendor-isolated:
    curl http://${local.net.privatelink_endpoint_dns}

    ── Test E2: Isolation Proof ────────────────────────────────────────
    # From vendor-isolated (all should FAIL):
    ping -c 2 -W 2 ${aws_instance.shared_public.private_ip}     # Timeout
    ping -c 2 -W 2 ${aws_instance.app_a_private.private_ip}     # Timeout
    curl -s --connect-timeout 5 ifconfig.me                       # Timeout

  EOT
}
