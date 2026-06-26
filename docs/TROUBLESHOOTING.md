# Operational Troubleshooting Guide

This guide serves as the primary runbook for diagnosing and resolving common platform failures. It categorizes issues by the layer of the stack where the failure is observed.

---

## 1. Terraform & AWS Infrastructure

### Issue: `DependencyViolation` on VPC Deletion
*   **Symptoms:** `terraform destroy` loops indefinitely, eventually timing out with: `api error DependencyViolation: Network vpc-... has some mapped public address(es)`.
*   **Root Cause:** The AWS Load Balancer Controller (running inside Kubernetes) dynamically provisioned physical AWS Application Load Balancers (ALBs) or Network Load Balancers (NLBs). Because Terraform did not create them, it does not know to delete them. The VPC cannot be destroyed while these Load Balancers exist.
*   **Debugging Commands:**
    *   `aws elbv2 describe-load-balancers --region us-east-1`
*   **Resolution:** 
    1. Manually delete the Kubernetes resources that triggered the LoadBalancer creation: `kubectl delete ingress --all -A` and `kubectl delete svc --all -A`.
    2. Wait exactly 2 minutes for AWS to physically detach the Elastic Network Interfaces (ENIs).
    3. Re-run `terraform destroy`.
*   **Preventative Measures:** Always purge Kubernetes ingress objects before attempting to destroy an EKS cluster.

### Issue: Kubernetes Service stuck in `Terminating`
*   **Symptoms:** Running `kubectl delete svc ingress-nginx-controller -n ingress-nginx` hangs indefinitely. Hitting `Ctrl+C` exits, but the service remains in a `Terminating` state.
*   **Root Cause:** Kubernetes Services of type `LoadBalancer` have a "Finalizer" attached (`service.kubernetes.io/load-balancer-cleanup`). This tells Kubernetes not to delete the object until it successfully talks to the AWS API to delete the physical AWS Load Balancer. If AWS is unresponsive, or the physical Load Balancer was already deleted manually/via Terraform, Kubernetes waits forever.
*   **Resolution:** You must manually patch the Kubernetes Service to strip the finalizer, forcing Kubernetes to let it go:
    `kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"metadata":{"finalizers":null}}'`

### Issue: Terraform State Lock Error
*   **Symptoms:** `Error: Error acquiring the state lock`
*   **Root Cause:** A previous CI/CD pipeline or local Terraform run crashed unexpectedly before releasing the DynamoDB lock.
*   **Resolution:** Run `terraform force-unlock <LOCK_ID>`. Ensure no other engineers or pipelines are currently applying changes before forcing the unlock.

---

## 2. Argo CD (GitOps Engine)

### Issue: Application Stuck in `OutOfSync`
*   **Symptoms:** The Argo CD dashboard shows a yellow `OutOfSync` status for a microservice.
*   **Root Cause:** The declarative state in Git does not match the live state in the cluster. This is typically caused by someone manually editing a resource via `kubectl edit`, or a Helm template validation error preventing the sync.
*   **Debugging Commands:**
    *   `kubectl describe application <app-name> -n argocd`
*   **Resolution:** If the drift was an unauthorized manual edit, click **Sync** in Argo CD to enforce the Git state (Self-Heal). If it's a validation error, fix the YAML in the repository and push a commit.

### Issue: Helm Template `nil pointer evaluating` Error
*   **Symptoms:** Argo CD fails to render the Application, citing a Go template nil pointer error related to annotations or notifications.
*   **Root Cause:** Helm utilizes Go Templating (`{{ .Values }}`). Argo CD Notifications also utilize Go Templating (`{{ .app.metadata.name }}`). If you place an Argo CD variable directly into a Helm chart, Helm attempts to evaluate it locally, fails to find the variable, and crashes.
*   **Resolution:** Wrap all Argo CD variables in Helm's literal escape sequence. E.g., change `{{.app.metadata.name}}` to `{{ "{{.app.metadata.name}}" }}`.

### Issue: Helm Upgrade Fails with `invalid ownership metadata`
*   **Symptoms:** Running `helm upgrade --install platform-control-plane` fails with: `ConfigMap "argocd-notifications-cm" in namespace "argocd" exists and cannot be imported into the current release: invalid ownership metadata`. Trying to use `--force` results in `cannot use server-side apply and force replace together`.
*   **Root Cause:** A previous installation (either a raw `kubectl apply` from the Argo CD catalog or an aborted older Helm release) created resources in the `argocd` namespace. Helm sees those resources exist but aren't labeled as managed by this specific Helm release, so it defensively blocks the installation.
*   **Resolution:** Purge the conflicting release entirely to give Helm a clean slate. Run:
    1. `helm uninstall platform-control-plane -n argocd`
    2. *Optional (if configmaps linger):* `kubectl delete cm argocd-notifications-cm -n argocd`
    3. Re-run your `helm upgrade --install ...` command.

### Issue: Secret `already exists` during Bootstrapping
*   **Symptoms:** `error: failed to create secret secrets "argocd-notifications-secret" already exists`
*   **Root Cause:** You are running the `kubectl create secret` command on a cluster where the secret was already created by a previous run or pipeline.
*   **Resolution:** If you are just re-running setup commands and the password hasn't changed, you can safely ignore this. If you made a mistake and need to update the secret, you must delete it first: `kubectl delete secret argocd-notifications-secret -n argocd` before recreating it.

---

## 3. Argo CD Image Updater & ECR

### Issue: New Docker Images Are Not Being Deployed
*   **Symptoms:** A new Docker image is pushed to AWS ECR, but the Kubernetes pods are not updating. The `.argocd-source-<app>.yaml` file is not receiving automated commits on GitHub.
*   **Root Cause:** The Image Updater controller has either lost authentication to AWS ECR, or it lacks permission to push commits to GitHub.
*   **Debugging Commands:**
    *   `kubectl logs -l app.kubernetes.io/name=argocd-image-updater-controller -n argocd -f`
*   **Resolution (GitHub Permission):** Ensure the `github-gitops-creds` secret exists, contains a valid PAT with `repo` permissions, and is labeled with `argocd.argoproj.io/secret-type=repository`.
*   **Resolution (ECR Authentication):** ECR tokens expire every 12 hours. The automated CronJob may have failed. Run `kubectl create job --from=cronjob/ecr-token-refresh manual-refresh -n argocd` to manually force a token refresh, then check the job logs.

---

## 4. GitHub Actions (CI/CD)

### Issue: `Not authorized to perform sts:AssumeRoleWithWebIdentity`
*   **Symptoms:** The GitHub Actions pipeline fails immediately at the `aws-actions/configure-aws-credentials` step.
*   **Root Cause:** The OIDC trust policy in AWS does not match the GitHub repository attempting to assume the role.
*   **Resolution:** Verify that the `aws-oidc-github-role.yaml` CloudFormation stack was deployed with the exact `GitHubOrg` and `GitHubRepo` parameters matching your current repository. Verify the `id-token: write` permission is present in the GitHub Actions YAML.
