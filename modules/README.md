# Módulos Terraform Reutilizables

Esta carpeta contiene módulos Terraform propios que encapsulan patrones repetitivos.

## ¿Por qué módulos propios?

En las etapas del proyecto, hay patrones que se repiten:
- Crear un Fargate Profile (siempre es: profile + IAM role + selector)
- Instalar un Helm chart (siempre es: namespace + release + values + wait)

En vez de copiar/pegar el mismo código, creamos un módulo que se usa así:

```hcl
module "profile_apps" {
  source       = "../../modules/fargate-profile"
  cluster_name = "platform-cluster"
  profile_name = "apps"
  namespace    = "apps"
  subnet_ids   = module.vpc.private_subnets
}
```

## Módulos disponibles

| Módulo | Qué hace |
|--------|----------|
| `fargate-profile/` | Crea un Fargate Profile + IAM Role |
| `helm-release/` | Instala un Helm chart con buenas prácticas |

## Buenas prácticas aplicadas en los módulos

> **🏆 Cada módulo tiene su propio README con documentación de uso.**

> **🏆 Variables con `description` y `type` siempre.**

> **🏆 Outputs para que otros módulos puedan referenciar lo creado.**

> **🏆 Valores por defecto sensatos (no obligar al usuario a definir todo).**

> **🏆 Un módulo hace UNA cosa bien (Single Responsibility).**

## Cuándo crear un módulo vs cuándo no

**Crear módulo cuando:**
- El mismo patrón se repite 3+ veces
- Quieres encapsular complejidad (IAM roles, policies)
- Quieres forzar buenas prácticas (tags, naming)

**NO crear módulo cuando:**
- Solo se usa una vez (over-engineering)
- Es muy simple (un solo recurso sin lógica)
- El módulo oficial de la comunidad ya existe y es bueno
