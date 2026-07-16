module "eks_addons_core" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  ## Reliability
  # We MUST deploy this module entirely first, because it registers a mutating webhook.
  # If we deploy NGINX at the exact same time, NGINX tries to create a Service,
  # the API server calls the webhook, and the deployment fails because ALB isn't ready.
  # Splitting addons into core and apps enforces a strict DAG dependency.
  # ---------------------------------------------------------
  # 1. AWS LOAD BALANCER CONTROLLER (Layer 7 Routing)
  # ---------------------------------------------------------
  # the API server calls the webhook, and it fails because ALB isn't ready.
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    most_recent = true
    namespace   = "kube-system"
    wait        = true # Force Terraform to wait for ALB pods to be 'Ready'
    
    # CRITICAL FIX: The pod is crashing with EC2Metadata 401 error. 
    # Explicitly providing the VPC ID and Region prevents it from relying on IMDSv2.
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      },
      {
        name  = "region"
        value = local.region
      }
    ]
  }

  depends_on = [module.eks]
}

module "eks_addons_apps" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # ---------------------------------------------------------
  # 2. NGINX INGRESS (Layer 4/7 Gateway)
  # ---------------------------------------------------------
  enable_ingress_nginx = true
  ingress_nginx = {
    most_recent = true
    namespace   = "ingress-nginx"

    set = [
      { name = "controller.service.type", value = "LoadBalancer" },
      { name = "controller.resources.requests.cpu", value = "100m" },
      { name = "controller.resources.requests.memory", value = "128Mi" }
    ]

    set_sensitive = [
      { name = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme", value = "internet-facing" },
      { name = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type", value = "nlb" }
    ]
  }

  # ---------------------------------------------------------
  # 3. KUBE-PROMETHEUS-STACK (Monitoring & Observability)
  # ---------------------------------------------------------
  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    most_recent = true
    namespace   = "monitoring"

    values = [
      yamlencode({
        prometheus = {
          prometheusSpec = {
            resources = {
              requests = { cpu = "100m", memory = "256Mi" }
            }
          }
          ingress = {
            enabled          = true
            ingressClassName = "alb"
            annotations = {
              "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
              "alb.ingress.kubernetes.io/target-type" = "ip"
            }
            hosts = [""]
            paths = ["/*"]
          }
        }
        grafana = {
          adminPassword = "prom-operator"
          resources = {
            requests = { cpu = "50m", memory = "128Mi" }
          }
          ingress = {
            enabled          = true
            ingressClassName = "alb"
            annotations = {
              "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
              "alb.ingress.kubernetes.io/target-type" = "ip"
            }
            path = "/"
          }
        }
      })
    ]
  }

  # CRITICAL FIX: Do not deploy these until ALB Controller is 100% running
  depends_on = [module.eks_addons_core]
}

# ---------------------------------------------------------
# 4. IRSA for Argo CD Image Updater
# ---------------------------------------------------------

## Security
# This binds the AWS IAM Role directly to the Kubernetes ServiceAccount via OIDC.
# It adheres to the Principle of Least Privilege by completely avoiding long-lived AWS static keys.
# The `AmazonEC2ContainerRegistryReadOnly` policy allows the Image Updater to fetch tags
# but denies it the ability to push or delete images.
module "image_updater_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "argocd-image-updater-ecr-role"
  attach_vpc_cni_policy = false
  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["argocd:argocd-image-updater-controller"]
    }
  }
}