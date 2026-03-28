# AWS Networking Lab

A hands-on Terraform lab that deploys a multi-VPC environment to demonstrate and test 5 core AWS networking services:

- **Transit Gateway (TGW)** — hub-and-spoke connectivity
- **VPC Peering** — direct VPC-to-VPC links
- **VPC Endpoints** — private access to AWS services (Gateway + Interface types)
- **AWS PrivateLink** — service exposure without network merging
- **Site-to-Site VPN** — simulated Direct Connect for hybrid cloud

Each service is used where it naturally makes sense — not forced — so you can understand *why* and *when* to use each one.

---

## Architecture

```
                          +----------------------------------+
                          |       TRANSIT GATEWAY (TGW)       |
                          |          Hub & Spoke              |
                          +--+-----------+-----------+-------+
                             |           |           |
                      +------+----+ +----+-----+ +---+-------+
                      |VPC-SHARED | |VPC-APP-A | |VPC-APP-B  |
                      |10.0.0.0/16| |10.1.0/16 | |10.2.0/16  |
                      | Shared    | | App      | | App       |
                      | Services  | | Team A   | | Team B    |
                      +-----+-----+ +----+-----+ +-----+-----+
                            |            |              |
                       VPC Peering-------+        PrivateLink
                       (direct, low-latency)           |
                                                 +-----+-----+
                                                 |VPC-VENDOR |
                                                 |10.3.0/16  |
                                                 | External  |
                                                 | Partner   |
                                                 +-----------+

    VPC Endpoints (Gateway S3 + Interface SSM/STS) on VPC-SHARED + VPC-VENDOR
    Site-to-Site VPN on TGW (simulates Direct Connect) -- optional
```

### VPC Roles

| VPC | CIDR | Role | Why It Exists |
|-----|------|------|---------------|
| **vpc-shared** | 10.0.0.0/16 | Central shared services | Hub for TGW, hosts centralized VPC Endpoints, directly peered with app-a |
| **vpc-app-a** | 10.1.0.0/16 | Application Team A | TGW spoke + direct peering with shared (demonstrates route priority) |
| **vpc-app-b** | 10.2.0.0/16 | Application Team B | TGW spoke + exposes HTTP service via PrivateLink |
| **vpc-vendor** | 10.3.0.0/16 | External vendor/partner | Completely isolated — NO TGW, NO peering, only PrivateLink access |

### Why Each Service Is Used Where It Is

| Service | Where | Why (not just how) |
|---------|-------|--------------------|
| **TGW** | shared ↔ app-a ↔ app-b | When you have 3+ VPCs that need any-to-any connectivity, TGW scales linearly (N attachments) instead of exponentially (N×(N-1)/2 peerings). It also supports transitive routing — spoke A can reach spoke B through the hub. |
| **VPC Peering** | shared ↔ app-a (additionally) | For a critical, latency-sensitive path between two specific VPCs. Peering is free, has lower latency than TGW, and coexists with TGW. The /16 peering route wins over the /8 TGW route via longest prefix match. |
| **VPC Endpoints (Gateway)** | S3 in all VPCs | Gateway Endpoints for S3 are **free** and route S3 traffic through the AWS backbone instead of the internet. No NAT Gateway needed for S3 access. |
| **VPC Endpoints (Interface)** | SSM/STS in shared + vendor | Interface Endpoints create an ENI with a private IP. When Private DNS is enabled, `ssm.us-east-2.amazonaws.com` resolves to the private IP instead of the public one. This enables SSM Session Manager to work without any internet access. |
| **PrivateLink** | app-b → vendor | PrivateLink lets you expose a service to another VPC without any network-level connectivity. The vendor can only reach the service's port (80) — they cannot ping, scan, or access anything else in vpc-app-b. |
| **VPN** | TGW attachment | Same attachment pattern as Direct Connect. In production, you'd replace the VPN with a DX Gateway associated to the TGW. |

---

## Subnet Design: 3 Tiers

Each VPC (except vendor) has 3 subnet tiers that demonstrate different internet access patterns:

```
+---------------------------------------------------------------------+
|                         VPC (e.g., 10.0.0.0/16)                     |
|                                                                     |
|  +-----------------+  +-----------------+  +-----------------+      |
|  |  PUBLIC SUBNET  |  |  PRIVATE SUBNET |  | ISOLATED SUBNET |      |
|  |  10.0.1.0/24    |  |  10.0.2.0/24    |  |  10.0.3.0/24    |      |
|  |                 |  |                 |  |                 |      |
|  |  Route:         |  |  Route:         |  |  Route:         |      |
|  |  0.0.0.0/0->IGW |  |  0.0.0.0/0->NAT |  |  (no default)   |      |
|  |                 |  |                 |  |                 |      |
|  |  Internet:      |  |  Internet:      |  |  Internet:      |      |
|  |  IN + OUT [YES] |  |  OUT only [YES] |  |  NONE [NO]      |      |
|  |                 |  |  IN blocked [NO]|  |                 |      |
|  +-----------------+  +-----------------+  +-----------------+      |
|                                                                     |
|  All tiers: 10.0.0.0/8 -> TGW (cross-VPC), Peering routes, S3 GWEP |
+---------------------------------------------------------------------+
```

### How Each Tier Works

**Public Subnet** (`0.0.0.0/0 → Internet Gateway`)
- Instances can have public IPs (auto-assigned or Elastic IP)
- Full bidirectional internet: outbound via IGW, inbound via public IP + security group
- Use case: load balancers, bastion hosts, NAT Gateways themselves
- The IGW performs 1:1 NAT between public and private IPs — it doesn't change the packet, just translates the address

**Private Subnet** (`0.0.0.0/0 → NAT Gateway`)
- Instances have only private IPs
- Outbound internet works via NAT Gateway (source IP becomes the NAT GW's Elastic IP)
- Inbound from internet is impossible — NAT only tracks outbound-initiated connections
- Use case: application servers that need to download packages, call external APIs, etc.
- This is the most common subnet tier in production

**Isolated Subnet** (no `0.0.0.0/0` route)
- Zero internet access in either direction
- Can only reach AWS services via VPC Endpoints
- Can still reach other VPCs via TGW/Peering (those routes exist)
- Use case: databases, internal processing, sensitive workloads
- If you try `curl ifconfig.me`, it will timeout — there is literally no route to the internet

### Subnet Map

| VPC | Public | Private | Isolated |
|-----|--------|---------|----------|
| vpc-shared (10.0.0.0/16) | 10.0.1.0/24 | 10.0.2.0/24 | 10.0.3.0/24 |
| vpc-app-a (10.1.0.0/16) | 10.1.1.0/24 | 10.1.2.0/24 | 10.1.3.0/24 |
| vpc-app-b (10.2.0.0/16) | 10.2.1.0/24 | 10.2.2.0/24 | 10.2.3.0/24 |
| vpc-vendor (10.3.0.0/16) | — | — | 10.3.1.0/24 |

> **vpc-vendor** has isolated subnet only — no IGW, no NAT, no internet. It represents an external partner that should have zero network access except via PrivateLink.

---

## Test Instances

| Instance | VPC | Subnet Tier | Public IP | Purpose |
|----------|-----|-------------|-----------|---------|
| `shared-public` | vpc-shared | Public | Yes | IGW inbound+outbound, TGW, peering |
| `shared-isolated` | vpc-shared | Isolated | No | VPC Endpoints (S3, SSM), zero internet proof |
| `app-a-private` | vpc-app-a | Private | No | NAT outbound, TGW, peering route priority |
| `app-a-isolated` | vpc-app-a | Isolated | No | Centralized SSM endpoints via TGW |
| `app-b-private` | vpc-app-b | Private | No | HTTP server behind NLB (PrivateLink target) |
| `vendor-isolated` | vpc-vendor | Isolated | No | PrivateLink consumer, full isolation proof |

All instances are accessed via **SSM Session Manager** — no SSH keys, no bastion hosts, no public IPs needed (except shared-public for inbound testing).

---

## Prerequisites

1. **AWS CLI v2** configured with appropriate credentials
2. **Terraform >= 1.5** installed
3. **AWS IAM Permissions** — the deploying user/role needs permissions for:
   - VPC, Subnets, Route Tables, Internet Gateways, NAT Gateways
   - EC2 (instances, security groups, EIPs)
   - Transit Gateway
   - VPC Peering
   - VPC Endpoints
   - Elastic Load Balancing (NLB)
   - S3
   - IAM (roles, instance profiles)
   - SSM (for session manager access)
   - VPN (if `create_vpn = true`)
4. **Session Manager Plugin** for AWS CLI — [install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

---

## Project Structure

The project is split into two Terraform layers with independent state files:

```
networking/    → VPCs, TGW, Peering, Endpoints, PrivateLink, VPN, IAM, S3
compute/       → EC2 instances, Security Groups, PrivateLink target attachment
```

**Deploy order**: networking → compute
**Destroy order**: compute → networking (reverse)

The `compute` layer reads all outputs from `networking` via `terraform_remote_state`,
so there is no manual output passing — any new output added to `networking/outputs.tf`
is automatically available in `compute` as `local.net.<output_name>`.

### Cross-Layer Communication via `terraform_remote_state`

Instead of passing dozens of `TF_VAR_*` environment variables between CI jobs, this
project uses `terraform_remote_state` — a Terraform-native mechanism where one layer
reads outputs directly from another layer's state file in S3.

**How it works:**

1. `networking/outputs.tf` declares outputs (VPC IDs, subnet IDs, etc.)
2. `terraform apply` in networking writes these outputs to S3 (`aws-labs/networking/terraform.tfstate`)
3. `compute/remote-state.tf` reads that state file via the `terraform_remote_state` data source
4. `compute/` code references values as `local.net.<output_name>` (alias for the long data source path)
5. The only variable the CI needs to pass is `state_bucket` — the S3 bucket name

```
networking/outputs.tf          compute/remote-state.tf          compute/ec2.tf
  output "vpc_shared_id"  ──►   data "terraform_remote_state"  ──►  local.net.vpc_shared_id
  (written to S3 state)          "networking" { bucket = ... }       (used in resources)
```

**Is this production-ready?**

Yes. `terraform_remote_state` is the standard Terraform pattern for multi-layer
architectures and is widely used in production environments. Key considerations:

- **When to use it**: Same team/org owns both layers, same AWS account, state is in
  a shared backend (S3, GCS, Terraform Cloud). This is the most common case for
  infrastructure layering (network → compute → apps).
- **When NOT to use it**: Cross-team boundaries where you don't want to expose the
  full state file. `terraform_remote_state` grants read access to _all_ outputs in
  the state, not just the ones you need. For cross-team scenarios, prefer
  [`terraform_remote_state` with Terraform Cloud workspaces](https://developer.hashicorp.com/terraform/language/state/remote-state-data)
  (which scopes access) or use SSM Parameter Store / Secrets Manager as an
  intermediary — the producer writes values, the consumer reads them, and IAM
  controls who can access what.
- **Alternatives in production**:
  - **SSM Parameter Store**: Producer writes `aws_ssm_parameter`, consumer reads via
    `data.aws_ssm_parameter`. Fine-grained IAM control, works cross-account.
  - **Terraform Cloud/Enterprise**: Native workspace outputs with RBAC.
  - **CI job outputs** (what sl-eks uses): Necessary when the Terraform _provider_
    configuration itself depends on outputs (e.g., Helm provider needs the EKS
    endpoint). `terraform_remote_state` cannot be used in provider blocks because
    data sources are resolved after providers are configured.

For this lab (single account, single team, pure AWS provider), `terraform_remote_state`
is the simplest and most maintainable approach — zero CI boilerplate, zero manual
variable wiring.

### CI/CD

GitHub Actions workflows deploy on push to `main` (with manual approval gate via
the `production` environment) and destroy via `workflow_dispatch`.

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS credential |
| `AWS_SECRET_ACCESS_KEY` | AWS credential |
| `TF_API_TOKEN` | Terraform Cloud token (for setup-terraform) |
| `TF_STATE_BUCKET` | S3 bucket name for remote state |

## Quick Start

### Local Development

```bash
cd aws-labs/

# 1. Deploy networking (VPCs, TGW, endpoints, etc.)
cd networking
terraform init -backend-config="bucket=YOUR_BUCKET" \
               -backend-config="key=aws-labs/networking/terraform.tfstate" \
               -backend-config="region=us-east-2" -backend-config="encrypt=true"
terraform plan
terraform apply

# 2. Deploy compute (EC2 instances)
cd ../compute
terraform init -backend-config="bucket=YOUR_BUCKET" \
               -backend-config="key=aws-labs/compute/terraform.tfstate" \
               -backend-config="region=us-east-2" -backend-config="encrypt=true"
terraform plan  -var="state_bucket=YOUR_BUCKET"
terraform apply -var="state_bucket=YOUR_BUCKET"

# 3. View test commands
terraform output test_commands
```

### Variables

**networking/**

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-2` | AWS region for all resources |
| `project_name` | `aws-networking-lab` | Prefix for all resource names |
| `create_vpn` | `false` | Create VPN connection (adds ~$0.05/hr) |
| `create_nat_gateways` | `true` | Create NAT Gateways (adds ~$0.135/hr). Set to `false` to save cost. |

**compute/**

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-2` | AWS region for all resources |
| `project_name` | `aws-networking-lab` | Prefix for all resource names |
| `instance_type` | `t3.micro` | EC2 instance type |
| `state_bucket` | — (required) | S3 bucket name where networking state is stored |

---

## Connectivity Matrix

This matrix shows which instances can reach which destinations, and how.

```
FROM v  -> TO ->        | Internet | Internet | shared   | shared   | app-a   | app-a    | app-b   | vendor   | S3       |
                        | Outbound | Inbound  | public   | isolated | private | isolated | private | isolated | (AWS)    |
------------------------+----------+----------+----------+----------+---------+----------+---------+----------+----------+
shared-public           | OK IGW   | OK IGW   |  self    | OK local | OK Peer | OK Peer  | OK TGW  | --       | OK IGW   |
shared-isolated         | --       | --       | OK local |  self    | OK Peer | OK Peer  | OK TGW  | --       | OK GWEP  |
app-a-private           | OK NAT   | --       | OK Peer  | OK Peer  |  self   | OK local | OK TGW  | --       | OK NAT   |
app-a-isolated          | --       | --       | OK Peer  | OK Peer  | OK local|  self    | OK TGW  | --       | OK GWEP  |
app-b-private           | OK NAT   | --       | OK TGW   | OK TGW   | OK TGW  | OK TGW   |  self   | --       | OK NAT   |
vendor-isolated         | --       | --       | --       | --       | --      | --       | [PL]    |  self    | --       |
```

**Legend:** IGW = Internet Gateway, NAT = NAT Gateway, TGW = Transit Gateway, Peer = VPC Peering, PL = PrivateLink, GWEP = S3 Gateway Endpoint, local = same VPC

---

## Testing Guide — 16 Scenarios

After `terraform apply`, run `terraform output test_commands` for ready-to-paste commands.

### Group A: Internet Connectivity

#### A1. Public Subnet → Internet (Outbound)

**What it proves:** Public subnets have bidirectional internet via the Internet Gateway.

```bash
# Connect to shared-public
aws ssm start-session --target <shared-public-id>

# Test outbound internet
curl -s ifconfig.me
# Expected: returns the instance's public IP address
```

**How it works:** The public subnet's route table has `0.0.0.0/0 → IGW`. The IGW performs a 1:1 NAT: it translates the instance's private IP (10.0.1.x) to its associated public IP for outbound traffic, and reverses the translation for responses. This is stateless — unlike NAT Gateway, the IGW doesn't maintain a connection table.

#### A2. Internet → Public Subnet (Inbound)

**What it proves:** Instances with public IPs can receive inbound connections (if the security group allows it).

```bash
# From your local machine (not the instance):
curl http://<shared-public-public-ip>
# Expected: HTML response from the Apache server

# Check terraform output for the public IP:
terraform output shared_public_ip
```

**How it works:** Inbound traffic arrives at the IGW, which translates the public IP to the instance's private IP and forwards the packet to the VPC. The security group must allow the inbound port (80 in this case). If the security group doesn't have an inbound rule, the traffic is silently dropped — it doesn't even reach the instance.

#### A3. Private Subnet → Internet (Outbound Only)

**What it proves:** Private subnets can reach the internet outbound (via NAT Gateway), but cannot receive inbound connections.

```bash
# Connect to app-a-private
aws ssm start-session --target <app-a-private-id>

# Test outbound internet
curl -s ifconfig.me
# Expected: returns the NAT Gateway's Elastic IP (NOT the instance's IP)

# Verify: try accessing this instance from outside
# From your local machine: curl http://<app-a-private-ip> → will NOT work
```

**How it works:** The private subnet's route table has `0.0.0.0/0 → NAT Gateway`. The NAT Gateway lives in the public subnet and has its own Elastic IP. When an instance in the private subnet sends traffic to the internet:
1. Traffic goes to the NAT Gateway (via route table)
2. NAT Gateway translates: source IP private → NAT GW's public IP
3. NAT Gateway forwards to the IGW, which sends to the internet
4. Response comes back to NAT GW's public IP
5. NAT Gateway translates back and forwards to the instance

Inbound connections fail because the NAT Gateway only tracks connections that were initiated from the inside. Unsolicited inbound packets have no mapping and are dropped.

#### A4. Isolated Subnet → Internet (Blocked)

**What it proves:** Isolated subnets have zero internet access — there is literally no route.

```bash
# Connect to shared-isolated
aws ssm start-session --target <shared-isolated-id>

# Test internet access (will fail)
curl -s --connect-timeout 5 ifconfig.me
# Expected: timeout after 5 seconds — no internet route exists

# But internal cross-VPC still works:
ping -c 2 <app-b-private-ip>
# Expected: success via TGW (10.0.0.0/8 → TGW route exists)
```

**How it works:** The isolated subnet's route table has NO `0.0.0.0/0` entry. When the instance tries to reach an internet IP, the kernel sends the packet, but the route table has no matching entry, so VPC drops the packet. Cross-VPC traffic still works because the `10.0.0.0/8 → TGW` route exists — TGW routes are independent of internet routes.

---

### Group B: Transit Gateway

#### B1. Hub → Spoke (shared → app-b)

**What it proves:** TGW enables hub-and-spoke connectivity. The hub (shared) can reach any spoke.

```bash
# From shared-public:
ping -c 3 <app-b-private-ip>
# Expected: success — traffic flows: shared → TGW → app-b
```

**How it works:** The shared VPC's route table has `10.0.0.0/8 → TGW`. When shared-public pings app-b's IP (10.2.x.x), the route table matches the /8 route and sends traffic to the TGW. The TGW has an attachment to vpc-app-b and knows (via route propagation) that 10.2.0.0/16 is reachable through that attachment. It forwards the packet to the TGW ENI in vpc-app-b's subnet, which delivers it to the target instance.

> **Note:** shared → app-a traffic actually goes via VPC Peering, not TGW, because the /16 peering route is more specific than the /8 TGW route. See test C1.

#### B2. Spoke → Hub (app-b → shared)

**What it proves:** TGW routing is bidirectional.

```bash
# From app-b-private:
ping -c 3 <shared-isolated-ip>
# Expected: success — traffic flows: app-b → TGW → shared
```

#### B3. Spoke ↔ Spoke (app-a ↔ app-b)

**What it proves:** TGW enables transitive routing — spoke A can reach spoke B through the hub, even though there's no direct connection between them. VPC Peering cannot do this (peering is non-transitive).

```bash
# From app-a-private:
ping -c 3 <app-b-private-ip>
# Expected: success — traffic flows: app-a → TGW → app-b

# From app-b-private:
ping -c 3 <app-a-private-ip>
# Expected: success — bidirectional
```

**How it works:** Both VPCs have `10.0.0.0/8 → TGW` routes. The TGW's default route table has propagated routes for all three attached VPCs. When app-a sends traffic to 10.2.x.x, TGW matches the 10.2.0.0/16 propagated route and forwards to app-b's attachment.

#### B4. Cross-Tier via TGW (isolated → remote private)

**What it proves:** TGW routes between VPCs regardless of subnet tier. An isolated subnet instance can reach a private subnet instance in another VPC.

```bash
# From app-a-isolated:
ping -c 3 <app-b-private-ip>
# Expected: success — TGW doesn't care about subnet tier
```

---

### Group C: VPC Peering

#### C1. Peering Route Priority Over TGW

**What it proves:** When both a VPC Peering route (/16) and a TGW route (/8) match the same destination, the more specific route (longest prefix match) wins. This is how AWS route tables work.

```bash
# From app-a-private:
traceroute -n <shared-public-ip>
# Expected: direct hop (1 hop) — traffic goes via peering, NOT via TGW
# If it went via TGW, you'd see the TGW as an intermediate hop

# Compare with a destination that only has a TGW route:
traceroute -n <app-b-private-ip>
# Expected: via TGW (app-a has no peering with app-b)
```

**How it works:** vpc-app-a's route table has two entries that could match shared's CIDR:
- `10.0.0.0/8 → TGW` (added by transit-gateway.tf)
- `10.0.0.0/16 → VPC Peering` (added by vpc-peering.tf)

When app-a sends a packet to 10.0.x.x, both routes match. AWS uses **longest prefix match**: /16 is more specific than /8, so peering wins. This is the same algorithm routers use worldwide — it's not AWS-specific.

#### C2. Peering Bidirectional

**What it proves:** VPC Peering requires route entries on BOTH sides. The peering connection itself is symmetric, but each VPC needs its own route table entries pointing traffic to the peering connection.

```bash
# From shared-public → app-a:
ping -c 3 <app-a-private-ip>    # Success via peering

# From app-a-private → shared:
ping -c 3 <shared-public-ip>    # Success via peering
```

---

### Group D: VPC Endpoints

#### D1. S3 Gateway Endpoint (from Isolated Subnet)

**What it proves:** S3 Gateway Endpoints enable S3 access from subnets with zero internet connectivity. The traffic never leaves the AWS backbone.

```bash
# From shared-isolated (no internet!):
aws s3 ls s3://<test-bucket-name>
# Expected: lists the test.txt file

aws s3 cp s3://<test-bucket-name>/test.txt -
# Expected: displays the test file content
```

**How it works:** Gateway Endpoints work at the route table level. When you create an S3 Gateway Endpoint, AWS adds a route to your route table: `pl-xxxxxxxx → vpce-xxxxxxxx`. The prefix list (`pl-xxx`) is a managed list of S3's IP ranges. When the instance sends traffic to any S3 IP, the route table matches this prefix list entry and routes traffic directly to the S3 endpoint — bypassing the internet entirely.

You can verify this in the AWS Console: go to VPC → Route Tables → select the isolated subnet's route table. You'll see the prefix list entry.

Gateway Endpoints are **free** — no hourly charge, no data processing charge. That's why they're recommended for S3 and DynamoDB in all VPCs.

#### D2. SSM Interface Endpoint (from Isolated Subnet, Same VPC)

**What it proves:** Interface Endpoints create an ENI with a private IP. When Private DNS is enabled, the public service hostname resolves to this private IP instead of the public IP.

```bash
# From shared-isolated:

# Check DNS resolution
nslookup ssm.us-east-2.amazonaws.com
# Expected: resolves to 10.0.3.x (private IP in the isolated subnet)
# WITHOUT the endpoint, this would resolve to a public IP

# SSM Session Manager itself is proof:
# The fact that you connected to this instance via SSM proves the endpoints work.
# This instance has NO internet access, so SSM Agent must be using the
# Interface Endpoints to communicate with the SSM service.
```

**How it works:** When you create an Interface Endpoint with `private_dns_enabled = true`, AWS creates:
1. An ENI in your specified subnet with a private IP from that subnet's CIDR
2. A private hosted zone that overrides the public DNS name of the service

So when any instance in the VPC resolves `ssm.us-east-2.amazonaws.com`, instead of getting the public IP (e.g., 52.x.x.x), it gets the ENI's private IP (e.g., 10.0.3.x). All HTTPS traffic to the SSM API goes to this local ENI, which AWS forwards to the service internally.

This is transparent to applications — they use the same hostname, same SDK, same code. The DNS resolution is what changes.

#### D3. Centralized SSM Endpoints via TGW

**What it proves:** You can centralize VPC Endpoints in a shared services VPC and route traffic from other VPCs via TGW, saving the cost of deploying endpoints in every VPC.

```bash
# From app-a-isolated (has NO local SSM endpoints):
# If SSM session works, traffic is flowing:
#   app-a-isolated → TGW → vpc-shared → SSM Interface Endpoint → SSM API
aws ssm start-session --target <app-a-isolated-id>
```

**How it works:** app-a-isolated has no SSM Interface Endpoints in its VPC. But it has a route `10.0.0.0/8 → TGW` (via peering in this case, since 10.0.0.0/16 → peering exists). Traffic to the SSM endpoint's private IP (10.0.3.x) routes through the peering/TGW to vpc-shared, where the Interface Endpoint forwards it to the SSM service.

> **Important caveat:** This requires DNS resolution to work across VPCs. The private hosted zone created by the Interface Endpoint only applies within vpc-shared by default. For cross-VPC resolution, you need Route 53 Resolver rules or to associate the private hosted zone with the other VPCs.

**Production recommendation:** Centralize Interface Endpoints in a shared services VPC and use Route 53 Resolver to forward DNS queries. This can save significant cost — instead of N endpoints × M VPCs, you deploy N endpoints × 1 VPC.

---

### Group E: PrivateLink

#### E1. PrivateLink Service Consumption

**What it proves:** A completely isolated VPC (no TGW, no peering, no internet) can access a specific service in another VPC via PrivateLink.

```bash
# From vendor-isolated:
curl http://<privatelink-endpoint-dns>
# Expected: HTML response from app-b's HTTP server:
#   "PrivateLink Service — You are accessing this service from vpc-app-b..."

# Get the DNS name from terraform output:
terraform output privatelink_endpoint_dns
```

**How it works:** The PrivateLink architecture has two sides:

**Producer (vpc-app-b):**
1. An NLB (internal) fronts the HTTP server running on app-b-private
2. An Endpoint Service wraps the NLB, making it available as a PrivateLink service
3. The Endpoint Service gets a unique service name (e.g., `com.amazonaws.vpce.us-east-2.vpce-svc-xxxxxxxx`)

**Consumer (vpc-vendor):**
1. A VPC Endpoint (Interface type) is created pointing to the Endpoint Service
2. This creates an ENI in vendor's isolated subnet
3. The ENI gets a DNS name (e.g., `vpce-xxxxxxxx.vpce-svc-xxxxxxxx.us-east-2.vpce.amazonaws.com`)

**Traffic flow:**
```
vendor-isolated -> ENI (10.3.1.x) -> AWS backbone -> NLB (10.2.2.x) -> app-b-private:80
```

The ENI acts as a proxy — the vendor sends traffic to the ENI's IP, and AWS internally routes it to the NLB in vpc-app-b. The vendor never sees vpc-app-b's IP addresses.

#### E2. PrivateLink Isolation Proof

**What it proves:** PrivateLink provides service-level access, NOT network-level access. The vendor can reach ONLY the exposed service port — nothing else in any VPC.

```bash
# From vendor-isolated — all of these should FAIL:

# Cannot reach shared VPC:
ping -c 2 -W 2 <shared-public-ip>
# Expected: timeout (no route — vendor has no TGW or peering)

# Cannot reach app-a VPC:
ping -c 2 -W 2 <app-a-private-ip>
# Expected: timeout

# Cannot reach internet:
curl -s --connect-timeout 5 ifconfig.me
# Expected: timeout

# Cannot even ping app-b directly (PrivateLink ≠ network connectivity):
ping -c 2 -W 2 <app-b-private-ip>
# Expected: timeout — PrivateLink only exposes the NLB's port, not the VPC network
```

**Key insight:** This is what makes PrivateLink different from VPC Peering or TGW. With peering/TGW, the vendor would have network-level access to the entire VPC CIDR — they could scan ports, ping hosts, and potentially reach resources they shouldn't. PrivateLink restricts access to exactly one service on exactly one port.

---

### Group F: VPN / Direct Connect

#### F1. VPN Attachment on TGW (Simulated Direct Connect)

> **Note:** This test requires `create_vpn = true` in your variables.

**What it proves:** VPN and Direct Connect use the same TGW attachment pattern. The resource structure is identical — only the underlying transport differs.

```bash
# View VPN connection details:
aws ec2 describe-vpn-connections \
  --query 'VpnConnections[].{State:State,TgwId:TransitGatewayId,Tunnels:VgwTelemetry[].{Status:Status,IP:OutsideIpAddress}}' \
  --output table

# Expected:
# - State: available
# - TgwId: tgw-xxxxxxxx
# - Tunnel Status: DOWN (expected — no real remote endpoint)

# View TGW attachments (VPN shows alongside VPC attachments):
aws ec2 describe-transit-gateway-attachments \
  --filters Name=transit-gateway-id,Values=<tgw-id> \
  --query 'TransitGatewayAttachments[].{Type:ResourceType,State:State}' \
  --output table

# Expected: 3x vpc attachments + 1x vpn attachment
```

**How Direct Connect would work:** In production, you'd replace the VPN resources with:

```hcl
# Instead of aws_customer_gateway + aws_vpn_connection:
resource "aws_dx_gateway" "main" {
  name            = "my-dx-gateway"
  amazon_side_asn = 64512
}

resource "aws_dx_gateway_association" "tgw" {
  dx_gateway_id         = aws_dx_gateway.main.id
  associated_gateway_id = aws_ec2_transit_gateway.main.id
}
```

The TGW route table, VPC attachments, and VPC routing all stay the same. Only the attachment type changes from VPN to DX.

---

## Cost Breakdown

Default configuration: `create_nat_gateways = true`, `create_vpn = false`.

Prices vary significantly by region. São Paulo (sa-east-1) is typically 20-40% more expensive than US regions due to local taxes and infrastructure costs.

### us-east-2 (Ohio) — default region

| Resource | Qty | $/hr each | Subtotal/hr | Monthly (730h) | Notes |
|----------|-----|-----------|-------------|-----------------|-------|
| EC2 t3.micro | 6 | $0.0104 | $0.062 | $45.55 | 1 instance is free-tier eligible |
| NAT Gateway | 3 | $0.045 | $0.135 | $98.55 | Set `create_nat_gateways = false` to skip |
| TGW Attachments | 3 | $0.05 | $0.150 | $109.50 | Charged per attachment per hour |
| Interface VPC Endpoints | 9 | $0.01 | $0.090 | $65.70 | 4 shared + 4 vendor + 1 PrivateLink |
| NLB | 1 | $0.0225 | $0.023 | $16.43 | Minimum charge even with no traffic |
| Public IPv4 addresses | 4 | $0.005 | $0.020 | $14.60 | 3 NAT EIPs + 1 EC2 public IP |
| VPC Peering | 1 | Free | $0.000 | $0 | Only data transfer costs |
| S3 Gateway Endpoints | 3 | Free | $0.000 | $0 | Always free |
| VPN (optional) | 1 | $0.05 | $0.050 | $36.50 | Only if `create_vpn = true` |
| **Total (default)** | | | **~$0.48/hr** | **~$350** | **Without VPN** |

### sa-east-1 (São Paulo)

| Resource | Qty | $/hr each | Subtotal/hr | Monthly (730h) | Notes |
|----------|-----|-----------|-------------|-----------------|-------|
| EC2 t3.micro | 6 | $0.0152 | $0.091 | $66.58 | ~46% more than us-east-2 |
| NAT Gateway | 3 | $0.065 | $0.195 | $142.35 | ~44% more than us-east-2 |
| TGW Attachments | 3 | $0.07 | $0.210 | $153.30 | ~40% more than us-east-2 |
| Interface VPC Endpoints | 9 | $0.014 | $0.126 | $91.98 | ~40% more than us-east-2 |
| NLB | 1 | $0.0315 | $0.032 | $22.99 | ~40% more than us-east-2 |
| Public IPv4 addresses | 4 | $0.005 | $0.020 | $14.60 | Same price globally |
| VPC Peering | 1 | Free | $0.000 | $0 | Only data transfer costs |
| S3 Gateway Endpoints | 3 | Free | $0.000 | $0 | Always free |
| VPN (optional) | 1 | $0.07 | $0.070 | $51.10 | Only if `create_vpn = true` |
| **Total (default)** | | | **~$0.67/hr** | **~$492** | **Without VPN** |

### Cost by scenario

| Scenario | us-east-2/hr | us-east-2/month | sa-east-1/hr | sa-east-1/month |
|----------|-------------|-----------------|-------------|-----------------|
| **Default** (NAT on, VPN off) | ~$0.48 | ~$350 | ~$0.67 | ~$492 |
| **Minimal** (NAT off, VPN off) | ~$0.33 | ~$237 | ~$0.46 | ~$338 |
| **Full** (NAT on, VPN on) | ~$0.53 | ~$387 | ~$0.73 | ~$535 |

> **Recommendation:** Deploy the lab, run your tests, then `terraform destroy`. A 2-hour session costs ~$0.96 (us-east-2) or ~$1.34 (sa-east-1).

> **Note:** These are hourly fixed costs only. Data transfer (cross-AZ, NAT processing, TGW data processing, internet egress) adds additional charges but is negligible for a lab with minimal traffic. Prices sourced from AWS public pricing pages — check the [AWS Pricing Calculator](https://calculator.aws/) for exact, up-to-date values.

### Cost optimization tips

- Set `create_nat_gateways = false` to save ~$0.135-0.195/hr (you lose private subnet outbound testing, but public and isolated still work)
- The lab uses a single AZ to halve costs vs multi-AZ
- S3 Gateway Endpoints are free — always deploy them
- **Network infrastructure (TGW + NAT + Endpoints) accounts for ~79% of the total cost**, while EC2 instances are only ~14%

---

## Production Recommendations

This lab is designed for learning. Here's what you'd change for production:

### Transit Gateway
- **Separate route tables** per attachment type (shared-services vs spoke vs on-premises). The default "all propagate, all associate" is convenient but gives every VPC full access to every other VPC.
- **Route table segmentation**: Create a "spoke" route table that only routes to shared-services, not to other spokes. Spoke-to-spoke traffic should route through a firewall in the shared services VPC.
- **Inter-region peering**: TGW supports peering between TGWs in different regions for multi-region architectures.
- **AWS Network Firewall**: Deploy at the TGW level for centralized traffic inspection between VPCs.

### VPC Peering
- VPC Peering is best for 1-3 connections. Beyond that, TGW scales better.
- Peering is **not transitive** — if A peers with B and B peers with C, A cannot reach C. This is by design.
- Cross-region peering is supported but adds latency.
- You cannot peer VPCs with overlapping CIDRs.

### VPC Endpoints
- Deploy **Gateway Endpoints** for S3 and DynamoDB in every VPC — they're free.
- **Centralize Interface Endpoints** in a shared services VPC and use Route 53 Resolver for cross-VPC DNS resolution. This avoids paying for N endpoints × M VPCs.
- Use **VPC Endpoint Policies** to restrict which resources can be accessed through the endpoint (e.g., only specific S3 buckets).
- **Multi-AZ**: Deploy Interface Endpoints in all AZs for high availability. Each AZ costs an additional $0.01/hr per endpoint.

### PrivateLink
- Enable `acceptance_required = true` to manually approve each consumer connection.
- Use `allowed_principals` to restrict which AWS accounts can create endpoints to your service.
- Consider cross-account scenarios — PrivateLink is commonly used between different AWS accounts within the same organization.
- For SaaS architectures, combine PrivateLink with AWS Marketplace for discovery and billing.

### Direct Connect
- Use **Dedicated Connections** (1/10/100 Gbps) for consistent high-bandwidth needs.
- Use **Hosted Connections** (50 Mbps – 10 Gbps) through a partner for smaller needs.
- Always have a **VPN backup** — DX is a single physical connection and can fail.
- Use **DX Gateway** for multi-region connectivity through a single DX connection.
- **LAG (Link Aggregation Group)**: Bundle multiple DX connections for increased bandwidth and redundancy.
- **MACsec encryption**: Available on 10/100 Gbps dedicated connections for layer-2 encryption.

### General Networking
- **VPC Flow Logs**: Enable on all VPCs for traffic monitoring and troubleshooting. Send to CloudWatch Logs or S3.
- **Multi-AZ**: Deploy subnets, NAT Gateways, and endpoints in at least 2 AZs for high availability.
- **CIDR Planning**: Use non-overlapping CIDRs across all VPCs. Plan for growth — you can add secondary CIDRs, but it's cleaner to plan upfront.
- **Security Groups vs NACLs**: Use security groups (stateful, instance-level) as your primary firewall. Use NACLs (stateless, subnet-level) only for broad deny rules.
- **DNS Resolution**: Enable `enable_dns_support` and `enable_dns_hostnames` on all VPCs. Use Route 53 Private Hosted Zones for service discovery.

---

## Cleanup

```bash
# Destroy in reverse order
cd compute
terraform destroy -var="state_bucket=YOUR_BUCKET"

cd ../networking
terraform destroy
```

Or trigger the **Terraform Destroy** workflow via GitHub Actions (`workflow_dispatch`).

This removes all resources. Takes ~5-10 minutes (NAT Gateways and TGW attachments are the slowest to delete).

If destroy fails on the PrivateLink endpoint, it may be because the NLB is still draining. Wait 1 minute and retry.

---

## File Structure

```
aws-labs/
├── networking/                  # Layer 1: all network infrastructure
│   ├── versions.tf              # Terraform + providers + S3 backend
│   ├── providers.tf             # AWS provider with default tags
│   ├── variables.tf             # region, project_name, vpc_cidrs, feature flags
│   ├── outputs.tf               # Exports consumed by compute via remote state
│   ├── locals.tf                # Computed subnet CIDRs, AZ selection
│   ├── data.tf                  # AZs, region, caller identity
│   ├── iam.tf                   # SSM instance profile and IAM role
│   ├── vpc.tf                   # 4 VPCs, 10 subnets, route tables, IGW, NAT
│   ├── transit-gateway.tf       # TGW, 3 VPC attachments, VPC route entries
│   ├── vpc-peering.tf           # shared ↔ app-a peering + bidirectional routes
│   ├── vpc-endpoints.tf         # S3 Gateway + SSM/STS Interface endpoints
│   ├── privatelink.tf           # NLB + Endpoint Service + consumer endpoint
│   ├── vpn.tf                   # Optional VPN connection (simulated DX)
│   └── s3.tf                    # Test S3 bucket for Gateway Endpoint validation
├── compute/                     # Layer 2: test instances
│   ├── versions.tf              # Terraform + AWS provider + S3 backend
│   ├── providers.tf             # AWS provider with default tags
│   ├── variables.tf             # instance_type + state_bucket (only cross-layer input)
│   ├── outputs.tf               # Instance IDs, IPs, test commands
│   ├── remote-state.tf          # terraform_remote_state → networking outputs
│   ├── data.tf                  # AMI lookup
│   └── ec2.tf                   # 4 SGs + 6 EC2 instances + PrivateLink TG attachment
├── .github/workflows/
│   ├── tf-deploy.yml            # Push to main → approval gate → networking → compute
│   └── tf-destroy.yml           # Manual trigger → destroy compute → destroy networking
└── README.md
```
