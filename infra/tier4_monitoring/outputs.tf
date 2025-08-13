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
      
    Note: Alarms trigger on high CPU (>80%), memory (>80%), pod restarts (>5), or health check failures

  EOT
}
