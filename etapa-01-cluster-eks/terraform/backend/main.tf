###############################################################################
# Crear el bucket S3 y tabla DynamoDB para remote state
###############################################################################
# Este es un mini-Terraform que crea la infraestructura para guardar el state.
# Se ejecuta UNA SOLA VEZ antes de todo lo demás.
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
# DynamoDB Table para locking
# ============================================================================
# Previene que dos personas apliquen Terraform al mismo tiempo
resource "aws_dynamodb_table" "tflock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"  # Gratis en free tier (25GB)
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "Terraform Lock"
    ManagedBy = "terraform"
  }
}

# ============================================================================
# Variables
# ============================================================================
variable "bucket_name" {
  description = "Nombre del bucket S3 (debe ser único globalmente)"
  type        = string
  default     = "platform-cluster-tfstate"
}

variable "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB para locking"
  type        = string
  default     = "platform-cluster-tflock"
}

# ============================================================================
# Outputs
# ============================================================================
output "bucket_name" {
  value = aws_s3_bucket.tfstate.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tflock.name
}

output "next_step" {
  value = "Ahora descomenta el backend en ../backend.tf y ejecuta: terraform init -migrate-state"
}
