terraform {
  required_version = ">= 1.12"

  cloud {
    organization = "aws-platform"

    workspaces {
      name = "tier3_deployments"
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
  }
}

provider "aws" {
  region = "us-east-2"
}

# Reference tier2 compute resources via remote state
data "terraform_remote_state" "compute" {
  backend = "remote"

  config = {
    organization = "aws-platform"
    workspaces = {
      name = "tier2_compute"
    }
  }
}

# EKS cluster data for Helm/Kubernetes providers
data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.compute.outputs.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.compute.outputs.eks_cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
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

  cluster_name = data.terraform_remote_state.compute.outputs.eks_cluster_name
}


# Create ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "systemtool-argocd"
    labels = {
      name = "systemtool-argocd"
    }
  }
}

# Install ArgoCD using Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.17"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    file("${path.module}/argocd/argocd.yaml")
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Install root app using Helm
resource "helm_release" "root_app" {
  name       = "root-app"
  chart      = "./root"
  namespace  = "systemtool-argocd"

  depends_on = [helm_release.argocd]
}
