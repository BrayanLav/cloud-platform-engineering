###############################################################################
# Módulo: Fargate Profile
###############################################################################
# Módulo reutilizable para crear Fargate Profiles en EKS.
# En vez de repetir el mismo bloque por cada namespace, usas este módulo.
#
# Uso:
#   module "profile_apps" {
#     source       = "../../modules/fargate-profile"
#     cluster_name = module.eks.cluster_name
#     profile_name = "apps"
#     namespace    = "apps"
#     subnet_ids   = module.vpc.private_subnets
#     tags         = var.tags
#   }
###############################################################################

resource "aws_eks_fargate_profile" "this" {
  cluster_name           = var.cluster_name
  fargate_profile_name   = var.profile_name
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.subnet_ids

  selector {
    namespace = var.namespace
    labels    = var.labels
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${var.profile_name}"
  })
}

###############################################################################
# IAM Role para Fargate Pod Execution
###############################################################################
resource "aws_iam_role" "fargate" {
  name = "${var.cluster_name}-fargate-${var.profile_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}
