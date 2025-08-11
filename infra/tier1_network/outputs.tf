# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnet Outputs
output "private_subnet_1a_id" {
  description = "ID of the private subnet in AZ 1a"
  value       = aws_subnet.private_1a.id
}

output "private_subnet_1b_id" {
  description = "ID of the private subnet in AZ 1b"
  value       = aws_subnet.private_1b.id
}

output "public_subnet_1a_id" {
  description = "ID of the public subnet in AZ 1a"
  value       = aws_subnet.public_1a.id
}

output "public_subnet_1b_id" {
  description = "ID of the public subnet in AZ 1b"
  value       = aws_subnet.public_1b.id
}

# Security Group Outputs
output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}