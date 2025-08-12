variable "workspaces" {
  description = "List of workspaces to create"
  type = list(object({
    name                = string
    description         = string
    global_remote_state = bool
  }))
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "tfc_token" {
  description = "Terraform Cloud API token"
  type        = string
  sensitive   = true
}

variable "hcp_client_id" {
  description = "HCP Client ID for Vault"
  type        = string
  sensitive   = true
}

variable "hcp_client_secret" {
  description = "HCP Client Secret for Vault"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token (repo, admin:repo_hook, admin:org_hook)"
  type        = string
  sensitive   = true
}

variable "user_email" {
  description = "User email for monitoring alerts"
  type        = string
}

# github owner can be either a username (personal) or organization name
variable "github_owner" {
  description = "GitHub owner (username for personal repos, organization name for org repos)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without username)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

output "vault_token" {
  description = "Vault admin token"
  value       = hcp_vault_cluster_admin_token.main.token
  sensitive   = true
}
