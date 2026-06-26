# 🌌 AWS EKS GitOps Boilerplate

<p>
  <img src="https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform" />
  <img src="https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white" alt="AWS" />
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes" />
  <img src="https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white" alt="Helm" />
  <img src="https://img.shields.io/badge/Argo%20CD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white" alt="Argo CD" />
  <img src="https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white" alt="GitHub Actions" />
</p>

## 📖 Project Overview & Vision
This repository is an **open-source, globally reusable GitOps and Infrastructure-as-Code (IaC) boilerplate template**. It is designed to act as a launchpad for DevOps and Platform Engineers who want to bootstrap a production-grade AWS EKS environment with a fully automated, keyless CI/CD pipeline and an Argo CD GitOps engine.

Initially built to solve the operational friction of managing distributed microservices, this repository centralizes infrastructure definition (Terraform) and Kubernetes orchestration into a single, highly governed monorepo. It serves as both a demonstration of advanced Zero-Trust DevOps practices and a plug-and-play template for modern cloud-native deployments.

## 🛠️ How to Use This Template

If you have forked or cloned this repository to start your own platform, you must inject your specific environments, names, and AWS IDs into the codebase. We have sanitized all hardcoded values into standard placeholders.

To make this frictionless, we have provided an automated bootstrap script.

1. **Edit the Script**: Open `bootstrap-template.sh` in the root of the repository and update the variables at the top of the file with your specific credentials:
   ```bash
   export PROJECT_NAME="my-awesome-app"
   export AWS_ACCOUNT_ID="123456789012"
   ...
   ```
2. **Run the Script**: Execute the script in your terminal to automatically hydrate the boilerplate across all files:
   ```bash
   ./bootstrap-template.sh
   ```
3. **Enable CI/CD**: Open `.github/workflows/terraform-cicd.yaml` and uncomment the `push:` and `pull_request:` triggers to activate your deployment pipeline.

> **Important Note:** You must also manually replace `my-project-terraform-state-bucket`, `my-project-terraform-lock-table`, and `my-eks-cluster` with your own unique names inside the Terraform files to avoid AWS state collisions. See the **[Reusability Guide](docs/REUSABILITY_GUIDE.md)** for the full checklist!

## ✨ Key Features
*   **Declarative Infrastructure:** Physical AWS compute and networking layers (EKS, VPCs, IAM) are strictly managed via Terraform.
*   **GitOps Automation:** Argo CD ApplicationSets dynamically discover and deploy new microservices without manual intervention.
*   **Automated Image Rollouts:** The Argo CD Image Updater securely polls AWS ECR for new Docker tags and pushes Git commits back to this repository, ensuring the infrastructure documents its own release history.
*   **Keyless CI/CD Security:** GitHub Actions utilizes AWS OIDC (OpenID Connect) to dynamically assume temporary roles, eliminating hardcoded access keys.
*   **Native AWS ECR Authentication:** Implements a highly secure, Kubernetes-native CronJob architecture using IRSA (IAM Roles for Service Accounts) to rotate credentials seamlessly.
*   **Day 2 Operations & Observability:** Integrated with **Prometheus & Grafana** for deep cluster metrics, health monitoring, and performance dashboards out-of-the-box.
*   **Active Alerting & Notifications:** Configured with Argo CD SMTP bindings to instantly alert your engineering team (via Email/Slack) whenever a deployment succeeds, fails, or degrades.

## 📚 Documentation Directory

To make this repository easy to navigate and reuse, the documentation has been distributed into focused manuals:

*   🚀 **[Setup Guide](docs/SETUP_GUIDE.md):** The comprehensive, step-by-step manual for provisioning the AWS infrastructure and bootstrapping the GitOps engine from scratch.
*   🧠 **[Architecture Deep Dive](docs/ARCHITECTURE.md):** An in-depth exploration of the system design, including OIDC trust policies, ApplicationSet configurations, and networking boundaries.
*   🧬 **[Reusability Guide (Forking)](docs/REUSABILITY_GUIDE.md):** A checklist of exactly which hardcoded values (AWS IDs, S3 buckets) must be changed if you intend to clone this template for a new project.
*   🛠️ **[Troubleshooting Runbook](docs/TROUBLESHOOTING.md):** Operational guides for resolving common platform failures (e.g., Terraform deadlocks, Argo CD OutOfSync errors).

## 🚀 Quick Start
If you are already familiar with the architecture, you can bootstrap the environment using the core commands below. **For a full explanation of these commands, please read the [Setup Guide](docs/SETUP_GUIDE.md).**

```bash
# 1. Provision Infrastructure
cd terraform-eks/remote-backend && terraform init && terraform apply -auto-approve
cd ../ && terraform init && terraform apply -auto-approve

# 2. Authenticate CLI
aws eks update-kubeconfig --region us-east-1 --name my-eks-cluster

# 3. Bootstrap GitOps Control Plane
helm upgrade --install platform-control-plane ./gitops-control-plane -n argocd --create-namespace --wait

# 4. Initialize Automated ECR Authentication
kubectl create job --from=cronjob/ecr-token-refresh ecr-token-refresh-manual -n argocd
```

---
<div align="center">
  <b>Maintained by Parth Singh Kushwaha</b>
</div>
