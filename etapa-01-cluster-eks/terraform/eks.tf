###############################################################################
# EKS Cluster con Fargate Profiles
###############################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  # Add-ons del cluster
  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # =========================================================================
  # FARGATE PROFILES
  # Un profile por cada namespace que usaremos en las etapas siguientes
  # =========================================================================

  fargate_profiles = {
    # Sistema (CoreDNS, kube-proxy)
    system = {
      name = "system"
      selectors = [
        { namespace = "kube-system" }
      ]
    }

    # Etapa 2: Ingress Controller
    ingress = {
      name = "ingress"
      selectors = [
        { namespace = "ingress-nginx" },
        { namespace = "cert-manager" }
      ]
    }

    # Etapa 3: Monitoreo
    monitoring = {
      name = "monitoring"
      selectors = [
        { namespace = "monitoring" }
      ]
    }

    # Etapa 4: GitOps
    argocd = {
      name = "argocd"
      selectors = [
        { namespace = "argocd" }
      ]
    }

    # Etapa 5: Datadog
    datadog = {
      name = "datadog"
      selectors = [
        { namespace = "datadog" }
      ]
    }

    # Aplicaciones de usuario (para pruebas)
    apps = {
      name = "apps"
      selectors = [
        { namespace = "apps" }
      ]
    }
  }

  tags = {
    Environment = var.environment
  }
}
