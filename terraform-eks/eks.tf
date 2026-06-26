## Architecture
# This module provisions the control plane and data plane for the EKS cluster.
# It sits at the foundation of the platform stack. All GitOps workloads (Argo CD)
# and network ingress layers (ALB Controller) depend on the output of this module.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # Cluster configuration
  name                    = local.name
  kubernetes_version      = "1.30" # Note: EKS 1.35 does not exist yet. 1.30 is stable.
  endpoint_public_access  = true
  endpoint_private_access = true

  # Networking
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets # Because control plane is aws managed

  # Grant the cluster creator admin permissions via access_entries
  enable_cluster_creator_admin_permissions = true

  # enable_cluster_creator_admin_permissions = true

  ## Reliability
  # The AWS Load Balancer Controller creates physical NLBs for our NGINX Ingress.
  # If the NLB health checks cannot reach the nodes on the NGINX NodePort (10254),
  # the NLB will mark the entire cluster as unhealthy and drop all external traffic.
  # This rule ensures the VPC CIDR can always reach the ingress controllers.
  # Allow AWS Load Balancer Health Checks to reach Nginx Ingress
  node_security_group_additional_rules = {
    ingress_nginx_health = {
      description = "Allow AWS NLB Health Checks to Ingress Nginx"
      protocol    = "tcp"
      from_port   = 10254
      to_port     = 10254
      type        = "ingress"
      cidr_blocks = [local.vpc_cidr]
    }
  }

  # EKS Add-ons
  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true # Deploy before node groups to avoid networking issues
    }
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true # Enables pod-level IAM via Pod Identity
    }
  }

  # EKS Add-ons

  ## Maintainability
  # These node groups run the actual application workloads.
  # We default to SPOT instances to reduce non-production costs.
  # IMPORTANT: Do not set max_size lower than 3, as Karpenter or the Cluster Autoscaler
  # needs headroom to spin up new nodes during rolling upgrades before cordoning old ones.
  # Managed Node Groups
  eks_managed_node_groups = {
    my-project-node-groups = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["c7i-flex.large"] # "c7i-flex.large" might not be available in all AZs/Accounts, t3.medium is safer
      capacity_type  = "SPOT"

      min_size     = 2
      max_size     = 3
      desired_size = 2

      tags = {
        ExtraTag = "my-project-cluster"
      }
    }
  }

  tags = {
    Environment = local.env
    Terraform   = "true"
  }
}