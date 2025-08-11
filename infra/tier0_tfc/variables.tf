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
