variable "cluster_name" {
  description = "Nombre del cluster EKS"
  type        = string
}

variable "profile_name" {
  description = "Nombre del Fargate Profile"
  type        = string
}

variable "namespace" {
  description = "Namespace de Kubernetes que matchea este profile"
  type        = string
}

variable "subnet_ids" {
  description = "IDs de las subnets privadas donde corren los pods"
  type        = list(string)
}

variable "labels" {
  description = "Labels adicionales para el selector (opcional)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags para los recursos"
  type        = map(string)
  default     = {}
}
