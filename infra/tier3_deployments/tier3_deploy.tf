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
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# vault provider configured via environment variables from tier0
provider "vault" {}

# read platform config from vault
data "vault_generic_secret" "platform_config" {
  path = "secret/platform"
}

data "vault_generic_secret" "argocd_git" {
  path = "secret/argocd"
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

# Install ArgoCD using Helm with dynamic configuration
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.17"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      controller = {
        replicas = 1
      }

      server = {
        replicas = 1
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }
        extraArgs = ["--insecure"]
      }

      repoServer = {
        replicas = 1
      }

      applicationSet = {
        enabled = true
        replicas = 1
      }

      notifications = {
        enabled = false
      }

      dex = {
        enabled = false
      }

      configs = {
        params = {
          "server.insecure" = true
        }

        cm = {
          # credential template for private github repos
          "credentialTemplates.github" = yamlencode({
            url = "https://github.com/${data.vault_generic_secret.argocd_git.data["github_owner"]}"
            username = "oauth2"
            password = data.vault_generic_secret.argocd_git.data["github_token"]
          })

          # repositories for git and helm
          repositories = yamlencode([
            {
              type = "git"
              url  = data.vault_generic_secret.argocd_git.data["repo_url"]
            },
            {
              type = "helm"
              name = "ecr-helm"
              url  = "oci://${aws_ecr_repository.applications.repository_url}"
              enableOCI = true
            }
          ])
        }

        secret = {
          argocdServerAdminPassword = "$2a$10$yGT7V/vbE0ekkZHiaHvOhOsoh0EaJ7EXhgG8WHEzP1vG1x2s5MY.W"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Install root app using Helm with dynamic ECR injection
resource "helm_release" "root_app" {
  name      = "root-app"
  chart     = "./root"
  namespace = "systemtool-argocd"

  # pass ECR repository URL to ArgoCD apps
  set {
    name  = "global.ecrRepository"
    value = aws_ecr_repository.applications.repository_url
  }

  set {
    name  = "global.userEmail"
    value = data.vault_generic_secret.platform_config.data["user_email"]
  }

  depends_on = [helm_release.argocd]
}

# ECR Repository for application container images and helm charts
resource "aws_ecr_repository" "applications" {
  name                 = "${local.company}-${local.environment}-applications"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-applications-ecr"
  })
}

# ECR Lifecycle Policy to manage image retention
resource "aws_ecr_lifecycle_policy" "applications" {
  repository = aws_ecr_repository.applications.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Create GitHub OIDC provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = local.common_tags
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "${local.company}-${local.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${data.vault_generic_secret.platform_config.data["github_owner"]}/${data.vault_generic_secret.platform_config.data["github_repo"]}:*"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for ECR access
resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${local.company}-${local.environment}-github-actions-ecr-policy"
  description = "Policy for GitHub Actions to push to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:ListTagsForResource",
          "ecr:DescribeImageScanFindings"
        ]
        Resource = aws_ecr_repository.applications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = aws_ecr_repository.applications.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach ECR policy to GitHub Actions role
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  policy_arn = aws_iam_policy.github_actions_ecr.arn
  role       = aws_iam_role.github_actions.name
}
