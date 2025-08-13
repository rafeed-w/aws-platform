terraform {
  required_version = ">= 1.12"

  cloud {
    # update org name
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
  region = data.vault_generic_secret.platform_config.data["aws_region"]
}

# vault provider from env vars
provider "vault" {}

# platform config from vault
data "vault_generic_secret" "platform_config" {
  path = "secret/platform"
}

data "vault_generic_secret" "argocd_git" {
  path = "secret/argocd"
}

# tier2 compute remote state
data "terraform_remote_state" "compute" {
  backend = "remote"

  config = {
    organization = data.vault_generic_secret.platform_config.data["tfc_organization"]
    workspaces = {
      name = "tier2_compute"
    }
  }
}

# eks cluster data
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


# argocd namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "systemtool-argocd"
    labels = {
      name = "systemtool-argocd"
    }
  }
}

# install argocd with dynamic config
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.17"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    file("${path.module}/argocd/argocd.yaml"),
    yamlencode({
      configs = {
        cm = {
          # github repo credentials from vault
          "credentialTemplates.github" = yamlencode({
            url = "https://github.com/${data.vault_generic_secret.argocd_git.data["github_owner"]}"
            username = "oauth2"
            password = data.vault_generic_secret.argocd_git.data["github_token"]
          })

          # git and helm repositories
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
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# root app with ecr injection
resource "helm_release" "root_app" {
  name      = "root-app"
  chart     = "./root"
  namespace = "systemtool-argocd"

  # pass ecr url to apps
  set {
    name  = "global.ecrRepository"
    value = aws_ecr_repository.applications.repository_url
  }

  set {
    name  = "global.githubRepoUrl"
    value = data.vault_generic_secret.argocd_git.data["repo_url"]
  }

  depends_on = [helm_release.argocd]
}

# ecr repository
resource "aws_ecr_repository" "applications" {
  name                 = "${local.company}-${local.environment}-applications"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # allow deletion with images

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.company}-${local.environment}-applications-ecr"
  })
}

# ecr lifecycle policy
resource "aws_ecr_lifecycle_policy" "applications" {
  repository = aws_ecr_repository.applications.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "keep last 10 images"
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
        description  = "delete old untagged images"
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

# github oidc provider
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

# github actions iam role
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

# ecr access policy
resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${local.company}-${local.environment}-github-actions-ecr-policy"
  description = "github actions ecr push policy"

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

# attach ecr policy
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  policy_arn = aws_iam_policy.github_actions_ecr.arn
  role       = aws_iam_role.github_actions.name
}
