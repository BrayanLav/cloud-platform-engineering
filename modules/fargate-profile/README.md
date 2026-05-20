# Módulo: Fargate Profile

Crea un Fargate Profile para EKS con su IAM Role asociado.

## Uso

```hcl
module "profile_monitoring" {
  source       = "../../modules/fargate-profile"
  cluster_name = "platform-cluster"
  profile_name = "monitoring"
  namespace    = "monitoring"
  subnet_ids   = module.vpc.private_subnets
  tags         = { Environment = "development" }
}
```

## Variables

| Nombre | Tipo | Requerido | Descripción |
|--------|------|-----------|-------------|
| cluster_name | string | ✅ | Nombre del cluster EKS |
| profile_name | string | ✅ | Nombre del profile |
| namespace | string | ✅ | Namespace que matchea |
| subnet_ids | list(string) | ✅ | Subnets privadas |
| labels | map(string) | ❌ | Labels adicionales para el selector |
| tags | map(string) | ❌ | Tags |

## Outputs

| Nombre | Descripción |
|--------|-------------|
| profile_id | ID del Fargate Profile |
| profile_arn | ARN del Fargate Profile |
| role_arn | ARN del IAM Role |
