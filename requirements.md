---
- Objective -
---

Your task is to provision infrastructure and deploy a basic web application in a
scalable and observable way. You will use tools commonly seen in DevOps workflows.

---

- Requirements -

---

1. Infrastructure Provisioning

- Use Terraform to provision cloud resources (AWS preferred).
- Infrastructure should include:
- A virtual private cloud (VPC)
- A container orchestration platform (EKS/GKE/AKS or Docker + EC2)
- A load balancer
- Auto-scaling groups or node pools

2. Application Deployment

- Deploy a simple web app (very basic hello_world Node.js app).
- Containerize it using Docker.
- Deploy using Kubernetes or Docker Compose, depending on what you set up.
- Include a CI/CD pipeline (GitHub Actions, GitLab CI, CircleCI, etc.) that:
  - Builds Docker images
  - Pushes to a container registry (Docker Hub, ECR, etc.)
  - Deploys to the cluster

3. Monitoring & Logging

- Ensure basic metrics (CPU, memory, requests/sec) are exposed and viewable.
- Set up basic alerting (email/Slack webhook is fine).

4. Bonus Points

- Add HTTPS using cert-manager or a reverse proxy with TLS.
- Implement blue-green or canary deployments.
- Use Secrets management (AWS Secrets Manager, HashiCorp Vault, etc.).
- Add health checks for the deployed app.

---

- Deliverables -

---

- A GitHub repository with:
- `README.md` explaining architecture, how to deploy, and how to checks
- Where to check alerting and monitoring dashboards
- Infrastructure code
- CI/CD config
- Dockerfile(s)
- Kubernetes manifests or Docker Compose
- Diagrams or notes on:
- System architecture
- Any tradeoffs or decisions you made
- Replication instructions
- step by step instructions on how to clone the github repository and deploy it
  start to finish on another AWS account
  Use a brand new, free AWS account and resources. Avoid any additional billing.
