# CloudWatch Dashboard URL
output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL for EKS monitoring"
  value       = "https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards:name=${aws_cloudwatch_dashboard.eks_monitoring.dashboard_name}"
}

# Container Insights URL
output "container_insights_url" {
  description = "CloudWatch Container Insights URL"
  value       = "https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#container-insights:performance/EKS:Cluster/${local.cluster_name}"
}

# SNS Topic for alerts
output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for CloudWatch alerts"
  value       = aws_sns_topic.cloudwatch_alerts.arn
}

# CloudWatch Add-on status
output "cloudwatch_addon_status" {
  description = "Status of the CloudWatch Observability add-on"
  value       = aws_eks_addon.cloudwatch_observability.addon_name
}

# Connection information
output "monitoring_info" {
  description = "Complete CloudWatch monitoring connection information"
  value       = <<-EOT
    
    📊 CloudWatch Monitoring Stack Ready!
    
    📈 Dashboard:
      URL: https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#dashboards:name=${aws_cloudwatch_dashboard.eks_monitoring.dashboard_name}
    
    🔍 Container Insights:
      URL: https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#container-insights:performance/EKS:Cluster/${local.cluster_name}
    
    🚨 Alerts:
      SNS Topic: ${aws_sns_topic.cloudwatch_alerts.name}
      Email: admin@thrive.local (update this!)
      
    📊 Metrics Available:
      ✅ CPU utilization (nodes & pods)
      ✅ Memory utilization (nodes & pods)  
      ✅ Pod restart counts
      ✅ Request rates (from ALB)
      ✅ Container logs
    
    📝 Next steps:
    1. Confirm email subscription in AWS SNS console
    2. View the dashboard to see metrics
    3. Check Container Insights for detailed pod/node views
    4. Alarms will trigger on high CPU (>80%), memory (>80%), or pod restarts (>5)
    
    💡 Tip: Update email address in tier4_monitoring.tf before applying
    
  EOT
}

# Individual alarm ARNs for reference
output "alarm_arns" {
  description = "CloudWatch alarm ARNs"
  value = {
    high_cpu    = aws_cloudwatch_metric_alarm.high_cpu_utilization.arn
    high_memory = aws_cloudwatch_metric_alarm.high_memory_utilization.arn
    pod_restart = aws_cloudwatch_metric_alarm.pod_restart_high.arn
  }
}