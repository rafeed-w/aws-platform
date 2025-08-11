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
  }
]
