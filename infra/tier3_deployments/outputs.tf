# argocd access
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "systemtool-argocd"
  }
  depends_on = [helm_release.argocd]
}

data "kubernetes_service" "nginx_controller" {
  metadata {
    name      = "nginx-ingress-nginx-controller"
    namespace = "systemtool-nginx"
  }
  depends_on = [helm_release.root_app]
}

output "argocd_loadbalancer_dns" {
  description = "ArgoCD LoadBalancer DNS name"
  value       = data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname
}

output "webapp_loadbalancer_dns" {
  description = "WebApp LoadBalancer DNS name (nginx ingress)"
  value       = data.kubernetes_service.nginx_controller.status[0].load_balancer[0].ingress[0].hostname
}

output "argocd_url" {
  description = "ArgoCD UI URL"
  value       = "http://${replace(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname, "***", "us-east-2")}"
}

output "connection_info" {
  description = "ArgoCD connection information"
  value       = <<-EOT

    ArgoCD is ready

    URL:      http://${data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname}
    Username: admin
    Password: admin
    
    Next steps:
    1. Open the URL in your browser
    2. Login with the credentials above
    3. Check that applications are syncing successfully
    
    Note: It may take 2-3 minutes for the LoadBalancer to be fully ready

  EOT
}

output "ecr_repository_url" {
  description = "ECR repository URL for all applications"
  value       = aws_ecr_repository.applications.repository_url
}

output "github_actions_role_arn" {
  description = "GitHub Actions IAM role ARN for CI/CD"
  value       = aws_iam_role.github_actions.arn
}
