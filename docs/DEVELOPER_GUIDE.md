# 💻 Developer Guide: Application Onboarding & Helm Blueprint

This guide explains how developers can leverage the **Universal DRY Helm Chart** located in `charts/common-microservices` to instantly deploy and scale their applications without writing raw Kubernetes YAML.

Because this template is highly advanced, a single `values.yaml` file can completely transform the underlying Kubernetes architecture, allowing you to deploy Deployments, StatefulSets, DaemonSets, ConfigMaps, Secrets, and ServiceMonitors effortlessly.

---

## 1. How to Add a New Microservice

Adding a new application to the cluster is completely automated via GitOps (Argo CD).

1. **Create a new directory** under `apps/` with your application name (e.g., `apps/my-new-app/`).
2. **Create a `values.yaml`** inside that directory.
3. **Commit and push** to the `main` branch. 
   *(Argo CD will automatically detect the new folder via its ApplicationSet and instantly deploy it using the universal blueprint).*

---

## 2. Configuring the Universal Template (`values.yaml`)

The Universal Helm Chart acts as a machine. Depending on what you toggle in your `values.yaml`, it will generate different Kubernetes resources. Below is a comprehensive guide to all advanced configurations.

### 2.1 Changing the Workload Type
By default, your app is deployed as a Kubernetes `Deployment`. If your application requires stateful persistent storage or needs to run exactly one Pod on every Node, you can instantly change the core architecture:

```yaml
# Options: "Deployment", "StatefulSet", "DaemonSet"
workloadType: "StatefulSet"
```

### 2.2 Injecting Environment Variables (ConfigMaps)
Do **not** write raw ConfigMap YAML. The universal chart will dynamically generate a ConfigMap and mount it directly into your Pod's environment via `envFrom` if you define the `envConfig` dictionary:

```yaml
envConfig:
  DATABASE_URL: "postgres://db.internal:5432"
  LOG_LEVEL: "info"
  CACHE_ENABLED: "true"
```

### 2.3 Injecting Secure Secrets
Similarly, you can dynamically generate and mount Kubernetes Secrets.
*(Note: In a true production environment, consider using External Secrets Operator instead of committing plaintext secrets).*

```yaml
secrets:
  API_KEY: "my-super-secret-key"
  DB_PASSWORD: "secure-password-123"
```

### 2.4 Enabling Prometheus Metrics (ServiceMonitor)
If your application exposes a `/metrics` endpoint, you can automatically generate a Prometheus `ServiceMonitor` to tell the Prometheus Operator to start scraping it. No `ServiceMonitor` YAML required!

```yaml
metrics:
  enabled: true       # Turns on the ServiceMonitor generation
  port: "http"        # Must match the named port in the Service
  path: "/metrics"    # The URL path where metrics are exposed
  interval: "30s"     # How often Prometheus should scrape
```

### 2.5 The Escape Hatch (Raw Kubernetes Manifests)
If your microservice requires a highly specific Kubernetes resource that the Universal Chart doesn't support (e.g., a `NetworkPolicy`, `CronJob`, or a custom `RoleBinding`), use the `extraManifests` escape hatch.

The template will read this list and render it exactly as raw YAML:

```yaml
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

## 3. Best Practices for Developers
*   **Never modify `charts/common-microservices`** unless the change applies globally to *every single microservice*.
*   **Keep it DRY**: If you find yourself using `extraManifests` to deploy a `CronJob` across 15 different microservices, it is time to ask the Platform Engineering team to build a native `cronjob.yaml` template into the Universal Chart.
