# 🌐 Laboratório de Networking AWS

Um laboratório prático com Terraform que implanta um ambiente multi-VPC para demonstrar e testar 5 serviços essenciais de networking da AWS:

- 🔀 **Transit Gateway (TGW)** — conectividade hub-and-spoke
- 🔗 **VPC Peering** — links diretos VPC-a-VPC
- 🏷️ **VPC Endpoints** — acesso privado a serviços AWS (tipos Gateway + Interface)
- 🔒 **AWS PrivateLink** — exposição de serviços sem merge de rede
- 🛡️ **Site-to-Site VPN** — simulação de Direct Connect para nuvem híbrida

Cada serviço é usado onde faz sentido naturalmente — sem forçar — para que você entenda *por que* e *quando* usar cada um.

---

## 🏗️ Arquitetura

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

### 📋 Papéis das VPCs

| VPC | CIDR | Papel | Por que existe |
|-----|------|-------|----------------|
| **vpc-shared** | 10.0.0.0/16 | Serviços compartilhados centrais | Hub do TGW, hospeda VPC Endpoints centralizados, peering direto com app-a |
| **vpc-app-a** | 10.1.0.0/16 | Application Team A | Spoke do TGW + peering direto com shared (demonstra prioridade de rotas) |
| **vpc-app-b** | 10.2.0.0/16 | Application Team B | Spoke do TGW + expõe serviço HTTP via PrivateLink |
| **vpc-vendor** | 10.3.0.0/16 | Vendor/parceiro externo | Completamente isolada — SEM TGW, SEM peering, apenas acesso via PrivateLink |

### 💡 Por que cada serviço é usado onde está

| Serviço | Onde | Por que (não apenas como) | Custo de setup | Transferência de dados |
|---------|------|-----------------------------|----------------|------------------------|
| **TGW** | shared ↔ app-a ↔ app-b | Quando você tem 3+ VPCs que precisam de conectividade any-to-any, o TGW escala linearmente (N attachments) ao invés de exponencialmente (N×(N-1)/2 peerings). Também suporta roteamento transitivo — spoke A alcança spoke B através do hub. | $0.05/hr por attachment (~$36.50/mês) | $0.02/GB processado |
| **VPC Peering** | shared ↔ app-a (adicionalmente) | Para um caminho crítico e sensível a latência entre duas VPCs específicas. Peering é gratuito, tem menor latência que o TGW e coexiste com o TGW. A rota /16 do peering vence a rota /8 do TGW via longest prefix match. | **Gratuito** | $0.00/GB mesma-AZ; $0.01/GB cross-AZ |
| **VPC Endpoints (Gateway)** | S3 em todas as VPCs | Gateway Endpoints para S3 são **gratuitos** e roteiam o tráfego do S3 pelo backbone da AWS ao invés da internet. Não é necessário NAT Gateway para acesso ao S3. | **Gratuito** | **Gratuito** |
| **VPC Endpoints (Interface)** | SSM/STS em shared + vendor | Interface Endpoints criam uma ENI com IP privado. Quando Private DNS está habilitado, `ssm.us-east-2.amazonaws.com` resolve para o IP privado ao invés do público. Isso permite que o SSM Session Manager funcione sem nenhum acesso à internet. | $0.01/hr por AZ (~$7.30/mês/AZ) | $0.01/GB |
| **PrivateLink** | app-b → vendor | O PrivateLink permite expor um serviço para outra VPC sem nenhuma conectividade a nível de rede. O vendor só consegue acessar a porta do serviço (80) — não pode fazer ping, scan ou acessar qualquer outra coisa na vpc-app-b. | NLB $0.0225/hr + Endpoint $0.01/hr por AZ (~$38/mês para 3 AZs) | $0.01/GB + LCU |
| **VPN** | TGW attachment | Mesmo padrão de attachment do Direct Connect. Em produção, você substituiria a VPN por um DX Gateway associado ao TGW. | $0.05/hr por conexão (~$36.50/mês) | $0.09/GB saída; entrada gratuita |

---

## 🏢 Design de Subnets: 3 Tiers

Cada VPC (exceto vendor) tem 3 tiers de subnet que demonstram diferentes padrões de acesso à internet:

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

### ⚙️ Como cada tier funciona

**Public Subnet** (`0.0.0.0/0 → Internet Gateway`)
- Instâncias podem ter IPs públicos (auto-assigned ou Elastic IP)
- Internet bidirecional completa: saída via IGW, entrada via IP público + security group
- Caso de uso: load balancers, bastion hosts, os próprios NAT Gateways
- O IGW faz NAT 1:1 entre IPs públicos e privados — não altera o pacote, apenas traduz o endereço

**Private Subnet** (`0.0.0.0/0 → NAT Gateway`)
- Instâncias têm apenas IPs privados
- Internet de saída funciona via NAT Gateway (IP de origem vira o Elastic IP do NAT GW)
- Entrada pela internet é impossível — NAT só rastreia conexões iniciadas de dentro
- Caso de uso: servidores de aplicação que precisam baixar pacotes, chamar APIs externas, etc.
- Este é o tier de subnet mais comum em produção

**Isolated Subnet** (sem rota `0.0.0.0/0`)
- Zero acesso à internet em qualquer direção
- Só consegue acessar serviços AWS via VPC Endpoints
- Ainda consegue alcançar outras VPCs via TGW/Peering (essas rotas existem)
- Caso de uso: bancos de dados, processamento interno, workloads sensíveis
- Se você tentar `curl ifconfig.me`, vai dar timeout — literalmente não existe rota para a internet

### 🗺️ Mapa de Subnets

| VPC | Public | Private | Isolated |
|-----|--------|---------|----------|
| vpc-shared (10.0.0.0/16) | 10.0.1.0/24 | 10.0.2.0/24 | 10.0.3.0/24 |
| vpc-app-a (10.1.0.0/16) | 10.1.1.0/24 | 10.1.2.0/24 | 10.1.3.0/24 |
| vpc-app-b (10.2.0.0/16) | 10.2.1.0/24 | 10.2.2.0/24 | 10.2.3.0/24 |
| vpc-vendor (10.3.0.0/16) | — | — | 10.3.1.0/24 |

> **vpc-vendor** possui apenas isolated subnet — sem IGW, sem NAT, sem internet. Representa um parceiro externo que deve ter zero acesso à rede exceto via PrivateLink.

---

## 🖥️ Instâncias de Teste

| Instância | VPC | Tier da Subnet | IP Público | Finalidade |
|-----------|-----|----------------|------------|------------|
| `shared-public` | vpc-shared | Public | Sim | IGW entrada+saída, TGW, peering |
| `shared-isolated` | vpc-shared | Isolated | Não | VPC Endpoints (S3, SSM), prova de zero internet |
| `app-a-private` | vpc-app-a | Private | Não | NAT saída, TGW, prioridade de rota peering |
| `app-a-isolated` | vpc-app-a | Isolated | Não | SSM endpoints centralizados via TGW |
| `app-b-private` | vpc-app-b | Private | Não | Servidor HTTP atrás do NLB (alvo do PrivateLink) |
| `vendor-isolated` | vpc-vendor | Isolated | Não | Consumidor PrivateLink, prova de isolamento total |

Todas as instâncias são acessadas via **SSM Session Manager** — sem SSH keys, sem bastion hosts, sem IPs públicos necessários (exceto shared-public para testes de entrada).

---

## ✅ Pré-requisitos

1. **AWS CLI v2** configurado com credenciais apropriadas
2. **Terraform >= 1.5** instalado
3. **Permissões IAM na AWS** — o usuário/role que faz o deploy precisa de permissões para:
   - VPC, Subnets, Route Tables, Internet Gateways, NAT Gateways
   - EC2 (instâncias, security groups, EIPs)
   - Transit Gateway
   - VPC Peering
   - VPC Endpoints
   - Elastic Load Balancing (NLB)
   - S3
   - IAM (roles, instance profiles)
   - SSM (para acesso via Session Manager)
   - VPN (se `create_vpn = true`)
4. **Session Manager Plugin** para AWS CLI — [guia de instalação](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

---

## 📁 Estrutura do Projeto

O projeto é dividido em duas camadas Terraform com state files independentes:

```
networking/    → VPCs, TGW, Peering, Endpoints, PrivateLink, VPN, IAM, S3
compute/       → EC2 instances, Security Groups, PrivateLink target attachment
```

**Ordem de deploy**: networking → compute
**Ordem de destroy**: compute → networking (inversa)

A camada `compute` lê todos os outputs de `networking` via `terraform_remote_state`,
então não há passagem manual de outputs — qualquer novo output adicionado em `networking/outputs.tf`
fica automaticamente disponível em `compute` como `local.net.<output_name>`.

### 🔄 Comunicação entre camadas via `terraform_remote_state`

Ao invés de passar dezenas de variáveis de ambiente `TF_VAR_*` entre jobs de CI, este
projeto usa `terraform_remote_state` — um mecanismo nativo do Terraform onde uma camada
lê outputs diretamente do state file de outra camada no S3.

**Como funciona:**

1. `networking/outputs.tf` declara outputs (VPC IDs, subnet IDs, etc.)
2. `terraform apply` no networking grava esses outputs no S3 (`aws-labs/networking/terraform.tfstate`)
3. `compute/remote-state.tf` lê esse state file via data source `terraform_remote_state`
4. O código de `compute/` referencia valores como `local.net.<output_name>` (alias para o caminho longo do data source)
5. A única variável que o CI precisa passar é `state_bucket` — o nome do bucket S3

```
networking/outputs.tf          compute/remote-state.tf          compute/ec2.tf
  output "vpc_shared_id"  ──►   data "terraform_remote_state"  ──►  local.net.vpc_shared_id
  (written to S3 state)          "networking" { bucket = ... }       (used in resources)
```

**Isso é production-ready?**

Sim. `terraform_remote_state` é o padrão Terraform para arquiteturas multi-camadas
e é amplamente usado em ambientes de produção. Considerações importantes:

- **Quando usar**: Mesmo time/org é dono de ambas as camadas, mesma conta AWS, state está em
  um backend compartilhado (S3, GCS, Terraform Cloud). Este é o caso mais comum para
  layering de infraestrutura (network → compute → apps).
- **Quando NÃO usar**: Fronteiras entre times onde você não quer expor o state file
  completo. `terraform_remote_state` concede acesso de leitura a _todos_ os outputs do
  state, não apenas os que você precisa. Para cenários cross-team, prefira
  [`terraform_remote_state` com Terraform Cloud workspaces](https://developer.hashicorp.com/terraform/language/state/remote-state-data)
  (que limita o escopo de acesso) ou use SSM Parameter Store / Secrets Manager como
  intermediário — o produtor grava valores, o consumidor lê, e o IAM controla quem
  pode acessar o quê.
- **Alternativas em produção**:
  - **SSM Parameter Store**: Produtor grava `aws_ssm_parameter`, consumidor lê via
    `data.aws_ssm_parameter`. Controle IAM granular, funciona cross-account.
  - **Terraform Cloud/Enterprise**: Outputs nativos de workspace com RBAC.
  - **CI job outputs** (o que o sl-eks usa): Necessário quando a configuração do _provider_
    Terraform depende de outputs (ex: Helm provider precisa do endpoint do EKS).
    `terraform_remote_state` não pode ser usado em blocos de provider porque
    data sources são resolvidos após os providers serem configurados.

Para este lab (conta única, time único, provider AWS puro), `terraform_remote_state`
é a abordagem mais simples e manutenível — zero boilerplate de CI, zero wiring manual
de variáveis.

### 🚀 CI/CD

Workflows do GitHub Actions fazem deploy em push para `main` (com gate de aprovação manual via
environment `production`) e destroy via `workflow_dispatch`.

| Secret | Descrição |
|--------|-----------|
| `AWS_ACCESS_KEY_ID` | Credencial AWS |
| `AWS_SECRET_ACCESS_KEY` | Credencial AWS |
| `TF_API_TOKEN` | Token do Terraform Cloud (para setup-terraform) |
| `TF_STATE_BUCKET` | Nome do bucket S3 para remote state |

## ⚡ Início Rápido

### 🛠️ Desenvolvimento Local

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

### 📝 Variáveis

**networking/**

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `aws_region` | `us-east-2` | Região AWS para todos os recursos |
| `project_name` | `aws-networking-lab` | Prefixo para todos os nomes de recursos |
| `create_vpn` | `false` | Cria conexão VPN (adiciona ~$0.05/hr) |
| `create_nat_gateways` | `true` | Cria NAT Gateways (adiciona ~$0.135/hr). Defina como `false` para economizar custos. |

**compute/**

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `aws_region` | `us-east-2` | Região AWS para todos os recursos |
| `project_name` | `aws-networking-lab` | Prefixo para todos os nomes de recursos |
| `instance_type` | `t3.micro` | Tipo de instância EC2 |
| `state_bucket` | — (obrigatório) | Nome do bucket S3 onde o state do networking está armazenado |

---

## 📡 Matriz de Conectividade

Esta matriz mostra quais instâncias conseguem alcançar quais destinos, e como.

| DE ↓ · PARA → | Internet Saída | Internet Entrada | shared-public | shared-isolated | app-a-private | app-a-isolated | app-b-private | vendor-isolated | S3 (AWS) |
|---|---|---|---|---|---|---|---|---|---|
| **shared-public** | ✅ IGW | ✅ IGW | self | ✅ local | ✅ Peer | ✅ Peer | ✅ TGW | ❌ | ✅ IGW |
| **shared-isolated** | ❌ | ❌ | ✅ local | self | ✅ Peer | ✅ Peer | ✅ TGW | ❌ | ✅ GWEP |
| **app-a-private** | ✅ NAT | ❌ | ✅ Peer | ✅ Peer | self | ✅ local | ✅ TGW | ❌ | ✅ NAT |
| **app-a-isolated** | ❌ | ❌ | ✅ Peer | ✅ Peer | ✅ local | self | ✅ TGW | ❌ | ✅ GWEP |
| **app-b-private** | ✅ NAT | ❌ | ✅ TGW | ✅ TGW | ✅ TGW | ✅ TGW | self | ❌ | ✅ NAT |
| **vendor-isolated** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | [PL] | self | ❌ |

**Legenda:** IGW = Internet Gateway, NAT = NAT Gateway, TGW = Transit Gateway, Peer = VPC Peering, PL = PrivateLink, GWEP = S3 Gateway Endpoint, local = mesma VPC

---

## 🧪 Guia de Testes — 16 Cenários

Após `terraform apply`, execute `terraform output test_commands` para comandos prontos para colar.

### 🌍 Grupo A: Conectividade com a Internet

#### A1. Public Subnet → Internet (Saída)

```
📤 shared-public (10.0.1.x) ──► IGW (1:1 NAT) ──► 🌍 Internet
         route: 0.0.0.0/0 → igw
```

**O que prova:** Public subnets têm internet bidirecional via Internet Gateway.

```bash
# Connect to shared-public
aws ssm start-session --target <shared-public-id>

# Test outbound internet
curl -s ifconfig.me
# Expected: returns the instance's public IP address
```

**Como funciona:** A route table da public subnet tem `0.0.0.0/0 → IGW`. O IGW faz NAT 1:1: traduz o IP privado da instância (10.0.1.x) para seu IP público associado no tráfego de saída, e reverte a tradução para respostas. Isso é stateless — diferente do NAT Gateway, o IGW não mantém tabela de conexões.

#### A2. Internet → Public Subnet (Entrada)

```
🌍 Internet ──► IGW (pub→priv NAT) ──► SG :80 ✅ ──► 📥 shared-public (10.0.1.x)
```

**O que prova:** Instâncias com IPs públicos podem receber conexões de entrada (se o security group permitir).

```bash
# From your local machine (not the instance):
curl http://<shared-public-public-ip>
# Expected: HTML response from the Apache server

# Check terraform output for the public IP:
terraform output shared_public_ip
```

**Como funciona:** O tráfego de entrada chega ao IGW, que traduz o IP público para o IP privado da instância e encaminha o pacote para a VPC. O security group deve permitir a porta de entrada (80 neste caso). Se o security group não tiver uma regra de entrada, o tráfego é silenciosamente descartado — nem chega à instância.

#### A3. Private Subnet → Internet (Apenas Saída)

```
📤 app-a-private (10.1.2.x) ──► NAT GW (EIP) ──► IGW ──► 🌍 Internet
         route: 0.0.0.0/0 → nat-gw
🌍 Internet ──► NAT GW ──✖ (no inbound mapping) ──► ❌ BLOCKED
```

**O que prova:** Private subnets conseguem alcançar a internet na saída (via NAT Gateway), mas não podem receber conexões de entrada.

```bash
# Connect to app-a-private
aws ssm start-session --target <app-a-private-id>

# Test outbound internet
curl -s ifconfig.me
# Expected: returns the NAT Gateway's Elastic IP (NOT the instance's IP)

# Verify: try accessing this instance from outside
# From your local machine: curl http://<app-a-private-ip> → will NOT work
```

**Como funciona:** A route table da private subnet tem `0.0.0.0/0 → NAT Gateway`. O NAT Gateway fica na public subnet e tem seu próprio Elastic IP. Quando uma instância na private subnet envia tráfego para a internet:
1. O tráfego vai para o NAT Gateway (via route table)
2. O NAT Gateway traduz: IP de origem privado → IP público do NAT GW
3. O NAT Gateway encaminha para o IGW, que envia para a internet
4. A resposta volta para o IP público do NAT GW
5. O NAT Gateway traduz de volta e encaminha para a instância

Conexões de entrada falham porque o NAT Gateway só rastreia conexões iniciadas de dentro. Pacotes de entrada não solicitados não têm mapeamento e são descartados.

#### A4. Isolated Subnet → Internet (Bloqueado)

```
🚫 shared-isolated (10.0.3.x) ──► route table: no 0.0.0.0/0 ──► ❌ DROPPED
   but cross-VPC works:
✅ shared-isolated (10.0.3.x) ──► TGW (10.0.0.0/8) ──► app-b-private
```

**O que prova:** Isolated subnets têm zero acesso à internet — literalmente não existe rota.

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

**Como funciona:** A route table da isolated subnet NÃO tem entrada `0.0.0.0/0`. Quando a instância tenta alcançar um IP da internet, o kernel envia o pacote, mas a route table não tem entrada correspondente, então a VPC descarta o pacote. O tráfego cross-VPC ainda funciona porque a rota `10.0.0.0/8 → TGW` existe — rotas do TGW são independentes de rotas de internet.

---

### 🔀 Grupo B: Transit Gateway

#### B1. Hub → Spoke (shared → app-b)

```
🔀 shared-public (10.0.1.x) ──► TGW ──► vpc-app-b attachment ──► ✅ app-b-private (10.2.2.x)
         route: 10.0.0.0/8 → tgw       propagated: 10.2.0.0/16
```

**O que prova:** O TGW habilita conectividade hub-and-spoke. O hub (shared) alcança qualquer spoke.

```bash
# From shared-public:
ping -c 3 <app-b-private-ip>
# Expected: success — traffic flows: shared → TGW → app-b
```

**Como funciona:** A route table da VPC shared tem `10.0.0.0/8 → TGW`. Quando shared-public faz ping para o IP da app-b (10.2.x.x), a route table corresponde à rota /8 e envia o tráfego para o TGW. O TGW tem um attachment para a vpc-app-b e sabe (via propagação de rotas) que 10.2.0.0/16 é alcançável por esse attachment. Ele encaminha o pacote para a ENI do TGW na subnet da vpc-app-b, que entrega à instância de destino.

> **Nota:** O tráfego shared → app-a na verdade vai via VPC Peering, não TGW, porque a rota /16 do peering é mais específica que a rota /8 do TGW. Veja o teste C1.

#### B2. Spoke → Hub (app-b → shared)

```
🔀 app-b-private (10.2.2.x) ──► TGW ──► vpc-shared attachment ──► ✅ shared-isolated (10.0.3.x)
         route: 10.0.0.0/8 → tgw       propagated: 10.0.0.0/16
```

**O que prova:** O roteamento do TGW é bidirecional.

```bash
# From app-b-private:
ping -c 3 <shared-isolated-ip>
# Expected: success — traffic flows: app-b → TGW → shared
```

#### B3. Spoke ↔ Spoke (app-a ↔ app-b)

```
🔀 app-a-private (10.1.2.x) ──► TGW ──► vpc-app-b attachment ──► ✅ app-b-private (10.2.2.x)
🔀 app-b-private (10.2.2.x) ──► TGW ──► vpc-app-a attachment ──► ✅ app-a-private (10.1.2.x)
         ⚠️ No direct peering — TGW provides transitive routing
```

**O que prova:** O TGW habilita roteamento transitivo — spoke A alcança spoke B através do hub, mesmo sem conexão direta entre eles. VPC Peering não consegue fazer isso (peering é não-transitivo).

```bash
# From app-a-private:
ping -c 3 <app-b-private-ip>
# Expected: success — traffic flows: app-a → TGW → app-b

# From app-b-private:
ping -c 3 <app-a-private-ip>
# Expected: success — bidirectional
```

**Como funciona:** Ambas as VPCs têm rotas `10.0.0.0/8 → TGW`. A route table padrão do TGW tem rotas propagadas para as três VPCs attached. Quando app-a envia tráfego para 10.2.x.x, o TGW corresponde à rota propagada 10.2.0.0/16 e encaminha para o attachment da app-b.

#### B4. Cross-Tier via TGW (isolated → remote private)

```
🔀 app-a-isolated (10.1.3.x) ──► TGW ──► vpc-app-b ──► ✅ app-b-private (10.2.2.x)
         isolated subnet                    private subnet
         ⚠️ TGW doesn't care about subnet tier — only VPC-level routing
```

**O que prova:** O TGW roteia entre VPCs independentemente do tier da subnet. Uma instância em isolated subnet alcança uma instância em private subnet de outra VPC.

```bash
# From app-a-isolated:
ping -c 3 <app-b-private-ip>
# Expected: success — TGW doesn't care about subnet tier
```

---

### 🔗 Grupo C: VPC Peering

#### C1. Prioridade da Rota Peering sobre TGW

```
🔗 app-a → shared:  10.0.0.0/16 → Peering ✅ WINS (longest prefix)
                     10.0.0.0/8  → TGW     ❌ less specific, ignored

🔀 app-a → app-b:   10.0.0.0/8  → TGW     ✅ only matching route (no peering with app-b)
```

**O que prova:** Quando uma rota de VPC Peering (/16) e uma rota de TGW (/8) correspondem ao mesmo destino, a rota mais específica (longest prefix match) vence. É assim que as route tables da AWS funcionam.

```bash
# From app-a-private:
traceroute -n <shared-public-ip>
# Expected: direct hop (1 hop) — traffic goes via peering, NOT via TGW
# If it went via TGW, you'd see the TGW as an intermediate hop

# Compare with a destination that only has a TGW route:
traceroute -n <app-b-private-ip>
# Expected: via TGW (app-a has no peering with app-b)
```

**Como funciona:** A route table da vpc-app-a tem duas entradas que podem corresponder ao CIDR da shared:
- `10.0.0.0/8 → TGW` (adicionada por transit-gateway.tf)
- `10.0.0.0/16 → VPC Peering` (adicionada por vpc-peering.tf)

Quando app-a envia um pacote para 10.0.x.x, ambas as rotas correspondem. A AWS usa **longest prefix match**: /16 é mais específico que /8, então o peering vence. Este é o mesmo algoritmo que roteadores usam mundialmente — não é específico da AWS.

#### C2. Peering Bidirecional

```
🔗 shared-public (10.0.1.x) ◄──── VPC Peering ────► app-a-private (10.1.2.x)
     route: 10.1.0.0/16 → pcx         route: 10.0.0.0/16 → pcx
     ⚠️ Both sides need route entries — peering alone isn't enough
```

**O que prova:** VPC Peering requer entradas de rota em AMBOS os lados. A conexão de peering em si é simétrica, mas cada VPC precisa de suas próprias entradas na route table apontando tráfego para a conexão de peering.

```bash
# From shared-public → app-a:
ping -c 3 <app-a-private-ip>    # Success via peering

# From app-a-private → shared:
ping -c 3 <shared-public-ip>    # Success via peering
```

---

### 🏷️ Grupo D: VPC Endpoints

#### D1. S3 Gateway Endpoint (de Isolated Subnet)

```
🏷️ shared-isolated (10.0.3.x) ──► route: pl-xxx → vpce ──► S3 (AWS backbone)
         🚫 no internet          ✅ Gateway Endpoint         💲 FREE
```

**O que prova:** S3 Gateway Endpoints permitem acesso ao S3 de subnets com zero conectividade com a internet. O tráfego nunca sai do backbone da AWS.

```bash
# From shared-isolated (no internet!):
aws s3 ls s3://<test-bucket-name>
# Expected: lists the test.txt file

aws s3 cp s3://<test-bucket-name>/test.txt -
# Expected: displays the test file content
```

**Como funciona:** Gateway Endpoints funcionam no nível da route table. Quando você cria um S3 Gateway Endpoint, a AWS adiciona uma rota à sua route table: `pl-xxxxxxxx → vpce-xxxxxxxx`. O prefix list (`pl-xxx`) é uma lista gerenciada dos ranges de IP do S3. Quando a instância envia tráfego para qualquer IP do S3, a route table corresponde à entrada do prefix list e roteia o tráfego diretamente para o endpoint do S3 — contornando a internet inteiramente.

Você pode verificar isso no Console AWS: vá em VPC → Route Tables → selecione a route table da isolated subnet. Você verá a entrada do prefix list.

Gateway Endpoints são **gratuitos** — sem cobrança por hora, sem cobrança por processamento de dados. Por isso são recomendados para S3 e DynamoDB em todas as VPCs.

#### D2. SSM Interface Endpoint (de Isolated Subnet, Mesma VPC)

```
🔌 shared-isolated ──► DNS: ssm.us-east-2.amazonaws.com → 10.0.3.x (private!)
                        ──► ENI (Interface Endpoint) ──► SSM API (AWS backbone)
         without endpoint: ssm.us-east-2.amazonaws.com → 52.x.x.x (public) → ❌ no route
```

**O que prova:** Interface Endpoints criam uma ENI com IP privado. Quando Private DNS está habilitado, o hostname público do serviço resolve para este IP privado ao invés do IP público.

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

**Como funciona:** Quando você cria um Interface Endpoint com `private_dns_enabled = true`, a AWS cria:
1. Uma ENI na subnet especificada com um IP privado do CIDR dessa subnet
2. Uma private hosted zone que sobrescreve o nome DNS público do serviço

Então quando qualquer instância na VPC resolve `ssm.us-east-2.amazonaws.com`, ao invés de obter o IP público (ex: 52.x.x.x), obtém o IP privado da ENI (ex: 10.0.3.x). Todo o tráfego HTTPS para a API do SSM vai para essa ENI local, que a AWS encaminha para o serviço internamente.

Isso é transparente para as aplicações — usam o mesmo hostname, mesmo SDK, mesmo código. A resolução DNS é o que muda.

#### D3. SSM Endpoints Centralizados via TGW

```
🔌 app-a-isolated ──► Peering/TGW ──► vpc-shared ──► ENI (10.0.3.x) ──► SSM API
      ⚠️ no local SSM endpoints        has SSM Interface Endpoints
      💲 saves: N endpoints × M VPCs → N endpoints × 1 VPC
```

**O que prova:** Você pode centralizar VPC Endpoints em uma VPC de serviços compartilhados e rotear tráfego de outras VPCs via TGW, economizando o custo de implantar endpoints em cada VPC.

```bash
# From app-a-isolated (has NO local SSM endpoints):
# If SSM session works, traffic is flowing:
#   app-a-isolated → TGW → vpc-shared → SSM Interface Endpoint → SSM API
aws ssm start-session --target <app-a-isolated-id>
```

**Como funciona:** app-a-isolated não tem SSM Interface Endpoints na sua VPC. Mas tem uma rota `10.0.0.0/8 → TGW` (via peering neste caso, já que 10.0.0.0/16 → peering existe). O tráfego para o IP privado do SSM endpoint (10.0.3.x) roteia pelo peering/TGW até a vpc-shared, onde o Interface Endpoint encaminha para o serviço SSM.

> **Ressalva importante:** Isso requer que a resolução DNS funcione entre VPCs. A private hosted zone criada pelo Interface Endpoint só se aplica dentro da vpc-shared por padrão. Para resolução cross-VPC, você precisa de regras do Route 53 Resolver ou associar a private hosted zone com as outras VPCs.

**Recomendação para produção:** Centralize Interface Endpoints em uma VPC de serviços compartilhados e use Route 53 Resolver para encaminhar consultas DNS. Isso pode economizar custos significativos — ao invés de N endpoints × M VPCs, você implanta N endpoints × 1 VPC.

---

### 🔒 Grupo E: PrivateLink

#### E1. Consumo de Serviço via PrivateLink

```
🔒 PRODUCER (vpc-app-b)                          CONSUMER (vpc-vendor)
   app-b-private:80 ◄── NLB ◄── Endpoint Service ◄── AWS backbone ◄── ENI (10.3.1.x) ◄── vendor-isolated
                                  vpce-svc-xxx                          vpce-xxx
   ⚠️ vendor never sees app-b IPs — only the local ENI
```

**O que prova:** Uma VPC completamente isolada (sem TGW, sem peering, sem internet) pode acessar um serviço específico em outra VPC via PrivateLink.

```bash
# From vendor-isolated:
curl http://<privatelink-endpoint-dns>
# Expected: HTML response from app-b's HTTP server:
#   "PrivateLink Service — You are accessing this service from vpc-app-b..."

# Get the DNS name from terraform output:
terraform output privatelink_endpoint_dns
```

**Como funciona:** A arquitetura PrivateLink tem dois lados:

**Producer (vpc-app-b):**
1. Um NLB (interno) frontaliza o servidor HTTP rodando na app-b-private
2. Um Endpoint Service envolve o NLB, tornando-o disponível como serviço PrivateLink
3. O Endpoint Service recebe um nome de serviço único (ex: `com.amazonaws.vpce.us-east-2.vpce-svc-xxxxxxxx`)

**Consumer (vpc-vendor):**
1. Um VPC Endpoint (tipo Interface) é criado apontando para o Endpoint Service
2. Isso cria uma ENI na isolated subnet do vendor
3. A ENI recebe um nome DNS (ex: `vpce-xxxxxxxx.vpce-svc-xxxxxxxx.us-east-2.vpce.amazonaws.com`)

**Fluxo de tráfego:**
```
vendor-isolated -> ENI (10.3.1.x) -> AWS backbone -> NLB (10.2.2.x) -> app-b-private:80
```

A ENI atua como proxy — o vendor envia tráfego para o IP da ENI, e a AWS roteia internamente para o NLB na vpc-app-b. O vendor nunca vê os endereços IP da vpc-app-b.

#### E2. Prova de Isolamento do PrivateLink

```
🔒 vendor-isolated attempts:
   → shared (10.0.x.x)    ❌ no TGW, no peering, no route
   → app-a  (10.1.x.x)    ❌ no TGW, no peering, no route
   → app-b  (10.2.x.x)    ❌ PrivateLink ≠ network access
   → internet              ❌ no IGW, no NAT
   → app-b:80 via PL ENI  ✅ only this works
```

**O que prova:** PrivateLink fornece acesso a nível de serviço, NÃO acesso a nível de rede. O vendor consegue alcançar APENAS a porta do serviço exposto — nada mais em nenhuma VPC.

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

**Insight principal:** Isso é o que torna o PrivateLink diferente do VPC Peering ou TGW. Com peering/TGW, o vendor teria acesso a nível de rede ao CIDR inteiro da VPC — poderia fazer scan de portas, ping em hosts e potencialmente alcançar recursos que não deveria. PrivateLink restringe o acesso a exatamente um serviço em exatamente uma porta.

---

### 🛡️ Grupo F: VPN / Direct Connect

#### F1. VPN Attachment no TGW (Simulação de Direct Connect)

```
🛡️ TGW Attachments:
   ├── vpc-shared    (type: vpc)     ✅ UP
   ├── vpc-app-a     (type: vpc)     ✅ UP
   ├── vpc-app-b     (type: vpc)     ✅ UP
   └── vpn-connection (type: vpn)    ⚠️ tunnels DOWN (no real remote endpoint)
       └── in production: replace with aws_dx_gateway → same pattern
```

> **Nota:** Este teste requer `create_vpn = true` nas suas variáveis.

**O que prova:** VPN e Direct Connect usam o mesmo padrão de TGW attachment. A estrutura dos recursos é idêntica — apenas o transporte subjacente difere.

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

**Como funcionaria o Direct Connect:** Em produção, você substituiria os recursos VPN por:

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

A route table do TGW, os VPC attachments e o roteamento das VPCs permanecem os mesmos. Apenas o tipo de attachment muda de VPN para DX.

---

## 💰 Detalhamento de Custos

Configuração padrão: `create_nat_gateways = true`, `create_vpn = false`.

Os preços variam significativamente por região. São Paulo (sa-east-1) é tipicamente 20-40% mais caro que regiões nos EUA devido a impostos locais e custos de infraestrutura.

### us-east-2 (Ohio) — região padrão

| Recurso | Qtd | $/hr cada | Subtotal/hr | Mensal (730h) | Notas |
|---------|-----|-----------|-------------|---------------|-------|
| EC2 t3.micro | 6 | $0.0104 | $0.062 | $45.55 | 1 instância elegível ao free-tier |
| NAT Gateway | 3 | $0.045 | $0.135 | $98.55 | Defina `create_nat_gateways = false` para pular |
| TGW Attachments | 3 | $0.05 | $0.150 | $109.50 | Cobrado por attachment por hora |
| Interface VPC Endpoints | 9 | $0.01 | $0.090 | $65.70 | 4 shared + 4 vendor + 1 PrivateLink |
| NLB | 1 | $0.0225 | $0.023 | $16.43 | Cobrança mínima mesmo sem tráfego |
| Endereços IPv4 públicos | 4 | $0.005 | $0.020 | $14.60 | 3 NAT EIPs + 1 EC2 IP público |
| VPC Peering | 1 | Gratuito | $0.000 | $0 | Apenas custos de transferência de dados |
| S3 Gateway Endpoints | 3 | Gratuito | $0.000 | $0 | Sempre gratuitos |
| VPN (opcional) | 1 | $0.05 | $0.050 | $36.50 | Apenas se `create_vpn = true` |
| **Total (padrão)** | | | **~$0.48/hr** | **~$350** | **Sem VPN** |

### sa-east-1 (São Paulo)

| Recurso | Qtd | $/hr cada | Subtotal/hr | Mensal (730h) | Notas |
|---------|-----|-----------|-------------|---------------|-------|
| EC2 t3.micro | 6 | $0.0152 | $0.091 | $66.58 | ~46% mais caro que us-east-2 |
| NAT Gateway | 3 | $0.065 | $0.195 | $142.35 | ~44% mais caro que us-east-2 |
| TGW Attachments | 3 | $0.07 | $0.210 | $153.30 | ~40% mais caro que us-east-2 |
| Interface VPC Endpoints | 9 | $0.014 | $0.126 | $91.98 | ~40% mais caro que us-east-2 |
| NLB | 1 | $0.0315 | $0.032 | $22.99 | ~40% mais caro que us-east-2 |
| Endereços IPv4 públicos | 4 | $0.005 | $0.020 | $14.60 | Mesmo preço globalmente |
| VPC Peering | 1 | Gratuito | $0.000 | $0 | Apenas custos de transferência de dados |
| S3 Gateway Endpoints | 3 | Gratuito | $0.000 | $0 | Sempre gratuitos |
| VPN (opcional) | 1 | $0.07 | $0.070 | $51.10 | Apenas se `create_vpn = true` |
| **Total (padrão)** | | | **~$0.67/hr** | **~$492** | **Sem VPN** |

### Custo por cenário

| Cenário | us-east-2/hr | us-east-2/mês | sa-east-1/hr | sa-east-1/mês |
|---------|-------------|---------------|-------------|---------------|
| **Padrão** (NAT on, VPN off) | ~$0.48 | ~$350 | ~$0.67 | ~$492 |
| **Mínimo** (NAT off, VPN off) | ~$0.33 | ~$237 | ~$0.46 | ~$338 |
| **Completo** (NAT on, VPN on) | ~$0.53 | ~$387 | ~$0.73 | ~$535 |

> **Recomendação:** Implante o lab, execute seus testes e depois `terraform destroy`. Uma sessão de 2 horas custa ~$0.96 (us-east-2) ou ~$1.34 (sa-east-1).

> **Nota:** Estes são custos fixos por hora apenas. Transferência de dados (cross-AZ, processamento NAT, processamento de dados TGW, egress de internet) adiciona cobranças extras mas é desprezível para um lab com tráfego mínimo. Preços obtidos das páginas de preços públicas da AWS — consulte a [AWS Pricing Calculator](https://calculator.aws/) para valores exatos e atualizados.

### Dicas de otimização de custos

- Defina `create_nat_gateways = false` para economizar ~$0.135-0.195/hr (você perde os testes de saída da private subnet, mas public e isolated ainda funcionam)
- O lab usa uma única AZ para reduzir custos pela metade vs multi-AZ
- S3 Gateway Endpoints são gratuitos — sempre implante-os
- **Infraestrutura de rede (TGW + NAT + Endpoints) representa ~79% do custo total**, enquanto instâncias EC2 são apenas ~14%

---

## 🏭 Recomendações para Produção

Este lab foi projetado para aprendizado. Aqui está o que você mudaria para produção:

### Transit Gateway
- **Route tables separadas** por tipo de attachment (shared-services vs spoke vs on-premises). O padrão "todos propagam, todos associam" é conveniente mas dá a cada VPC acesso total a todas as outras VPCs.
- **Segmentação de route tables**: Crie uma route table "spoke" que roteia apenas para shared-services, não para outros spokes. O tráfego spoke-para-spoke deve rotear por um firewall na VPC de serviços compartilhados.
- **Inter-region peering**: O TGW suporta peering entre TGWs em diferentes regiões para arquiteturas multi-região.
- **AWS Network Firewall**: Implante no nível do TGW para inspeção centralizada de tráfego entre VPCs.

### VPC Peering
- VPC Peering é melhor para 1-3 conexões. Além disso, o TGW escala melhor.
- Peering **não é transitivo** — se A faz peering com B e B faz peering com C, A não alcança C. Isso é por design.
- Cross-region peering é suportado mas adiciona latência.
- Você não pode fazer peering de VPCs com CIDRs sobrepostos.

### VPC Endpoints
- Implante **Gateway Endpoints** para S3 e DynamoDB em cada VPC — são gratuitos.
- **Centralize Interface Endpoints** em uma VPC de serviços compartilhados e use Route 53 Resolver para resolução DNS cross-VPC. Isso evita pagar por N endpoints × M VPCs.
- Use **VPC Endpoint Policies** para restringir quais recursos podem ser acessados pelo endpoint (ex: apenas buckets S3 específicos).
- **Multi-AZ**: Implante Interface Endpoints em todas as AZs para alta disponibilidade. Cada AZ custa $0.01/hr adicional por endpoint.

### PrivateLink
- Habilite `acceptance_required = true` para aprovar manualmente cada conexão de consumidor.
- Use `allowed_principals` para restringir quais contas AWS podem criar endpoints para seu serviço.
- Considere cenários cross-account — PrivateLink é comumente usado entre diferentes contas AWS dentro da mesma organização.
- Para arquiteturas SaaS, combine PrivateLink com AWS Marketplace para descoberta e faturamento.

### Direct Connect
- Use **Dedicated Connections** (1/10/100 Gbps) para necessidades consistentes de alta largura de banda.
- Use **Hosted Connections** (50 Mbps – 10 Gbps) através de um parceiro para necessidades menores.
- Sempre tenha um **backup VPN** — DX é uma conexão física única e pode falhar.
- Use **DX Gateway** para conectividade multi-região através de uma única conexão DX.
- **LAG (Link Aggregation Group)**: Agrupe múltiplas conexões DX para maior largura de banda e redundância.
- **Criptografia MACsec**: Disponível em conexões dedicated de 10/100 Gbps para criptografia de camada 2.

### Networking em Geral
- **VPC Flow Logs**: Habilite em todas as VPCs para monitoramento e troubleshooting de tráfego. Envie para CloudWatch Logs ou S3.
- **Multi-AZ**: Implante subnets, NAT Gateways e endpoints em pelo menos 2 AZs para alta disponibilidade.
- **Planejamento de CIDRs**: Use CIDRs não sobrepostos em todas as VPCs. Planeje para crescimento — você pode adicionar CIDRs secundários, mas é mais limpo planejar antecipadamente.
- **Security Groups vs NACLs**: Use security groups (stateful, nível de instância) como seu firewall principal. Use NACLs (stateless, nível de subnet) apenas para regras amplas de deny.
- **Resolução DNS**: Habilite `enable_dns_support` e `enable_dns_hostnames` em todas as VPCs. Use Route 53 Private Hosted Zones para service discovery.

---

## 🧹 Limpeza

```bash
# Destroy in reverse order
cd compute
terraform destroy -var="state_bucket=YOUR_BUCKET"

cd ../networking
terraform destroy
```

Ou acione o workflow **Terraform Destroy** via GitHub Actions (`workflow_dispatch`).

Isso remove todos os recursos. Leva ~5-10 minutos (NAT Gateways e TGW attachments são os mais lentos para deletar).

Se o destroy falhar no PrivateLink endpoint, pode ser porque o NLB ainda está drenando. Aguarde 1 minuto e tente novamente.

---

## 📂 Estrutura de Arquivos

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
