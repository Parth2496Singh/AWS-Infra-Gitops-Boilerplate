# 💻 Developer Guide: Application Onboarding & Helm Blueprint

This guide explains how developers can leverage the **Universal DRY Helm Chart** to instantly deploy and scale their applications without writing raw Kubernetes YAML. The definitive reference template can be found in `apps/example-microservice/values.yaml`.

> [!TIP]
> Because this template is highly advanced, a single `values.yaml` file can completely transform the underlying Kubernetes architecture, allowing you to deploy Deployments, StatefulSets, DaemonSets, ConfigMaps, Secrets, and ServiceMonitors effortlessly.

---

## 🔐 1. Updating the Universal Blueprint & Authentication

When the Platform Engineering team updates the master Universal Helm Chart (e.g., bumping it from `v1.0.4` to `v1.0.5`), all microservices must pull the new version to inherit the updates. Because the blueprint is stored securely in AWS ECR, your local machine must authenticate before generating the lock files.

### Step 1: Authenticate Local Helm Client
Run this command to fetch a 12-hour AWS token and log your local Helm client into the registry. You only need to do this once every 12 hours.
```bash
aws ecr get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

### Step 2: Generate the Lock Files
Whenever you change the `version: x.x.x` in your application's `Chart.yaml`, you must run the update command to physically download the blueprint and generate the `Chart.lock` file.
```bash
cd apps/<your-app-name>
helm dependency update
```
> [!NOTE]
> In large enterprise environments with 100+ microservices, you do not run this manually. You should utilize a bot like **Renovate** or **Dependabot**, which will automatically open Pull Requests, authenticate with ECR via CI/CD secrets, and run `helm dependency update` across all 100 repositories simultaneously.

### Step 3: Upgrading the GitOps Control Plane (Platform Admins)
If you make changes to the master `gitops-control-plane/values.yaml` (such as updating Image Updater rules or Argo CD settings), you must apply them via Helm. 

> [!WARNING]
> Because Kubernetes Server-Side Apply (SSA) restricts Helm from overwriting the ECR token injected dynamically by the CronJob, you must explicitly delete the secret before upgrading!

```bash
# 1. Delete the dynamic secret to prevent SSA conflicts
kubectl delete secret ecr-registry-secret -n argocd

# 2. Upgrade the control plane
helm upgrade platform-control-plane ./gitops-control-plane -n argocd

# 3. Manually trigger the CronJob to refill the token instantly
kubectl create job --from=cronjob/ecr-token-refresh manual-refresh-$(date +%s) -n argocd
```

---

## 🚀 2. How to Add a New Microservice

Adding a new application to the cluster is completely automated via GitOps. We use the **Umbrella Chart Pattern** to dynamically import your infrastructure blueprint from an AWS ECR OCI registry.

1. **Create a new folder** inside the `apps/` directory with your application's name (e.g., `apps/payment-service/`).
2. **Create a `Chart.yaml`** to import the universal blueprint:
   ```yaml
   apiVersion: v2
   name: payment-service
   version: 1.0.0
   dependencies:
     - name: common-microservice
       version: 1.0.1  # The version of the universal blueprint in ECR
       repository: oci://<YOUR_AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/universal-helm-chart
   ```
3. **Create your `values.yaml`** to configure your app. (Note: everything must be indented under `common-microservice:`):
   ```yaml
   common-microservice:
     replicaCount: 2
     image:
       repository: "..."
       tag: "v1.0.0"
   ```
4. **Generate the Lockfile (CRITICAL):** Argo CD requires a lockfile to ensure deterministic GitOps state. Run this locally:
   ```bash
   aws ecr get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
   helm dependency update apps/payment-service/
   ```
5. **Commit and push** the `Chart.yaml`, `values.yaml`, and the generated `Chart.lock` to the `main` branch. 
   *(Argo CD will automatically detect the new folder, download the OCI blueprint, and deploy it).*

---

## 🔗 3. Service Discovery (Cross-Pod Communication)
When microservices talk to each other (e.g., an NGINX frontend proxying to a Django backend), you must use the exact Kubernetes Service name. 

> [!CAUTION]
> Because we use the `appPrefix` in Argo CD to group your applications, **your Service names will be prefixed with your Project Name.**

**Example Scenario:**
*   Project Name: `lost-found`
*   Backend Folder: `apps/backend/`
*   **Resulting Service Name:** `lost-found-backend`

If you are configuring `nginx.conf` in your frontend, your `proxy_pass` must match the prefixed name exactly:
```nginx
# WRONG (Will crash):
# proxy_pass http://backend:8080;

# CORRECT:
proxy_pass http://lost-found-backend:8080;
```

---

## ⚙️ 4. Configuring the Universal Template (`values.yaml`)

The Universal Helm Chart acts as a machine. Depending on what you toggle in your `values.yaml`, it will generate different Kubernetes resources. Below is a comprehensive guide to all advanced configurations.

### 4.1 Changing the Workload Type
By default, your app is deployed as a Kubernetes `Deployment`. If your application requires stateful persistent storage or needs to run exactly one Pod on every Node, you can instantly change the core architecture:

```yaml
common-microservice:
  # Options: "Deployment", "StatefulSet", "DaemonSet"
  workloadType: "StatefulSet"
```

### 4.2 Migrating Local `.env` Files to Kubernetes
In local development (Docker Compose), you rely on a `.env` file to pass environment variables to your application. In Kubernetes, you cannot mount a `.env` file directly. Instead, Kubernetes uses **ConfigMaps** (for non-sensitive data) and **Secrets** (for sensitive passwords/tokens).

Our Universal Helm Chart makes this migration effortless. You simply copy-paste the values from your `.env` file directly into your `values.yaml` using the `envConfig` and `secrets` blocks. The chart will dynamically generate the Kubernetes objects and inject them into your Pod as standard environment variables.

#### Non-Sensitive Variables (ConfigMap)
Do **not** write raw ConfigMap YAML. Define them here:
```yaml
common-microservice:
  envConfig:
    DJANGO_DEBUG: "True"
    NODE_ENV: "production"
    BACKEND_INTERNAL_URL: "http://backend:8000"
```

#### Sensitive Variables (Secrets)
Similarly, you can dynamically generate and mount Kubernetes Secrets:
> [!WARNING]
> In a true production environment, consider using External Secrets Operator (ESO) instead of committing plaintext secrets to Git!
```yaml
common-microservice:
  secrets:
    DATABASE_URL: "postgres://user:password@aws-0-us-east-1.pooler.supabase.com:6543/postgres"
    GITHUB_PAT: "your_github_personal_access_token_here"
    DJANGO_SECRET_KEY: "velzion-insecure-key"
```

### 4.3 Enabling Prometheus Metrics (ServiceMonitor)
If your application exposes a `/metrics` endpoint, you can automatically generate a Prometheus `ServiceMonitor` to tell the Prometheus Operator to start scraping it. No `ServiceMonitor` YAML required!

```yaml
common-microservice:
  metrics:
    enabled: true       # Turns on the ServiceMonitor generation
    port: "http"        # Must match the named port in the Service
    path: "/metrics"    # The URL path where metrics are exposed
    interval: "30s"     # How often Prometheus should scrape
```

### 4.4 Injecting Sidecars (`extraContainers`)
If your application requires a sidecar (like a Prometheus exporter, logging agent, or Cloud SQL Proxy), you can seamlessly inject raw container YAML into the same Pod without modifying the underlying blueprint:

```yaml
common-microservice:
  extraContainers:
    - name: nginx-exporter
      image: nginx/nginx-prometheus-exporter:1.1.0
      args:
        - -nginx.scrape-uri=http://127.0.0.1:80/nginx_status
      ports:
        - containerPort: 9113

  # IMPORTANT: You must also expose this port on the Service!
  extraPorts:
    - name: metrics
      port: 9113
      targetPort: 9113
      protocol: TCP

  metrics:
    enabled: true
    port: metrics    # Scrape the newly exposed metrics port!
```

### 4.5 The Escape Hatch (Raw Kubernetes Manifests)
If your microservice requires a highly specific Kubernetes resource that the Universal Chart doesn't support (e.g., a `NetworkPolicy`, `CronJob`, or a custom `RoleBinding`), use the `extraManifests` escape hatch.

The template will read this list and render it exactly as raw YAML:

```yaml
common-microservice:
  extraManifests:
    - apiVersion: batch/v1
      kind: CronJob
      metadata:
        name: my-app-cleanup-job
      spec:
        schedule: "0 2 * * *"
        jobTemplate:
          spec:
            template:
              spec:
                containers:
                  - name: cleaner
                    image: busybox
                    args: ["echo", "cleaning up!"]
                restartPolicy: OnFailure
```

---

## 🌍 5. Configuring the Global GitOps Engine (`gitops-control-plane`)

While the `apps/` directory controls individual microservices, the **`gitops-control-plane/values.yaml`** file controls the master Argo CD deployment engine itself. 

If you are setting up this boilerplate for a new project, you **must** edit this file to ensure Argo CD knows where to look for your code:

*   **`argocd.repoUrl`**: Change this to the Git URL of your repository. If you don't, Argo CD will try to deploy code from the original Boilerplate repo!
*   **`argocd.appPrefix`**: Prepended to all your apps (e.g., if prefix is "acme", the backend app becomes "acme-backend").
*   **`notifications.email`**: Update the `sender`, `receiver`, and `host` to point to your actual team's email addresses so you get alerted when deployments succeed or fail.
*   **`registry.ecrBaseUrl`**: Update this with your 12-digit AWS Account ID and region so the Image Updater knows where to look for new Docker tags.

---

## 🏆 6. Best Practices for Developers
*   **The Blueprint is External:** The universal blueprint lives in its own repository: **[universal-helm-chart](https://github.com/Parth2496Singh/universal-helm-chart)**. If you need a new global Kubernetes resource (like a `CronJob` template), you must contribute to that repository and bump the `version` tag.
*   **Keep it DRY**: If you find yourself using `extraManifests` to deploy the exact same resource across 15 different microservices, it is time to ask the Platform Engineering team to build it natively into the `universal-helm-chart`.
