# ArgoCD Access Information
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "systemtool-argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_url" {
  description = "ArgoCD UI URL"
  value       = "http://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname}"
}

output "argocd_username" {
  description = "ArgoCD admin username"
  value       = "admin"
}

output "argocd_password" {
  description = "ArgoCD admin password"
  value       = "admin123"
  sensitive   = false # Making it visible in output for convenience
}

output "connection_info" {
  description = "Complete ArgoCD connection information"
  value       = <<-EOT
    
    🚀 ArgoCD is ready!
    
    URL:      http://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname}
    Username: admin
    Password: admin
    
    📝 Next steps:
    1. Open the URL in your browser
    2. Login with the credentials above
    3. Check that applications are syncing successfully
    
    💡 Tip: It may take 2-3 minutes for the LoadBalancer to be fully ready
    
  EOT
}

# Additional useful outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster applications are deployed to"
  value       = data.terraform_remote_state.compute.outputs.eks_cluster_name
}

output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

# System tool namespaces for monitoring
output "systemtool_namespaces" {
  description = "List of system tool namespaces for monitoring"
  value = [
    "systemtool-argocd",
    "systemtool-nginx",
    "systemtool-cert-manager"
  ]
}

# ArgoCD service information for monitoring
output "argocd_service_name" {
  description = "ArgoCD server service name"
  value       = "argocd-server"
}

# Application namespaces
output "application_namespaces" {
  description = "List of application namespaces for monitoring"
  value = [
    "thrive-webapp"
  ]
}
