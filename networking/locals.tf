locals {
  az = data.aws_availability_zones.available.names[0]

  # Subnet CIDRs follow pattern: 10.X.{1=public, 2=private, 3=isolated}.0/24
  subnets = {
    shared = {
      public   = cidrsubnet(var.vpc_cidrs["shared"], 8, 1) # 10.0.1.0/24
      private  = cidrsubnet(var.vpc_cidrs["shared"], 8, 2) # 10.0.2.0/24
      isolated = cidrsubnet(var.vpc_cidrs["shared"], 8, 3) # 10.0.3.0/24
    }
    app_a = {
      public   = cidrsubnet(var.vpc_cidrs["app_a"], 8, 1) # 10.1.1.0/24
      private  = cidrsubnet(var.vpc_cidrs["app_a"], 8, 2) # 10.1.2.0/24
      isolated = cidrsubnet(var.vpc_cidrs["app_a"], 8, 3) # 10.1.3.0/24
    }
    app_b = {
      public   = cidrsubnet(var.vpc_cidrs["app_b"], 8, 1) # 10.2.1.0/24
      private  = cidrsubnet(var.vpc_cidrs["app_b"], 8, 2) # 10.2.2.0/24
      isolated = cidrsubnet(var.vpc_cidrs["app_b"], 8, 3) # 10.2.3.0/24
    }
    vendor = {
      isolated = cidrsubnet(var.vpc_cidrs["vendor"], 8, 1) # 10.3.1.0/24
    }
  }
}
