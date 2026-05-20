output "cluster_name" {
  description = "Nombre del cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint del API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Versión de Kubernetes"
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "ID de la VPC"
  value       = module.vpc.vpc_id
}

output "configure_kubectl" {
  description = "Comando para configurar kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "fargate_profiles" {
  description = "Fargate profiles creados (namespaces habilitados)"
  value       = keys(module.eks.fargate_profiles)
}

output "next_step" {
  description = "Siguiente paso"
  value       = "Cluster listo! Continua con etapa-02-ingress-controller"
}
