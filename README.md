# AWS Platform

[TODO: Architecture Diagram Space]

## Quick Start

### Local Requirements

- Terraform >= 1.12
- Git

Optional cli tools:

- aws
- kubectl
- helm
- hcp
- argocd

### Step 1: Required Accounts (One-time Setup)

Create these accounts if you don't have them:

1. **AWS Account**: [AWS Free Tier](https://aws.amazon.com/free/)
2. **Terraform Cloud**: [app.terraform.io](https://app.terraform.io/signup/account) (can use GitHub Auth)
   - **Important**: Use organization name `aws-platform` or you'll need to update all terraform cloud blocks in tier files
3. **HashiCorp Cloud Platform**: [portal.cloud.hashicorp.com](https://portal.cloud.hashicorp.com/sign-up) (can use GitHub Auth)
4. **GitHub Repository**: Fork this repository to your own GitHub account

### Step 2: Fork and Clone Repository

1. **Fork the repository**: Go to [github.com/rafeed-w/aws-platform](https://github.com/rafeed-w/aws-platform) and click "Fork" to create your own copy
2. **Clone your fork**:

```bash
git clone https://github.com/YOUR_USERNAME/aws-platform.git
cd aws-platform
```

### Step 3: Get Required Credentials (One-time Setup)

**Note**: These credentials are only needed for initial setup. After tier0 deployment, all secrets will be stored securely in HashiCorp Vault.

1. **AWS Access Keys**: Create in AWS Console > IAM > Users > [Security credentials](https://console.aws.amazon.com/iam/home?#security_credential)

2. **Terraform Cloud Token**: Run `terraform login` in terminal, which opens browser to authenticate and generate token automatically

3. **HCP Client Credentials**:

   - Go to HCP Console > Access control (IAM) > Service principals
   - Click "Create" → Give any name → Service: "Project" → Role: "Admin" → Click "Create"
   - In sidebar click "Keys" tab → Click "Generate key"
   - Copy the Client ID and Client Secret (these are your HCP credentials)

4. **GitHub Personal Access Token**:
   - Go to [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)
   - Name: any name
   - Repository access: minimum to your forked repo
   - Click "Add permissions" and configure:
     - **Administration**: Read and Write
     - **Contents**: Read only
     - **Environments**: Read and Write
     - **Secrets**: Read and Write

### Step 4: Configure Environment Variables

Copy the example environment file and configure with your credentials:

```bash
cp example.env .env
```

Edit `.env` with your specific values and load the environment:

**Mac/Linux:**

```bash
source .env
```

```bash
export TF_VAR_aws_access_key_id="AKIA..."                 # AWS access key from Step 3
export TF_VAR_aws_secret_access_key="your_secret_key"     # AWS secret key from Step 3
export TF_VAR_aws_account_id="123456789012"               # Your 12-digit AWS account ID
export TF_VAR_tfc_token="your_terraform_cloud_token"      # From terraform login in Step 3
export TF_VAR_tfc_organization="aws-platform"             # Your TFC organization name (keep "aws-platform" for minimal changes)
export TF_VAR_hcp_client_id="your_hcp_client_id"          # HCP client ID from Step 3
export TF_VAR_hcp_client_secret="your_hcp_client_secret"  # HCP client secret from Step 3
export TF_VAR_github_token="your_github_token"            # GitHub PAT from Step 3
export TF_VAR_github_owner="your_github_username"         # Your GitHub username (or Org name)
export TF_VAR_github_repo="aws-platform"                  # Repository name (keep as-is)
export TF_VAR_user_email="your.email@example.com"         # Your email for notifications
```

**Windows PowerShell:**

```powershell
$env:TF_VAR_aws_access_key_id="AKIA..."                    # AWS access key from Step 3
$env:TF_VAR_aws_secret_access_key="your_secret_key"       # AWS secret key from Step 3
$env:TF_VAR_aws_account_id="123456789012"                 # Your 12-digit AWS account ID
$env:TF_VAR_tfc_token="your_terraform_cloud_token"        # From terraform login in Step 3
$env:TF_VAR_tfc_organization="aws-platform"               # Your TFC organization name (keep "aws-platform" for minimal changes)
$env:TF_VAR_hcp_client_id="your_hcp_client_id"            # HCP client ID from Step 3
$env:TF_VAR_hcp_client_secret="your_hcp_client_secret"    # HCP client secret from Step 3
$env:TF_VAR_github_token="your_github_token"              # GitHub PAT from Step 3
$env:TF_VAR_github_owner="your_github_username"           # Your GitHub username (or Org name)
$env:TF_VAR_github_repo="aws-platform"                    # Repository name (keep as-is)
$env:TF_VAR_user_email="your.email@example.com"           # Your email for notifications
```

### Step 5: Bootstrap Infrastructure (Tier 0)

Navigate to the Tier 0 directory and initialize the bootstrap infrastructure:

```bash
cd infra/tier0_tfc
terraform init
terraform plan
terraform apply
```

This step creates:

- Terraform Cloud workspaces
- HashiCorp Vault cluster
- GitHub environment configurations
- Secret storage in Vault

### Step 4: Deploy All Infrastructure

After successful Tier 0 deployment, trigger the complete infrastructure deployment using the GitHub Actions workflow:

1. Navigate to your GitHub repository
2. Go to Actions tab
3. Select "Apply All Tiers" workflow
4. Click "Run workflow"

**Expected Duration: 20-25 minutes**

This automated process will:

- Deploy network infrastructure (Tier 1)
- Create EKS cluster and compute resources (Tier 2)
- Set up ArgoCD and application deployments (Tier 3)
- Configure monitoring and alerting (Tier 4)
- Build and deploy the web application

### Step 5: Verify Deployment

Monitor the workflow execution and wait for completion (20-25 minutes).

**Important: All deployment URLs will be posted as a GitHub step summary in the "Apply All Tiers" workflow run. Check the workflow summary for:**

- **ArgoCD URL**: GitOps deployment dashboard
- **Web Application URL**: Live application endpoint
- **CloudWatch Dashboard**: Infrastructure monitoring
- **Container Insights**: Detailed EKS metrics

## Infrastructure Tiers

- **Tier 0**: Terraform Cloud setup and HashiCorp Vault configuration
- **Tier 1**: Network infrastructure (VPC, subnets, security groups)
- **Tier 2**: Compute resources (EKS cluster, node groups, autoscaling)
- **Tier 3**: Application deployments (ArgoCD, Helm charts, CI/CD)
- **Tier 4**: Monitoring and observability (CloudWatch, Container Insights)

## Decisions and Tradeoffs

This platform prioritizes ease of setup and demonstration value over production-ready practices. Several best practices were intentionally sacrificed for simplicity.

**Setup and Configuration:**

- Apply-all and destroy-all workflows created for convenience, but production environments would require more granular deployment controls and approval processes
- All secrets initially stored in single .env file before vault migration, production would use separate credential management systems from start
- Manual secret population in vault rather than automated secret rotation and management
- Hardcoded values in outputs and configurations to avoid complexity

**Infrastructure as Code:**

- Used Terraform's kubernetes and helm providers for simplicity, production would avoid these due to state drift issues and maintenance complexity
- Single vault instance without high availability or backup strategies
- Basic workspace setup rather than advanced Terraform Cloud features like policy enforcement

**Application Deployment:**

- Simple ArgoCD setup instead of app-of-apps pattern, production would use app-of-apps for automatic multi-environment deployments
- ArgoCD chosen for GitOps philosophy alignment with IaC principles, eliminating complex CI/CD orchestration
- Container tags use "latest" throughout, production requires semantic versioning and immutable tags
- Single environment deployment, production would require multi-environment promotion workflows

**Monitoring and Observability:**

- CloudWatch-only monitoring instead of comprehensive observability stack, production would benefit from Prometheus and Grafana for detailed application metrics and custom dashboards
- Basic health checks rather than more dedicated tools for request tracing across services
- No application performance monitoring, production could use tools like AWS Application Insights or others

**Security and Network Policy:**

- Basic security groups without Kubernetes network policies, production clusters should implement pod-to-pod communication restrictions
- Single cluster setup without service mesh, production would consider Istio for advanced traffic management and mTLS
- No Pod Security Standards enforcement, production clusters should implement restricted pod security policies

**Data Management and Resilience:**

- No backup strategies for persistent volumes or cluster state
- Single region deployment without disaster recovery, production systems would implement cross-region replication and failover capabilities
- No persistent storage examples, production applications often require StatefulSets with proper PVC management for databases and file storage

**Advanced Platform Features:**

- Basic ECR without multi-region replication, production would replicate container images across regions for availability
- No cost optimization automation, production platforms would include AWS Cost Explorer APIs, resource rightsizing, and spot instance automation
- Manual blue-green switching rather than automated canary deployments with metrics-based rollback

**Operations:**

- Shared admin credentials instead of proper RBAC and individual user management
- Public endpoints enabled for services that should be private in production
- Free-tier resource constraints rather than production-sized infrastructure
- Simplified monitoring without proper alerting escalation procedures

These tradeoffs enable rapid deployment and learning while maintaining architectural patterns suitable for production scaling.

### Key Components

- **Infrastructure as Code**: Terraform with remote state management
- **Container Orchestration**: Amazon EKS with auto-scaling node groups
- **GitOps Deployment**: ArgoCD for continuous deployment
- **Secrets Management**: HashiCorp Vault with OIDC authentication
- **CI/CD Pipeline**: GitHub Actions with OIDC to AWS IAM
- **Monitoring**: CloudWatch dashboards and Container Insights
- **Load Balancing**: NGINX Ingress Controller with cert-manager
- **Application**: Node.js web application with health checks

### Developer Workflows

**Infrastructure Changes:**

- Developer modifies tier1_network/tier1_network.tf -> creates PR -> GitHub Actions runs terraform plan -> posts plan results as PR comment -> team reviews -> PR merged to main -> terraform apply workflow triggers -> requires manual approval through GitHub environment protection -> infrastructure updated

**Application Updates:**

- Developer modifies app/app.js -> creates PR -> webapp build workflow runs Docker build for validation without push -> PR merged to main -> build workflow creates new semantic version tag -> builds and pushes to ECR with version tag and latest tag -> ArgoCD detects new image in ECR -> automatically syncs deployment based on configured image tags in values.yaml

**Blue-Green Deployment Control:**

- Developer wants to promote green to production -> modifies infra/tier3_deployments/webapp/values.yaml -> changes activeVersion from blue to green -> creates PR -> ArgoCD plan shows traffic will switch -> PR approved and merged -> ArgoCD syncs new configuration -> load balancer switches traffic from blue to green environment

## Monitoring and Observability

### CloudWatch Dashboards

Access monitoring dashboards through the AWS Console:

- **EKS Monitoring Dashboard**: Application and cluster metrics
- **Container Insights**: Detailed pod and service analysis

### Available Metrics

- CPU utilization (application and cluster)
- Memory utilization and limits
- Network traffic and request rates
- Pod counts and restart frequencies
- Application response times

### Alerting

SNS notifications are configured for:

- High CPU utilization (>80%)
- High memory utilization (>80%)
- Excessive pod restarts (>5)
- Application health check failures

## Application Features

### Blue-Green Deployments

The web application supports blue-green deployment patterns:

- **Blue Environment**: Currently active production version
- **Green Environment**: New version for testing and validation
- **Traffic Switching**: Controlled rollover between environments

Configuration in `infra/tier3_deployments/webapp/values.yaml`:

```yaml
blueGreen:
  enabled: true
  activeVersion: blue # Switch to 'green' for deployment
```

### Health Checks

Application includes comprehensive health monitoring:

- **Liveness Probe**: `/health` endpoint for container health
- **Readiness Probe**: Application startup verification
- **Load Testing**: `/load-test` endpoint for performance validation

### Auto-scaling

Horizontal Pod Autoscaler configuration:

- Minimum replicas: 2
- Maximum replicas: 10
- CPU target: 50% utilization
- Memory target: 80% utilization

## Security Considerations

### Secrets Management

All sensitive data is stored in HashiCorp Vault:

- AWS credentials
- Terraform Cloud tokens
- GitHub access tokens
- Application secrets

### Network Security

- Private subnets for EKS worker nodes
- Security groups with minimal required access
- NAT Gateway for outbound internet access
- Load balancer in public subnets only

### Access Control

- OIDC authentication for GitHub Actions
- Least privilege IAM roles
- Kubernetes RBAC for service accounts
- ArgoCD authentication and authorization

## Load Testing

Trigger load testing using the GitHub Actions workflow:

1. Navigate to Actions > "Load Test"
2. Configure parameters:
   - Duration (default: 5 minutes)
   - Virtual users (default: 50)
   - Ramp-up time (default: 2 minutes)
3. Monitor results in CloudWatch dashboards

### Resource Cleanup

To avoid charges, destroy infrastructure when not needed:

**Expected Duration: 20-25 minutes**

```bash
# Via GitHub Actions
Actions > "Destroy All Tiers" > Run workflow

# Or manually by tier (reverse order)
cd infra/tier4_monitoring && terraform destroy
cd infra/tier3_deployments && terraform destroy
cd infra/tier2_compute && terraform destroy
cd infra/tier1_network && terraform destroy
```
