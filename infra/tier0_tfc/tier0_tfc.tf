terraform {
  required_version = ">= 1.12"

  cloud {
    organization = "aws-platform" # Change to your TFC organization name

    workspaces {
      name = "tier0_tfc"
    }
  }

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.68.2"
    }
  }
}

provider "tfe" {
  token = var.tfc_token
}

data "tfe_organization" "org" {
  name = "aws-platform" # Change to your TFC organization name
}

resource "tfe_variable_set" "aws_credentials" {
  name         = "aws-credentials"
  description  = "AWS credentials for all workspaces"
  organization = data.tfe_organization.org.name
  global       = true
}

resource "tfe_variable" "aws_access_key_id" {
  key             = "AWS_ACCESS_KEY_ID"
  value           = var.aws_access_key_id
  category        = "env"
  description     = "AWS Access Key ID"
  variable_set_id = tfe_variable_set.aws_credentials.id
  sensitive       = true
}

resource "tfe_variable" "aws_secret_access_key" {
  key             = "AWS_SECRET_ACCESS_KEY"
  value           = var.aws_secret_access_key
  category        = "env"
  description     = "AWS Secret Access Key"
  variable_set_id = tfe_variable_set.aws_credentials.id
  sensitive       = true
}

# Create workspaces
resource "tfe_workspace" "workspaces" {
  for_each     = { for ws in var.workspaces : ws.name => ws }
  name         = each.value.name
  description  = each.value.description
  organization = data.tfe_organization.org.name
}
