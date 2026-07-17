# 🛠️ Operational Troubleshooting Guide

Welcome to the definitive runbook for diagnosing and resolving platform failures. This guide categorizes issues by stack layer to help you quickly identify the root cause.

> [!TIP]
> **Before diving in:** Always check the logs first! Kubernetes failures are usually very explicitly stated in the pod or controller logs.

---

## 🏗️ 1. Terraform & AWS Infrastructure

### 🚨 Issue: `DependencyViolation` on VPC Deletion
*   **Symptoms:** `terraform destroy` loops indefinitely, eventually timing out with: `api error DependencyViolation: Network vpc-... has some mapped public address(es)`.
*   **Root Cause:** The AWS Load Balancer Controller (running inside Kubernetes) dynamically provisioned physical AWS Application Load Balancers (ALBs) or Network Load Balancers (NLBs). Because Terraform did not create them, it does not know to delete them. The VPC cannot be destroyed while these Load Balancers exist.
*   **Debugging Commands:**
    *   `aws elbv2 describe-load-balancers --region us-east-1`
*   **Resolution:** 
    1. Manually delete the Kubernetes resources that triggered the LoadBalancer creation: `kubectl delete ingress --all -A` and `kubectl delete svc --all -A`.
    2. Wait exactly 2 minutes for AWS to physically detach the Elastic Network Interfaces (ENIs).
    3. Re-run `terraform destroy`.

> [!WARNING]
> **Preventative Measure:** Always purge Kubernetes ingress objects before attempting to destroy an EKS cluster.

### 🚨 Issue: Kubernetes Service stuck in `Terminating`
*   **Symptoms:** Running `kubectl delete svc ingress-nginx-controller -n ingress-nginx` hangs indefinitely. Hitting `Ctrl+C` exits, but the service remains in a `Terminating` state.
*   **Root Cause:** Kubernetes Services of type `LoadBalancer` have a "Finalizer" attached. This tells Kubernetes not to delete the object until it successfully talks to the AWS API to delete the physical AWS Load Balancer. If AWS is unresponsive, or the physical Load Balancer was already deleted manually/via Terraform, Kubernetes waits forever.
*   **Resolution:** You must manually patch the Kubernetes Service to strip the finalizer, forcing Kubernetes to let it go:
    ```bash
    kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"metadata":{"finalizers":null}}'
    ```

### 🚨 Issue: Terraform State Lock Error
*   **Symptoms:** `Error: Error acquiring the state lock`
*   **Root Cause:** A previous CI/CD pipeline or local Terraform run crashed unexpectedly before releasing the DynamoDB lock.
*   **Resolution:** Run `terraform force-unlock <LOCK_ID>`. Ensure no other engineers or pipelines are currently applying changes before forcing the unlock.

---

## 🐙 2. Argo CD (GitOps Engine)

### 🚨 Issue: Application Stuck in `OutOfSync`
*   **Symptoms:** The Argo CD dashboard shows a yellow `OutOfSync` status for a microservice.
*   **Root Cause:** The declarative state in Git does not match the live state in the cluster. This is typically caused by someone manually editing a resource via `kubectl edit`, or a Helm template validation error preventing the sync.
*   **Debugging Commands:**
    *   `kubectl describe application <app-name> -n argocd`
*   **Resolution:** If the drift was an unauthorized manual edit, click **Sync** in Argo CD to enforce the Git state (Self-Heal). If it's a validation error, fix the YAML in the repository and push a commit.

### 🚨 Issue: Helm Template `nil pointer evaluating` Error
*   **Symptoms:** Argo CD fails to render the Application, citing a Go template nil pointer error related to annotations or notifications.
*   **Root Cause:** Helm utilizes Go Templating (`{{ .Values }}`). Argo CD Notifications also utilize Go Templating (`{{ .app.metadata.name }}`). If you place an Argo CD variable directly into a Helm chart, Helm attempts to evaluate it locally, fails to find the variable, and crashes.
*   **Resolution:** Wrap all Argo CD variables in Helm's literal escape sequence. E.g., change `{{.app.metadata.name}}` to `{{ "{{.app.metadata.name}}" }}`.

### 🚨 Issue: Helm Upgrade Fails with `invalid ownership metadata`
*   **Symptoms:** Running `helm upgrade --install platform-control-plane` fails with: `ConfigMap "argocd-notifications-cm" ... cannot be imported ... invalid ownership metadata`. 
*   **Root Cause:** A previous installation created resources in the `argocd` namespace. Helm sees those resources exist but aren't labeled as managed by this specific Helm release, so it defensively blocks the installation.
*   **Resolution:** Purge the conflicting release entirely to give Helm a clean slate.
    1. `helm uninstall platform-control-plane -n argocd`
    2. `kubectl delete cm argocd-notifications-cm -n argocd --ignore-not-found`
    3. Re-run your `helm upgrade` command.

### 🚨 Issue: Secret `already exists` during Bootstrapping
*   **Symptoms:** `error: failed to create secret secrets "argocd-notifications-secret" already exists`
*   **Resolution:** If you are just re-running setup commands and the password hasn't changed, you can safely ignore this. If you made a mistake and need to update the secret, you must delete it first: `kubectl delete secret argocd-notifications-secret -n argocd`.

---

## 🤖 3. Argo CD Image Updater & ECR

### 🚨 Issue: New Docker Images Are Not Being Deployed
*   **Symptoms:** A new Docker image is pushed to AWS ECR, but the Kubernetes pods are not updating.
*   **Root Cause:** The Image Updater controller has either lost authentication to AWS ECR, or it lacks permission to push commits to GitHub.
*   **Resolution (GitHub Permission):** Ensure the `github-gitops-creds` secret exists, contains a valid PAT with `repo` permissions, and is labeled with `argocd.argoproj.io/secret-type=repository`.
*   **Resolution (ECR Authentication):** ECR tokens expire every 12 hours. Run `kubectl create job --from=cronjob/ecr-token-refresh manual-refresh -n argocd` to manually force a token refresh, then check the job logs.

### 🚨 Issue: Image Updater "Deadlock" (Tags not updating)
*   **Symptoms:** A new Docker tag is pushed to ECR, but the Image Updater refuses to update the application manifest in GitHub.
*   **Root Cause:** The Image Updater will **never** update an application that is in a `Degraded` or `SyncFailed` state. It intentionally pauses updates to prevent compounding failures.
*   **Resolution:** You must manually fix the crash or invalid YAML by committing a fix to turn the app `Healthy`. Once green, the Image Updater will resume scanning.

### 🚨 Issue: Image Updater `no basic auth credentials`
*   **Symptoms:** Image Updater logs show `Could not get tags from registry... no basic auth credentials`.
*   **Root Cause:** The Image Updater requires an explicit configuration to use the ECR pull secret to query the registry API for new tags.
*   **Resolution:** Ensure `pullSecret: "pullsecret:argocd/ecr-registry-secret"` is properly configured inside the `commonUpdateSettings` block of your `ImageUpdater` CRD.

### 🚨 Issue: CronJob Fails with `NoCredentials` (IRSA Missing)
*   **Symptoms:** The `ecr-token-refresh` job fails, and logs show `aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials.` This results in an empty password being pushed to the Kubernetes secret.
*   **Root Cause:** The `argocd-image-updater-controller` ServiceAccount is missing the IAM Roles for Service Accounts (IRSA) annotation. Without it, the AWS CLI cannot assume the identity required to pull the ECR token.
*   **Resolution:** Annotate the ServiceAccount and restart the pod:
    ```bash
    kubectl annotate serviceaccount argocd-image-updater-controller -n argocd eks.amazonaws.com/role-arn=arn:aws:iam::<YOUR_AWS_ACCOUNT>:role/argocd-image-updater-ecr-role
    kubectl rollout restart deployment argocd-image-updater-controller -n argocd
    ```

---

## ⚡ 4. Monitoring & Networking

### 🚨 Issue: ServiceMonitor `Invalid value: "integer"`
*   **Symptoms:** Kubernetes rejects the Helm sync: `spec.endpoints[0].port in body must be of type string: "integer"`.
*   **Root Cause:** The Prometheus `ServiceMonitor` CRD requires the `port` field to be the **string name** of the port defined in the Kubernetes Service (e.g., `metrics`), not the numeric port value (e.g., `9113`).
*   **Resolution:** Change the `port:` value in your `values.yaml` `metrics` block to exactly match the `name:` of the port defined in your `extraPorts` block.

### 🚨 Issue: NGINX `host not found in upstream`
*   **Symptoms:** The NGINX sidecar crashes on startup with `host not found in upstream "backend"`.
*   **Root Cause:** When NGINX tries to route traffic using `proxy_pass`, it relies on Kubernetes DNS. Argo CD automatically prepends your `appPrefix` (e.g., `my-project`) to all Service names. Thus, the backend service is named `my-project-backend`, not `backend`.
*   **Resolution:** Update your `nginx.conf` to use the fully-prefixed Kubernetes Service name (e.g., `proxy_pass http://my-project-backend:8001;`).

---

## 📦 5. Universal Helm Chart & OCI Dependencies

### 🚨 Issue: `401 Unauthorized` when downloading OCI Helm Charts
*   **Symptoms:** Argo CD returns `helm dependency build failed... 401 Unauthorized` despite the ECR CronJob running successfully.
*   **Root Cause:** Argo CD requires TWO distinct secrets to interact with AWS ECR: a `kubernetes.io/dockerconfigjson` secret for pulling Docker containers, and a `type: Opaque` secret with `argocd.argoproj.io/secret-type: repository` labels for pulling OCI Helm charts.
*   **Resolution:** Ensure your `ecr-auth-job.yaml` CronJob is configured to patch BOTH secrets, delete the old secrets, and run the job manually once.

### 🚨 Issue: Helm Upgrade Fails with `conflict with "curl"`
*   **Symptoms:** Running `helm upgrade` fails with `Apply failed with 1 conflict: conflict with "curl" using v1: .data..dockerconfigjson`.
*   **Root Cause:** This is caused by Kubernetes Server-Side Apply (SSA). Helm creates the initial ECR registry secret, but the `ecr-auth-job` CronJob subsequently uses `curl` to update the token field. Kubernetes records `curl` as the owner of that field, preventing Helm from overwriting it.
*   **Resolution:** You must manually delete the secret, run Helm upgrade to recreate the empty shell, and then manually trigger the CronJob to refill it:
    ```bash
    kubectl delete secret ecr-registry-secret -n argocd
    helm upgrade platform-control-plane ./gitops-control-plane -n argocd
    kubectl create job --from=cronjob/ecr-token-refresh manual-refresh-$(date +%s) -n argocd
    ```

### 🚨 Issue: The "Double URL" Error (`/common-microservice/common-microservice`)
*   **Symptoms:** `could not download oci://.../universal-helm-chart/common-microservice/common-microservice`.
*   **Root Cause:** Helm 3 OCI resolution automatically appends the `name:` of the dependency to the end of the `repository:` string in your `Chart.yaml`. 
*   **Resolution:** Remove the chart name from the end of the `repository:` URL in your application's `Chart.yaml`. It should point only to the registry's base folder.
