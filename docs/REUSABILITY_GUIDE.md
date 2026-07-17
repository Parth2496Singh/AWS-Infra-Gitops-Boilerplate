# Platform Reusability Guide

This repository is designed as a reusable GitOps boilerplate template. If you are forking this repository to use as the foundation for an entirely new project, organization, or environment, you **must** update the placeholder variables to ensure architectural isolation.

Failing to update these values will result in state collisions, permission denials, or your GitOps engine attempting to pull from the original repository.

---

## 1. The Automated Bootstrap Script

To make platform creation frictionless, we use `bootstrap-template.sh` to hydrate the repository with your specific AWS and GitHub credentials.

**What this script modifies under the hood:**
1. **GitHub Org/Repo:** Scans `gitops-control-plane/values.yaml` and `.github/workflows` to ensure Argo CD and GitHub Actions point to your new fork, not the original template.
2. **AWS Account ID & Region:** Updates IAM OIDC trust policies and ECR image registry paths across Terraform and Helm.
3. **Terraform State Isolation:** Generates globally unique names for your `terraform-eks` and `terraform-ec2` remote backend S3 buckets and DynamoDB lock tables to prevent state corruption.
4. **EKS Cluster Naming:** Injects your custom cluster name into `locals.tf` to avoid VPC/EKS name collisions if deploying multiple clusters in the same AWS account.

**Mandatory Post-Script Checklist:**
Even after running the script, you must manually complete these steps:
- [ ] Delete all `.terraform/` directories and `.terraform.lock.hcl` files locally if you have previously run `terraform init`.
- [ ] Generate fresh SSH keys (`terraform-eks-key`) in the AWS console.
- [ ] Verify your ECR repository prefix in `gitops-control-plane/values.yaml`. The `repositoryPrefix` value MUST exactly match your Docker repository names in AWS ECR (e.g. `lost-found`), otherwise Argo CD Image Updater will silently ignore new image tags due to strict string matching.
- [ ] Uncomment the `push` and `pull_request` triggers in `.github/workflows/terraform-cicd.yaml` to activate your pipeline.

---

## 2. Managing Multiple Environments (Staging vs Prod)

If you are deploying multiple copies of this platform into the same AWS account (e.g., `staging` and `production`), you cannot use a single repository branch without careful isolation.

### Option A: The Branch Strategy (Simpler)
1. Keep your repository structure.
2. Create a `staging` branch and a `production` branch.
3. Run `bootstrap-template.sh` on the `staging` branch, setting `CLUSTER_NAME="staging-eks"` and unique S3 buckets.
4. Run `bootstrap-template.sh` on the `production` branch, setting `CLUSTER_NAME="prod-eks"` and unique S3 buckets.
5. Point your Argo CD ApplicationSet to track the specific branch for that environment.

### Option B: The Multi-Directory Strategy (Enterprise)
1. Restructure the Terraform folders: `terraform-eks-staging` and `terraform-eks-prod`.
2. Give each folder its own `remote-backend` configuration.
3. In `gitops-control-plane`, create a `values-staging.yaml` and `values-prod.yaml` to deploy different application configurations based on the cluster.

---

## 3. Customizing the GitOps Engine

The `gitops-control-plane` directory is the master configuration for your entire platform. When reusing this template, remember that changes here affect *all* microservices.

*   **Email Notifications:** By default, Argo CD will send emails on sync failures. You must update `notifications.email` in `gitops-control-plane/values.yaml` with your SMTP server and team addresses.
*   **App Prefixing:** If you are deploying multiple projects into the same cluster, use `argocd.appPrefix` to namespace your applications (e.g., `finance-backend` vs `hr-backend`) to avoid Argo CD naming collisions.
