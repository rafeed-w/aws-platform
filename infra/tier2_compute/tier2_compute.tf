terraform {
  required_version = ">= 1.12"

  cloud {
    # update org name
    organization = "aws-platform"

    workspaces {
      name = "tier2_compute"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.8.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
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

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
    }
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
  }
}

# tier1 network remote state
data "terraform_remote_state" "network" {
  backend = "remote"

  config = {
    organization = "aws-platform"
    workspaces = {
      name = "tier1_network"
    }
  }
}

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

# eks cluster iam role
resource "aws_iam_role" "eks_cluster" {
  name = "${local.company}-${local.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# eks node group iam role
resource "aws_iam_role" "eks_nodes" {
  name = "${local.company}-${local.environment}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# eks cluster
resource "aws_eks_cluster" "main" {
  name     = "${local.company}-${local.environment}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.33"

  vpc_config {
    subnet_ids = [
      data.terraform_remote_state.network.outputs.private_subnet_1a_id,
      data.terraform_remote_state.network.outputs.private_subnet_1b_id,
      data.terraform_remote_state.network.outputs.public_subnet_1a_id,
      data.terraform_remote_state.network.outputs.public_subnet_1b_id
    ]
    security_group_ids      = [data.terraform_remote_state.network.outputs.eks_cluster_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-eks"
  })
}

# eks node group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.company}-${local.environment}-eks-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids = [
    data.terraform_remote_state.network.outputs.private_subnet_1a_id,
    data.terraform_remote_state.network.outputs.private_subnet_1b_id
  ]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 5
    max_size     = 10
    min_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  # iam permissions required for proper cleanup
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-eks-nodes"
    # cluster autoscaler tags
    "k8s.io/cluster-autoscaler/enabled"                                   = "true"
    "k8s.io/cluster-autoscaler/${local.company}-${local.environment}-eks" = "owned"
  })
}

# current aws account id
data "aws_caller_identity" "current" {}

# eks oidc tls cert
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# oidc identity provider
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-eks-oidc"
  })
}

# cluster autoscaler iam role
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.company}-${local.environment}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}"
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" : "system:serviceaccount:systemtool-cluster-autoscaler:cluster-autoscaler"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" : "sts.amazonaws.com"
        }
      }
    }]
    Version = "2012-10-17"
  })

  tags = local.common_tags
}

# cluster autoscaler policy
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.company}-${local.environment}-cluster-autoscaler-policy"
  description = "eks cluster autoscaler policy"

  policy = jsonencode({
    Statement = [
      {
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
    Version = "2012-10-17"
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.cluster_autoscaler.name
}

# cluster autoscaler namespace
resource "kubernetes_namespace" "cluster_autoscaler" {
  metadata {
    name = "systemtool-cluster-autoscaler"
    labels = {
      name = "systemtool-cluster-autoscaler"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# install cluster autoscaler
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.43.2"
  namespace  = kubernetes_namespace.cluster_autoscaler.metadata[0].name

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = "${local.company}-${local.environment}-eks"
        enabled     = true
      }

      awsRegion = data.vault_generic_secret.platform_config.data["aws_region"]

      cloudProvider = "aws"

      replicaCount = 1

      image = {
        repository = "registry.k8s.io/autoscaling/cluster-autoscaler"
        tag        = "v1.32.1"
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "300Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "300Mi"
        }
      }

      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }

      rbac = {
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
          }
        }
      }

      extraArgs = {
        v                             = 4
        stderrthreshold               = "info"
        cloud-provider                = "aws"
        skip-nodes-with-local-storage = false
        expander                      = "least-waste"
        node-group-auto-discovery     = "asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${local.company}-${local.environment}-eks"
        balance-similar-node-groups   = false
        scale-down-enabled            = true
        scale-down-delay-after-add    = "10m"
        scale-down-unneeded-time      = "10m"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.cluster_autoscaler,
    aws_iam_role_policy_attachment.cluster_autoscaler,
    aws_iam_openid_connect_provider.eks
  ]
}
