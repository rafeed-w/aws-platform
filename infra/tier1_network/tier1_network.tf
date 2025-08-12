terraform {
  required_version = ">= 1.12"

  cloud {
    # Change to your TFC organization name if different
    organization = "aws-platform"

    workspaces {
      name = "tier1_network"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.8.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

data "vault_generic_secret" "platform_config" {
  path = "secret/platform"
}

provider "aws" {
  region = data.vault_generic_secret.platform_config.data["aws_region"]
}

# TODO: Add later - ECR repository, S3 bucket, VPC Flow Logs 
# (These will be added in observability tier)

locals {
  environment = "test"
  company     = "thrive"
  common_tags = {
    Environment = local.environment
    Company     = local.company
    ManagedBy   = "terraform"
    Project     = "aws-platform"
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-vpc"
  })
}

# Public Subnets (for Load Balancers)
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${data.vault_generic_secret.platform_config.data["aws_region"]}a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-public-1a"
    Type = "public"
  })
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${data.vault_generic_secret.platform_config.data["aws_region"]}b"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-public-1b"
    Type = "public"
  })
}

# Private Subnets (for EKS Nodes)
resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${data.vault_generic_secret.platform_config.data["aws_region"]}a"

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-private-1a"
    Type = "private"
  })
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${data.vault_generic_secret.platform_config.data["aws_region"]}b"

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-private-1b"
    Type = "private"
  })
}

# Security Group for EKS Cluster Control Plane
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${local.company}-${local.environment}-eks-cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-eks-cluster-sg"
  })
}

# Security Group for EKS Worker Nodes
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${local.company}-${local.environment}-eks-nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Node to node communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-eks-nodes-sg"
  })
}

# Security Group Rules (separate resources to avoid circular dependency)
resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_nodes.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "HTTPS from worker nodes"
}

resource "aws_security_group_rule" "nodes_ingress_from_cluster" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_nodes.id
  description              = "Control plane to nodes"
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-igw"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-nat-eip"
  })
}

# NAT Gateway (in public subnet for private subnet internet access)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1a.id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-nat-gw"
  })
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-public-rt"
  })
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-private-rt"
  })
}

# Route Table Associations - Public Subnets
resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

# Route Table Associations - Private Subnets
resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private.id
}
