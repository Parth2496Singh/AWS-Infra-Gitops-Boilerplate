# 🚀 Setup & Bootstrap Guide

Welcome to the comprehensive manual for provisioning the infrastructure and bootstrapping the GitOps deployment engine from scratch.

> [!CAUTION]
> **Do not skip verification commands.** Kubernetes relies heavily on eventual consistency and asynchronous operations. Moving to the next step before a dependency is ready will cause cascading failures.

---

## 🛠️ 1. Prerequisites

Before executing any commands, you must configure your local environment.

*   **AWS CLI (v2.x):** Must be installed and authenticated via `aws configure`. Ensure the IAM user has `AdministratorAccess` (or equivalent permissions) to create VPCs, IAM Roles, and EKS clusters.
*   **Terraform (v1.5+):** Required to provision the physical AWS resources.
*   **kubectl (v1.28+):** Required to interact with the Kubernetes API.
*   **Helm (v3.x):** Required to deploy the Argo CD control plane.
*   **GitHub PAT:** You need a Personal Access Token with `repo` permissions to allow Argo CD to write commits back to this repository.

---

## 🏗️ 2. Infrastructure Provisioning

### 2.1 Generate Cryptographic Identities (SSH Keys)
**Purpose:** EC2 and EKS nodes require SSH keys for administrative access. Terraform expects these files to exist locally.
**Command:**
```bash
# EKS Keys
ssh-keygen -t ed25519 -f ./terraform-eks/terraform-eks-key -C "aws-eks-deployments" -N ""
cp ./terraform-eks/terraform-eks-key* ./terraform-eks/remote-backend/

# EC2 Keys (Legacy)
ssh-keygen -t ed25519 -f ./terraform-ec2/terraform-ec2-key -C "aws-ec2-deployments" -N ""
cp ./terraform-ec2/terraform-ec2-key* ./terraform-ec2/remote-backend/
```
> [!NOTE]
> This generates modern `ed25519` key pairs without a passphrase. The `.gitignore` prevents these from being committed to source control.

### 2.2 Bootstrap Terraform Remote State
**Purpose:** Terraform must store its state remotely (S3) and use state locking (DynamoDB) to prevent concurrent modifications by CI/CD pipelines.
**Command:**
```bash
cd terraform-eks/remote-backend
terraform init
terraform apply -auto-approve
cd ../..
```
**✅ Verification:** Log into the AWS Console. Verify the S3 bucket and DynamoDB table were created in `us-east-1`.

### 2.3 Configure Keyless CI/CD Authentication (OIDC)
**Purpose:** Allows GitHub Actions to assume an AWS IAM role dynamically without storing static, long-lived AWS Access Keys.
**Command:**
```bash
aws cloudformation deploy \
  --template-file terraform-eks/aws-oidc-github-role.yaml \
  --stack-name github-oidc-terraform-role \
  --parameter-overrides GitHubOrg=<YOUR_ORG> GitHubRepo=<YOUR_REPO> CreateOIDCProvider=true \
  --capabilities CAPABILITY_NAMED_IAM
```
> [!IMPORTANT]
> **Next Action (GitHub Setup):** 
> 1. Get the generated Role ARN by running: `aws cloudformation describe-stacks --stack-name github-oidc-terraform-role --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" --output text`
> 2. Go to your GitHub Repository -> **Settings** -> **Secrets and variables** -> **Actions**.
> 3. Under **Secrets**, click *New repository secret*, name it `AWS_ROLE_ARN`, and paste the ARN.

### 2.4 Provision the EKS Cluster
**Purpose:** Deploys the VPC, Subnets, Internet Gateway, EKS Control Plane, and Managed Node Groups.
**Command:**
```bash
cd terraform-eks/
terraform init
terraform apply -auto-approve
```
> [!TIP]
> This process takes approximately 15 minutes. It provisions the physical compute resources and installs core addons like the AWS Load Balancer Controller.

---

## ☸️ 3. Kubernetes & GitOps Bootstrapping

> [!WARNING]
> **Re-Deployment Warning:** If you are re-running these commands on an existing cluster, you may encounter `Already Exists` errors or `invalid ownership metadata`. To clear the slate, run:
> 1. `kubectl delete secret github-gitops-creds argocd-notifications-secret -n argocd --ignore-not-found`
> 2. `helm uninstall platform-control-plane -n argocd --ignore-not-found`

### 3.1 Authenticate kubectl
**Purpose:** Configures your local CLI to communicate with the new EKS cluster.
**Command:**
```bash
aws eks update-kubeconfig --region us-east-1 --name my-eks-cluster
```
**✅ Verification:** Run `kubectl get nodes`. You should see the instances reporting `Ready`.

### 3.2 Install Base Custom Resource Definitions (CRDs)
**Purpose:** The GitOps Helm chart relies on custom Kubernetes resources (ImageUpdater, Notifications). Helm cannot reliably install CRDs simultaneously with the objects that implement them.
**Command:**
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/master/config/install.yaml
kubectl create rolebinding argocd-image-updater-app-reader --clusterrole=argocd-server --serviceaccount=argocd:argocd-image-updater-controller --namespace=argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
```
**✅ Verification:** Run `kubectl get crds | grep argoproj`.

### 3.3 Inject Operational Secrets
**Purpose:** Securely inject credentials into the cluster memory, ensuring they are never hardcoded in Git.
**Command:**
```bash
# GitHub PAT for automated commits
kubectl create secret generic github-gitops-creds -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/<YOUR_ORG>/<YOUR_REPO>.git \
  --from-literal=username=<USER> \
  --from-literal=password="<PAT>"
kubectl label secret github-gitops-creds -n argocd argocd.argoproj.io/secret-type=repository

# SMTP for automated alerts
kubectl create secret generic argocd-notifications-secret -n argocd \
  --from-literal=email-username=<YOUR_EMAIL>@example.com \
  --from-literal=email-password=<APP_PASSWORD>
```
> [!CAUTION]
> Forgetting to apply the `argocd.argoproj.io/secret-type=repository` label will cause Argo CD to silently ignore the GitHub credentials.

### 3.4 Deploy the GitOps Control Plane
**Purpose:** Installs Argo CD, ApplicationSets, and the global platform configuration using Helm.
**Command:**
```bash
kubectl delete configmap argocd-notifications-cm -n argocd --ignore-not-found
helm upgrade --install platform-control-plane ./gitops-control-plane -n argocd --create-namespace --wait
```
**✅ Verification:** Run `kubectl get pods -n argocd -w`. Wait until all pods report `Running`.

### 3.5 Initialize Native ECR Authentication (IRSA)
**Purpose:** AWS ECR passwords expire every 12 hours. The platform uses a CronJob bound to an IAM Role (IRSA) to rotate them. We must link the Kubernetes ServiceAccount to the AWS IAM Role, and then force the first run.
**Command:**
```bash
# 1. Bind the IAM Role to the ServiceAccount (Replace the AWS Account ID!)
kubectl annotate serviceaccount argocd-image-updater-controller -n argocd eks.amazonaws.com/role-arn=arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/argocd-image-updater-ecr-role

# 2. Restart the Image Updater so it picks up the AWS Identity
kubectl rollout restart deployment argocd-image-updater-controller -n argocd

# 3. Trigger the CronJob manually
kubectl create job --from=cronjob/ecr-token-refresh ecr-token-refresh-manual-$(date +%s) -n argocd
```
**✅ Verification:** Run `kubectl logs job/ecr-token-refresh-manual -n argocd` (you may need to add the timestamp suffix). Ensure the output reads `ECR tokens successfully updated for both Docker and Helm!`.

---

## 📊 4. Access & Dashboards

### Argo CD Dashboard
**Purpose:** Provides a visual representation of the GitOps synchronization state.
**Command:** `kubectl port-forward svc/argocd-server -n argocd 8080:443`
**Credentials:** 
- User: `admin`
- Pass: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`

### Grafana (Monitoring)
**Purpose:** Visualizes cluster metrics if `kube-prometheus-stack` was enabled in `addons.tf`.
**Command:** `kubectl get ingress -n monitoring` (to retrieve the AWS ALB URL).
**Credentials:**
- User: `admin`
- Pass: `prom-operator`

---

## 💥 5. Teardown & Cleanup

> [!CAUTION]
> **AVOID VPC DEPENDENCY ERRORS:** The AWS Load Balancer Controller dynamically creates physical AWS Application Load Balancers (ALBs) and Security Groups. Because Terraform did not create them, Terraform cannot delete them. If you run `terraform destroy` while these exist, AWS will block the VPC deletion, requiring painful manual cleanup.

Follow this exact sequence to safely destroy the cluster:

**Phase 1: Graceful Kubernetes Cleanup**
1. `kubectl delete ingress --all -A`
2. `kubectl delete svc ingress-nginx-controller -n ingress-nginx --ignore-not-found`
3. Wait **3 to 10 minutes** for the AWS Load Balancer Controller to physically detach the Elastic Network Interfaces (ENIs) from your Subnets. *(AWS is notoriously slow at deprovisioning ALBs).*

**Phase 2: Verification (DO NOT SKIP)**
> [!WARNING]
> This step is NOT a bluff! If you run `terraform destroy` while ALBs still exist, Terraform will kill your EKS cluster before AWS finishes deleting the ALB, permanently trapping orphaned Security Groups in your VPC.

Before running Terraform, ensure the AWS Load Balancer Controller has successfully finished deleting the ALBs:
```bash
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[*].[LoadBalancerName]'
```
*   ✅ If this returns an empty array `[]`, you are safe to proceed. 
*   ❌ If it still lists your ALBs, **DO NOT proceed**. Wait a few more minutes and run the command again.

**Phase 3: Terraform Destroy**
Once you have verified the AWS resources are gone, you are safe to destroy the infrastructure. 

> [!TIP]
> **⏱️ Estimated Time to Destroy:** ~10 to 15 minutes.

```bash
cd terraform-eks/
terraform destroy -auto-approve
```
