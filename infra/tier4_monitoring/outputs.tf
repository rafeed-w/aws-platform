output "monitoring_info" {
  description = "CloudWatch monitoring information"
  value       = <<-EOT

    CloudWatch Monitoring Ready

    Dashboard:
      https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards:name=${aws_cloudwatch_dashboard.eks_monitoring.dashboard_name}
    
    Container Insights:
      https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#container-insights:performance/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'${local.cluster_name})))~context~(orchestrationService~'eks))
    
    Alerts:
      Email: (configured via SNS subscription)
      SNS Topic: ${aws_sns_topic.cloudwatch_alerts.name}
      
    Metrics Available:
      - CPU utilization (webapp & cluster)
      - Memory utilization (webapp & cluster)  
      - Network traffic (webapp)
      - Request rates (webapp)
      - Pod counts and restarts
    
    Next steps:
    1. Update email address in tier4_monitoring.tf
    2. Confirm email subscription in AWS SNS console
    3. View dashboard for webapp metrics
    4. Check Container Insights for detailed analysis
    
    Note: Alarms trigger on high CPU (>80%), memory (>80%), pod restarts (>5), or health check failures

  EOT
}
