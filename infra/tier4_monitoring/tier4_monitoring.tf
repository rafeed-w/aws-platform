terraform {
  required_version = ">= 1.12"

  cloud {
    # Change to your TFC organization name if different
    organization = "aws-platform"

    workspaces {
      name = "tier4_monitoring"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.8.0"
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

# Reference tier2 compute resources via remote state
data "terraform_remote_state" "compute" {
  backend = "remote"

  config = {
    organization = data.vault_generic_secret.platform_config.data["tfc_organization"]
    workspaces = {
      name = "tier2_compute"
    }
  }
}

# EKS cluster data
data "aws_eks_cluster" "cluster" {
  name = data.terraform_remote_state.compute.outputs.eks_cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.compute.outputs.eks_cluster_name
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

# CloudWatch Observability Add-on for EKS
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = local.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.cloudwatch_agent.arn

  depends_on = [
    aws_iam_role_policy_attachment.cloudwatch_agent_server_policy,
    aws_iam_role_policy_attachment.cloudwatch_container_insights
  ]

  tags = local.common_tags
}

# IAM Role for CloudWatch Agent (IRSA)
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${local.company}-${local.environment}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.terraform_remote_state.compute.outputs.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Federated = data.terraform_remote_state.compute.outputs.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:fluent-bit"
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach CloudWatch Agent Server Policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_agent.name
}

# Attach Container Insights Policy  
resource "aws_iam_role_policy_attachment" "cloudwatch_container_insights" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.cloudwatch_agent.name
}

# CloudWatch Log Groups

resource "aws_cloudwatch_log_group" "fluent_bit" {
  name              = "/aws/containerinsights/${local.cluster_name}/application"
  retention_in_days = 7
  tags              = local.common_tags
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "cloudwatch_alerts" {
  name = "${local.company}-${local.environment}-cloudwatch-alerts"
  tags = local.common_tags
}

# SNS Topic Subscription - email needs to be set manually or via variable
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.cloudwatch_alerts.arn
  protocol  = "email"
  endpoint  = data.vault_generic_secret.platform_config.data["user_email"]
}

# CloudWatch Alarms for EKS Cluster
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "${local.cluster_name}-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = "60"
  alarm_description   = "This metric monitors EKS node CPU utilization"
  alarm_actions       = [aws_sns_topic.cloudwatch_alerts.arn]

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  alarm_name          = "${local.cluster_name}-high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = "60"
  alarm_description   = "This metric monitors EKS node memory utilization"
  alarm_actions       = [aws_sns_topic.cloudwatch_alerts.arn]

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "pod_restart_high" {
  alarm_name          = "${local.cluster_name}-pod-restart-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "pod_number_of_container_restarts"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors pod restart count"
  alarm_actions       = [aws_sns_topic.cloudwatch_alerts.arn]

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = local.common_tags
}

# Health Check Alarm for webapp
resource "aws_cloudwatch_metric_alarm" "webapp_health_check" {
  alarm_name          = "${local.cluster_name}-webapp-health-check"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetHealth"
  namespace           = "AWS/NetworkELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors webapp health check status"
  alarm_actions       = [aws_sns_topic.cloudwatch_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = "net/a4dbbf5d1f7d448ac9fe5abf54b950d1"
  }

  tags = local.common_tags
}

# CloudWatch Dashboard focused on webapp monitoring
resource "aws_cloudwatch_dashboard" "eks_monitoring" {
  dashboard_name = "${local.company}-${local.environment}-eks-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Webapp Metrics
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization_over_pod_limit", "ClusterName", local.cluster_name, "Namespace", "thrive-webapp"]
          ]
          period = 300
          stat   = "Average"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Webapp CPU (% of Pod Limit)"
          yAxis = {
            left = {
              min = 0
              max = 50
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "pod_memory_utilization_over_pod_limit", "ClusterName", local.cluster_name, "Namespace", "thrive-webapp"]
          ]
          period = 300
          stat   = "Average"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Webapp Memory (% of Pod Limit)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["AWS/NetworkELB", "NewFlowCount", "LoadBalancer", "net/a4dbbf5d1f7d448ac9fe5abf54b950d1"]
          ]
          period = 300
          stat   = "Sum"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Webapp Requests/sec"
        }
      },
      # Row 2: Webapp Network & Pod Count
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "pod_network_rx_bytes", "ClusterName", local.cluster_name, "Namespace", "thrive-webapp"],
            [".", "pod_network_tx_bytes", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Webapp Network Traffic (Bytes/sec)"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "service_number_of_running_pods", "ClusterName", local.cluster_name, "Namespace", "thrive-webapp"]
          ]
          period = 300
          stat   = "Average"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Webapp Running Pods"
        }
      },
      # Row 3: Cluster Overview
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", local.cluster_name]
          ]
          period = 300
          stat   = "Average"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Cluster Ready Nodes"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", local.cluster_name],
            [".", "node_memory_utilization", ".", "."]
          ]
          period = 300
          stat   = "Maximum"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Node Resource Utilization (%)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "node_filesystem_utilization", "ClusterName", local.cluster_name]
          ]
          period = 300
          stat   = "Maximum"
          region = data.vault_generic_secret.platform_config.data["aws_region"]
          title  = "Node Filesystem Usage (%)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      # Row 4: Text Instructions
      {
        type   = "text"
        x      = 0
        y      = 18
        width  = 24
        height = 2

        properties = {
          markdown = "**For detailed analysis:** Go to CloudWatch → Container Insights"
        }
      }
    ]
  })
}
