###############################################################################
# Variables con validación (BUENA PRÁCTICA)
###############################################################################
# Siempre:
# - Agregar description clara
# - Agregar type explícito
# - Agregar validation donde tenga sentido
# - Usar defaults sensatos para labs
###############################################################################

variable "aws_region" {
  description = "Región AWS para el despliegue"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^(us|eu|ap|sa|ca|me|af)-(north|south|east|west|central|northeast|southeast)-[0-9]$", var.aws_region))
    error_message = "Debe ser una región AWS válida (ej: us-east-1, eu-west-1)."
  }
}

variable "cluster_name" {
  description = "Nombre del cluster EKS (solo letras minúsculas, números y guiones)"
  type        = string
  default     = "platform-cluster"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,38}[a-z0-9]$", var.cluster_name))
    error_message = "El nombre debe tener 4-40 caracteres, solo minúsculas, números y guiones."
  }
}

variable "cluster_version" {
  description = "Versión de Kubernetes para EKS"
  type        = string
  default     = "1.29"

  validation {
    condition     = contains(["1.28", "1.29", "1.30", "1.31"], var.cluster_version)
    error_message = "Versión debe ser una soportada por EKS: 1.28, 1.29, 1.30, 1.31."
  }
}

variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Debe ser un CIDR válido (ej: 10.0.0.0/16)."
  }
}

variable "environment" {
  description = "Ambiente de despliegue"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Ambiente debe ser: development, staging o production."
  }
}

variable "tags" {
  description = "Tags comunes para todos los recursos (BUENA PRÁCTICA: siempre taggear)"
  type        = map(string)
  default = {
    Project   = "cloud-platform-engineering"
    ManagedBy = "terraform"
    Owner     = "devops-team"
  }
}
