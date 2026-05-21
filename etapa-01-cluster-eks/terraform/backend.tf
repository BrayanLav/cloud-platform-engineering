###############################################################################
# Backend remoto en S3 con locking nativo (BUENA PRÁCTICA)
###############################################################################
# ¿Por qué remote state?
# - El state local (.tfstate) se puede perder si borras tu laptop
# - Si trabajas en equipo, dos personas pueden aplicar al tiempo y corromperlo
# - S3 con locking nativo = state seguro, versionado y con locking
#
# NOTA: Desde Terraform 1.10 (nov 2024), S3 tiene locking NATIVO.
# Ya NO necesitas DynamoDB. Solo use_lockfile = true.
# DynamoDB para locking está DEPRECATED y será removido.
#
# INSTRUCCIONES:
# 1. Primero crea el bucket con: terraform -chdir=backend init && apply
# 2. Luego descomenta este bloque y ejecuta: terraform init (migra el state)
###############################################################################

# terraform {
#   backend "s3" {
#     bucket       = "platform-cluster-tfstate"    # Nombre del bucket (único global)
#     key          = "eks/terraform.tfstate"       # Path dentro del bucket
#     region       = "us-east-1"
#     encrypt      = true                          # Encriptar el state en reposo
#     use_lockfile = true                          # Locking nativo de S3 (NO necesita DynamoDB)
#   }
# }

# ============================================================================
# NOTA PARA PRINCIPIANTES:
# ============================================================================
# Si estás haciendo el lab solo (sin equipo), puedes dejar esto comentado
# y usar state local. Funciona igual, solo que el state queda en tu PC.
#
# Si quieres practicar remote state (recomendado para aprender):
# 1. Ve a la carpeta backend/ y ejecuta terraform apply
# 2. Vuelve aquí, descomenta el bloque de arriba
# 3. Ejecuta: terraform init -migrate-state
# 4. Terraform te pregunta si quieres migrar → yes
#
# IMPORTANTE: use_lockfile = true requiere Terraform >= 1.10
# Verifica tu versión: terraform --version
