# AWS Platform

## Architecture Overview

This platform implements a multi-tier infrastructure approach with complete automation, secrets management, and monitoring capabilities.

### Infrastructure Tiers

- **Tier 0**: Terraform Cloud setup and HashiCorp Vault configuration
- **Tier 1**: Network infrastructure (VPC, subnets, security groups)
- **Tier 2**: Compute resources (EKS cluster, node groups, autoscaling)
- **Tier 3**: Application deployments (ArgoCD, Helm charts, CI/CD)
- **Tier 4**: Monitoring and observability (CloudWatch, Container Insights)

[Architecture Diagram Space]

### Key Components

- **Infrastructure as Code**: Terraform with remote state management
- **Container Orchestration**: Amazon EKS with auto-scaling node groups
- **GitOps Deployment**: ArgoCD for continuous deployment
- **Secrets Management**: HashiCorp Vault with OIDC authentication
- **CI/CD Pipeline**: GitHub Actions with OIDC to AWS IAM
- **Monitoring**: CloudWatch dashboards and Container Insights
- **Load Balancing**: NGINX Ingress Controller with cert-manager
- **Application**: Node.js web application with health checks

## Prerequisites

### Local Requirements

- Terraform >= 1.12
- Git

Optional tools:

- kubectl
- helm
- hcp
- argocd

## Quick Start

### Step 1: Required Accounts (One-time Setup)

Create these accounts if you don't have them:

1. **AWS Account**: [AWS Free Tier](https://aws.amazon.com/free/)
2. **Terraform Cloud**: [app.terraform.io](https://app.terraform.io/signup/account) (can use GitHub Auth)
3. **HashiCorp Cloud Platform**: [portal.cloud.hashicorp.com](https://portal.cloud.hashicorp.com/sign-up) (can use GitHub Auth)
4. **GitHub Repository**: Fork or create repository for this code

### Step 2: Clone Repository

```bash
git clone https://github.com/your-username/aws-platform.git
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
export TF_VAR_tfc_organization="your_tfc_org_name"        # Your TFC organization name
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
$env:TF_VAR_tfc_organization="your_tfc_org_name"          # Your TFC organization name
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

This automated process will:

- Deploy network infrastructure (Tier 1)
- Create EKS cluster and compute resources (Tier 2)
- Set up ArgoCD and application deployments (Tier 3)
- Configure monitoring and alerting (Tier 4)
- Build and deploy the web application

### Step 5: Verify Deployment

Monitor the workflow execution and wait for completion (approximately 15-20 minutes). Upon successful deployment, you will receive:

- **ArgoCD URL**: GitOps deployment dashboard
- **Web Application URL**: Live application endpoint
- **CloudWatch Dashboard**: Infrastructure monitoring
- **Container Insights**: Detailed EKS metrics

## Infrastructure Management

### Terraform Workspaces

Each tier is managed in separate Terraform Cloud workspaces:

- `tier1_network`: VPC and networking components
- `tier2_compute`: EKS cluster and compute resources
- `tier3_deployments`: ArgoCD and application manifests
- `tier4_monitoring`: CloudWatch and observability setup

### GitHub Actions Workflows

Individual workflows for each tier provide granular control:

- `tier1-network.yml`: Network infrastructure changes
- `tier2-compute.yml`: EKS cluster modifications
- `tier3-deployments.yml`: Application deployment updates
- `tier4-monitoring.yml`: Monitoring configuration changes
- `webapp-build-push.yml`: Application container builds
- `apply-all.yml`: Complete infrastructure deployment
- `destroy-all.yml`: Full environment teardown

### ArgoCD Applications

GitOps-managed applications include:

- **thrive-webapp**: Main Node.js application with blue-green deployment
- **nginx**: Ingress controller for traffic routing
- **cert-manager**: TLS certificate management

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

```bash
# Via GitHub Actions
Actions > "Destroy All Tiers" > Run workflow

# Or manually by tier (reverse order)
cd infra/tier4_monitoring && terraform destroy
cd infra/tier3_deployments && terraform destroy
cd infra/tier2_compute && terraform destroy
cd infra/tier1_network && terraform destroy
```
