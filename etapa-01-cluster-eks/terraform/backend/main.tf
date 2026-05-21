###############################################################################
# Crear el bucket S3 para remote state (con locking nativo)
###############################################################################
# Desde Terraform 1.10+ (nov 2024), S3 soporta locking NATIVO.
# Ya NO necesitas DynamoDB. Solo S3 con use_lockfile = true.
#
# Uso:
#   cd backend/
#   terraform init
#   terraform apply
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================================================
# S3 Bucket para el state
# ============================================================================
resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  # Prevenir eliminación accidental
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State"
    ManagedBy = "terraform"
  }
}

# Versionamiento (para poder recuperar states anteriores)
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encriptación en reposo (buena práctica de seguridad)
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquear acceso público (el state tiene info sensible)
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# YA NO NECESITAS DYNAMODB
# ============================================================================
# Antes (Terraform < 1.10):
#   Se necesitaba una tabla DynamoDB para locking.
#   Esto está DEPRECATED y será removido en futuras versiones.
#
# Ahora (Terraform >= 1.10):
#   S3 tiene locking nativo con use_lockfile = true.
#   Crea un archivo .tflock junto al state. Más simple, menos infra.
# ============================================================================

# ============================================================================
# Variables
# ============================================================================
variable "bucket_name" {
  description = "Nombre del bucket S3 (debe ser único globalmente)"
  type        = string
  default     = "platform-cluster-tfstate"
}

# ============================================================================
# Outputs
# ============================================================================
output "bucket_name" {
  value = aws_s3_bucket.tfstate.id
}

output "next_step" {
  value = "Ahora descomenta el backend en ../backend.tf y ejecuta: terraform init -migrate-state"
}
