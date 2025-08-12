workspaces = [
  {
    name                = "tier1_network"
    description         = "VPC, subnets, security groups, and network infrastructure"
    global_remote_state = true
  },
  {
    name                = "tier2_compute"
    description         = "EKS cluster, node groups, and container orchestration"
    global_remote_state = true
  },
  {
    name                = "tier3_deployments"
    description         = "ArgoCD, Helm deployments, and Kubernetes applications"
    global_remote_state = true
  },
  {
    name                = "tier4_monitoring"
    description         = "CloudWatch monitoring, Container Insights, and alerting"
    global_remote_state = false
  }
]
