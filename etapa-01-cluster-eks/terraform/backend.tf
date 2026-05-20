###############################################################################
# Backend remoto en S3 + DynamoDB (BUENA PRÁCTICA)
###############################################################################
# ¿Por qué remote state?
# - El state local (.tfstate) se puede perder si borras tu laptop
# - Si trabajas en equipo, dos personas pueden aplicar al tiempo y corromperlo
# - S3 + DynamoDB = state seguro, versionado y con locking
#
# INSTRUCCIONES:
# 1. Primero crea el bucket y tabla con: terraform -chdir=backend init && apply
# 2. Luego descomenta este bloque y ejecuta: terraform init (migra el state)
###############################################################################

# terraform {
#   backend "s3" {
#     bucket         = "platform-cluster-tfstate"    # Nombre del bucket (debe ser único global)
#     key            = "eks/terraform.tfstate"       # Path dentro del bucket
#     region         = "us-east-1"
#     encrypt        = true                          # Encriptar el state en reposo
#     dynamodb_table = "platform-cluster-tflock"     # Tabla para locking
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
