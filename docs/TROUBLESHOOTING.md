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

---

## 5. Universal Helm Chart & OCI Dependencies

### Issue: Argo CD `PermissionDenied` for OCI Helm Repositories
*   **Symptoms:** Argo CD fails to sync with error: `helm repos <registry> are not permitted in project <projectName>`.
*   **Root Cause:** By default, the Argo CD `AppProject` acts as a strict firewall and only allows pulling code from your specific GitHub repository. It actively blocks outgoing requests to AWS ECR to pull your Universal Helm Chart dependencies.
*   **Resolution:** Open `gitops-control-plane/templates/AppProject.yaml` and add `- "*"` to the `sourceRepos` list, then upgrade the control plane via Helm.

### Issue: `401 Unauthorized` when downloading OCI Helm Charts
*   **Symptoms:** Argo CD returns `helm dependency build failed... 401 Unauthorized` despite the ECR CronJob running successfully.
*   **Root Cause:** Argo CD requires TWO distinct secrets to interact with AWS ECR. It needs a `kubernetes.io/dockerconfigjson` secret for pulling Docker containers, and a `type: Opaque` secret with `argocd.argoproj.io/secret-type: repository` labels for pulling OCI Helm charts. The CronJob was only creating the Docker secret.
*   **Resolution:** Ensure your `ecr-auth-job.yaml` CronJob is configured to patch BOTH secrets, delete the old secrets, and run the job manually once.

### Issue: The "Double URL" Error (`/common-microservice/common-microservice`)
*   **Symptoms:** `could not download oci://.../universal-helm-chart/common-microservice/common-microservice`.
*   **Root Cause:** Helm 3 OCI resolution automatically appends the `name:` of the dependency to the end of the `repository:` string in your `Chart.yaml`. If you manually added the chart name to the end of your repository URL, Helm appends it a second time, breaking the path.
*   **Resolution:** Remove the chart name from the end of the `repository:` URL in your application's `Chart.yaml`. It should point only to the registry's base folder (`oci://.../universal-helm-chart`).

---

## 6. Monitoring & Networking

### Issue: ServiceMonitor `Invalid value: "integer"`
*   **Symptoms:** Kubernetes rejects the Helm sync: `spec.endpoints[0].port in body must be of type string: "integer"`.
*   **Root Cause:** The Prometheus `ServiceMonitor` CRD requires the `port` field to be the **string name** of the port defined in the Kubernetes Service (e.g., `metrics`), not the numeric port value (e.g., `9113`). Even if wrapped in quotes, Helm templating evaluates `"9113"` as a pure integer, which fails OpenAPI validation.
*   **Resolution:** Change the `port:` value in your `values.yaml` `metrics` block to exactly match the `name:` of the port defined in your `extraPorts` block (e.g., `port: metrics`).

### Issue: NGINX `host not found in upstream`
*   **Symptoms:** The NGINX sidecar or frontend container crashes on startup with `host not found in upstream "backend"`.
*   **Root Cause:** When NGINX tries to route traffic to another microservice using `proxy_pass`, it relies on Kubernetes DNS. Argo CD automatically prepends your `appPrefix` (e.g., `my-project`) to all Service names to group them together. Thus, the backend service is named `my-project-backend`, not `backend`.
*   **Resolution:** Update your `nginx.conf` to use the fully-prefixed Kubernetes Service name (e.g., `proxy_pass http://my-project-backend:8001;`), and ensure you are targeting the correct internal container port, not necessarily port 80.

### Issue: Image Updater "Deadlock" (Tags not updating)
*   **Symptoms:** A new Docker tag is pushed to ECR, but the Image Updater refuses to update the application manifest in GitHub.
*   **Root Cause:** The Image Updater will **never** update an application that is in a `Degraded` or `SyncFailed` state (such as a Pod in a `CrashLoopBackOff` due to an NGINX typo, or a rejected `ServiceMonitor` YAML). It intentionally pauses updates to prevent compounding failures.
*   **Resolution:** You must manually fix the crash or invalid YAML by committing a fix (and manually updating the image tag if needed) to turn the app `Healthy`. Once green, the Image Updater will resume its automated scanning.
