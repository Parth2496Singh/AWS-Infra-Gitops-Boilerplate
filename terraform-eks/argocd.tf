# Wait for your EKS nodes and networking to stabilize
resource "time_sleep" "wait_for_cluster" {
  create_duration = "30s"
  depends_on      = [module.eks, module.eks_addons_apps]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"

  values = [
    yamlencode({
      server = {
        service   = { type = "ClusterIP" }
        ingress   = { enabled = false }
        extraArgs = ["--insecure"]
      }
      # Tuned down resource limits to save memory on your nodes
      controller = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "256Mi" }
        }
      }
      redis = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "200m", memory = "128Mi" }
        }
      }
    })
  ]

  depends_on = [time_sleep.wait_for_cluster]
}