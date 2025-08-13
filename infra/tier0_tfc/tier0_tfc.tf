terraform {
  required_version = ">= 1.12"

  cloud {
    organization = "aws-platform" # update org name

    workspaces {
      name = "tier0_tfc"
    }
  }

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.68.2"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.84"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "tfe" {
  token = var.tfc_token
}

provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
}

provider "github" {
  token = var.github_token
}

# hcp vault cluster
resource "hcp_hvn" "main" {
  hvn_id         = "${var.tfc_organization}-hvn"
  cloud_provider = "aws"
  region         = var.aws_region
  cidr_block     = "172.25.16.0/20"
}

resource "hcp_vault_cluster" "main" {
  cluster_id      = "${var.tfc_organization}-vault"
  hvn_id          = hcp_hvn.main.hvn_id
  tier            = "dev" # free tier
  public_endpoint = true
}

# vault admin token
resource "hcp_vault_cluster_admin_token" "main" {
  cluster_id = hcp_vault_cluster.main.cluster_id
}

# configure vault provider
provider "vault" {
  address = hcp_vault_cluster.main.vault_public_endpoint_url
  token   = hcp_vault_cluster_admin_token.main.token
}

# kv secrets engine
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "platform secrets"

  depends_on = [hcp_vault_cluster.main]
}

# platform secrets in vault
resource "vault_generic_secret" "aws_credentials" {
  path = "secret/aws"

  data_json = jsonencode({
    access_key_id     = var.aws_access_key_id
    secret_access_key = var.aws_secret_access_key
    account_id        = var.aws_account_id
  })

  depends_on = [vault_mount.kv]
}

resource "vault_generic_secret" "platform_config" {
  path = "secret/platform"

  data_json = jsonencode({
    user_email       = var.user_email
    github_owner     = var.github_owner
    github_repo      = var.github_repo
    github_token     = var.github_token
    tfc_organization = var.tfc_organization
    aws_region       = var.aws_region
    environment      = "test"
  })

  depends_on = [vault_mount.kv]
}

resource "vault_generic_secret" "terraform_cloud" {
  path = "secret/terraform"

  data_json = jsonencode({
    token        = var.tfc_token
    organization = var.tfc_organization
  })

  depends_on = [vault_mount.kv]
}

resource "vault_generic_secret" "hcp_credentials" {
  path = "secret/hcp"

  data_json = jsonencode({
    client_id     = var.hcp_client_id
    client_secret = var.hcp_client_secret
  })

  depends_on = [vault_mount.kv]
}

# github actions jwt auth
resource "vault_jwt_auth_backend" "github_actions" {
  path        = "jwt"
  description = "GitHub Actions JWT authentication"

  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"

  depends_on = [hcp_vault_cluster.main]
}

# github actions role
resource "vault_jwt_auth_backend_role" "github_actions_role" {
  backend   = vault_jwt_auth_backend.github_actions.path
  role_name = "github-actions-role"

  token_policies = ["github-actions-policy"]

  bound_audiences = ["https://github.com/${var.github_owner}"]
  bound_claims = {
    repository = "${var.github_owner}/${var.github_repo}"
  }

  user_claim    = "actor"
  role_type     = "jwt"
  token_ttl     = 3600
  token_max_ttl = 3600
}

# github actions secrets policy
resource "vault_policy" "github_actions" {
  name = "github-actions-policy"

  policy = <<EOT
path "secret/*" {
  capabilities = ["read"]
}
EOT
}

# github environments
resource "github_repository_environment" "terraform_plan" {
  environment = "terraform-plan"
  repository  = var.github_repo
}

resource "github_repository_environment" "terraform_apply" {
  environment = "terraform-apply"
  repository  = var.github_repo

  reviewers {
    users = [data.github_user.current.id]
  }
}

data "github_user" "current" {
  username = var.github_owner
}

# vault secrets as repo secrets
resource "github_actions_secret" "vault_url" {
  repository      = var.github_repo
  secret_name     = "VAULT_URL"
  plaintext_value = hcp_vault_cluster.main.vault_public_endpoint_url
}

resource "github_actions_secret" "vault_token" {
  repository      = var.github_repo
  secret_name     = "VAULT_TOKEN"
  plaintext_value = hcp_vault_cluster_admin_token.main.token
}

# argocd github access
resource "vault_generic_secret" "argocd_git" {
  path = "secret/argocd"

  data_json = jsonencode({
    github_token = var.github_token
    repo_url     = "https://github.com/${var.github_owner}/${var.github_repo}"
    github_owner = var.github_owner
  })

  depends_on = [vault_mount.kv]
}

# tfc workspaces
data "tfe_organization" "org" {
  name = var.tfc_organization
}

resource "tfe_variable_set" "vault_credentials" {
  name         = "vault-credentials"
  description  = "Vault credentials for all workspaces"
  organization = data.tfe_organization.org.name
  global       = true
}

resource "tfe_variable" "vault_addr" {
  key             = "VAULT_ADDR"
  value           = hcp_vault_cluster.main.vault_public_endpoint_url
  category        = "env"
  description     = "Vault cluster address"
  variable_set_id = tfe_variable_set.vault_credentials.id
}

resource "tfe_variable" "vault_token" {
  key             = "VAULT_TOKEN"
  value           = hcp_vault_cluster_admin_token.main.token
  category        = "env"
  description     = "Vault access token"
  variable_set_id = tfe_variable_set.vault_credentials.id
  sensitive       = true
}

# aws credentials for all workspaces
resource "tfe_variable" "aws_access_key_id" {
  key             = "AWS_ACCESS_KEY_ID"
  value           = var.aws_access_key_id
  category        = "env"
  description     = "AWS Access Key ID"
  variable_set_id = tfe_variable_set.vault_credentials.id
  sensitive       = true
}

resource "tfe_variable" "aws_secret_access_key" {
  key             = "AWS_SECRET_ACCESS_KEY"
  value           = var.aws_secret_access_key
  category        = "env"
  description     = "AWS Secret Access Key"
  variable_set_id = tfe_variable_set.vault_credentials.id
  sensitive       = true
}

resource "tfe_variable" "aws_region" {
  key             = "AWS_DEFAULT_REGION"
  value           = var.aws_region
  category        = "env"
  description     = "AWS Default Region"
  variable_set_id = tfe_variable_set.vault_credentials.id
}

# create workspaces
resource "tfe_workspace" "workspaces" {
  for_each     = { for ws in var.workspaces : ws.name => ws }
  name         = each.value.name
  description  = each.value.description
  organization = data.tfe_organization.org.name
}

resource "tfe_workspace_settings" "workspace_settings" {
  for_each     = { for ws in var.workspaces : ws.name => ws }
  workspace_id = tfe_workspace.workspaces[each.key].id

  global_remote_state = each.value.global_remote_state
}
