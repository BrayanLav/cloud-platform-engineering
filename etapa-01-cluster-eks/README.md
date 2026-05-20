# Etapa 1: Cluster EKS con Fargate

## Qué vamos a hacer

Crear un cluster Kubernetes (EKS) en AWS usando Terraform. Este cluster es la base
donde se despliega todo lo demás en las siguientes etapas.

Al terminar esta etapa vas a tener un cluster Kubernetes corriendo en AWS
al que puedes conectarte con `kubectl` desde tu laptop.

---

## Antes de empezar: Costos

| Recurso | Costo/hora | Se cobra siempre? |
|---------|-----------|-------------------|
| EKS Control Plane | $0.10 | Sí, mientras exista el cluster |
| NAT Gateway | $0.045 | Sí, mientras exista |
| Fargate (CoreDNS, 2 pods) | ~$0.01 | Sí, son pods del sistema |
| **Total** | **~$0.155/hr** | **~$1.24/día (8h)** |

**Traducido:** Si haces el lab en 3 horas te cuesta ~$0.47 USD. Si se te olvida
destruir un día entero, ~$3.72 USD.

---

## Paso 1: Verificar herramientas

Necesitas 3 herramientas instaladas. Abre tu terminal y verifica:

```bash
aws --version        # Necesitas v2.x
terraform --version  # Necesitas >= 1.5
kubectl version --client  # Cualquier versión reciente
```

Si alguna falta, instálala:
- **AWS CLI**: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- **Terraform**: https://developer.hashicorp.com/terraform/install
- **kubectl**: https://kubernetes.io/docs/tasks/tools/

---

## Paso 2: Verificar credenciales AWS

```bash
aws sts get-caller-identity
```

Debe mostrar tu Account ID y ARN. Si da error, configura tus credenciales:

```bash
aws configure
# AWS Access Key ID: (tu access key)
# AWS Secret Access Key: (tu secret key)
# Default region name: us-east-1
# Default output format: json
```

---

## Paso 3: Configurar alerta de billing

**HAZLO ANTES DE CREAR CUALQUIER RECURSO.** Si se te olvida destruir algo,
esta alerta te avisa por email antes de que la factura crezca.

1. Ir a: https://console.aws.amazon.com/billing/home#/budgets
2. Create Budget → Cost Budget
3. Period: Monthly
4. Budget amount: $10 USD
5. Alert threshold: 80% ($8)
6. Email: tu correo personal

---

## Paso 4: Entender la estructura del proyecto

Antes de ejecutar nada, mira los archivos que vas a usar:

```
terraform/
├── versions.tf      → Qué versiones de Terraform y providers usar
├── main.tf          → Configuración de providers (AWS, Kubernetes)
├── variables.tf     → Variables con valores por defecto y VALIDACIÓN
├── terraform.tfvars → Valores específicos para este despliegue
├── vpc.tf           → Crea toda la red (VPC, subnets, NAT)
├── eks.tf           → Crea el cluster EKS y Fargate profiles
├── outputs.tf       → Información útil que se muestra al final
├── backend.tf       → Configuración de remote state (opcional)
└── backend/         → Mini-Terraform para crear el bucket S3 del state
```

### ¿Por qué tantos archivos?

> **🏆 Buena práctica: Un archivo por responsabilidad.**
>
> Podrías meter todo en un solo `main.tf` de 300 líneas, pero es un infierno
> para leer y mantener. Separar por "tema" hace que sea fácil encontrar cosas
> y hacer code review. En un equipo real, una persona puede trabajar en `vpc.tf`
> mientras otra trabaja en `eks.tf` sin conflictos de Git.

---

## Paso 5: Entender QUÉ estamos creando y POR QUÉ

Antes de ejecutar Terraform, necesitas entender qué va a crear y por qué cada
pieza es necesaria. Lee esta sección completa antes de hacer `terraform apply`.

### La arquitectura completa

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            TU CUENTA AWS                                 │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                               │  │
│  │         "Tu red privada virtual en AWS"                           │  │
│  │                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │              SUBNETS PÚBLICAS (3 AZs)                        │  │  │
│  │  │  Tienen ruta directa a internet via Internet Gateway         │  │  │
│  │  │  Aquí viven: Load Balancers (NLB)                           │  │  │
│  │  │                                                             │  │  │
│  │  │  10.0.101.0/24 (us-east-1a)                                 │  │  │
│  │  │  10.0.102.0/24 (us-east-1b)                                 │  │  │
│  │  │  10.0.103.0/24 (us-east-1c)                                 │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                          │                                        │  │
│  │                    NAT Gateway                                     │  │
│  │              (permite salir a internet                            │  │
│  │               desde subnets privadas)                             │  │
│  │                          │                                        │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │              SUBNETS PRIVADAS (3 AZs)                        │  │  │
│  │  │  NO tienen ruta directa a internet (más seguro)              │  │  │
│  │  │  Salen a internet SOLO via NAT Gateway                      │  │  │
│  │  │  Aquí viven: Todos tus pods de Fargate                      │  │  │
│  │  │                                                             │  │  │
│  │  │  10.0.1.0/24 (us-east-1a)                                   │  │  │
│  │  │  10.0.2.0/24 (us-east-1b)                                   │  │  │
│  │  │  10.0.3.0/24 (us-east-1c)                                   │  │  │
│  │  │                                                             │  │  │
│  │  │  ┌─────────────────────────────────────────────────────┐   │  │  │
│  │  │  │              EKS CLUSTER                             │   │  │  │
│  │  │  │                                                     │   │  │  │
│  │  │  │  Control Plane (gestionado por AWS):                │   │  │  │
│  │  │  │    • API Server (recibe tus kubectl)                │   │  │  │
│  │  │  │    • etcd (base de datos del cluster)               │   │  │  │
│  │  │  │    • Scheduler (decide dónde poner pods)            │   │  │  │
│  │  │  │                                                     │   │  │  │
│  │  │  │  Fargate Profiles:                                  │   │  │  │
│  │  │  │    • kube-system → CoreDNS                          │   │  │  │
│  │  │  │    • apps → tus aplicaciones                        │   │  │  │
│  │  │  │    • ingress-nginx → Ingress Controller             │   │  │  │
│  │  │  │    • cert-manager → certificados TLS                │   │  │  │
│  │  │  │    • monitoring → Prometheus/Grafana                │   │  │  │
│  │  │  │    • argocd → ArgoCD                                │   │  │  │
│  │  │  │    • datadog → Datadog Agent                        │   │  │  │
│  │  │  └─────────────────────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### `versions.tf` — Qué versiones usar

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"    # ← Acepta 5.40, 5.41, etc. pero NO 6.0
    }
  }
}
```

> **🏆 Buena práctica: Pinnear versiones de providers y módulos.**
>
> `~> 5.40` significa "acepta cualquier 5.x mayor a 5.40 pero no 6.0".
> Si sale una versión nueva con breaking changes, tu código sigue funcionando.
> Sin esto, un `terraform init` podría descargar una versión incompatible
> y romper todo.

---

### `variables.tf` — Variables con validación

```hcl
variable "cluster_name" {
  description = "Nombre del cluster EKS"
  type        = string
  default     = "platform-cluster"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,38}[a-z0-9]$", var.cluster_name))
    error_message = "Solo minúsculas, números y guiones, 4-40 caracteres."
  }
}
```

> **🏆 Buena práctica: Validar variables.**
>
> Sin validación, si pones un nombre con espacios o mayúsculas, Terraform
> intenta crear el cluster, espera 10 minutos, y LUEGO falla con un error
> críptico de AWS. Con validación, falla INMEDIATAMENTE y te dice exactamente
> qué está mal. Ahorra tiempo y frustración.

---

### `vpc.tf` — La red (explicado línea por línea)

**¿Qué es una VPC?** Tu red privada en AWS. Es como tu propia "LAN" en la nube.
Todo recurso (pods, load balancers, bases de datos) vive dentro de una VPC.

**¿Por qué subnets públicas Y privadas?**
- **Públicas:** Tienen ruta directa a internet. Aquí pones cosas que NECESITAN
  ser accesibles desde afuera (Load Balancers).
- **Privadas:** NO tienen ruta directa a internet. Nadie de internet puede
  llegar a ellas directamente. Aquí pones tus pods (más seguro).

**¿Por qué 3 de cada una?** Una por Availability Zone (AZ). Si una AZ se cae
(pasa en AWS), tus pods siguen corriendo en las otras 2. Es alta disponibilidad.

**¿Qué es el NAT Gateway?** Permite que los pods en subnets privadas SALGAN
a internet (para descargar imágenes Docker, por ejemplo) sin ser accesibles
DESDE internet. Es como un proxy de salida.

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr                    # 10.0.0.0/16 = 65,536 IPs disponibles

  # Usar 3 AZs para alta disponibilidad
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]    # 256 IPs c/u
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # NAT Gateway: permite que pods en subnets privadas accedan a internet
  enable_nat_gateway   = true
  single_nat_gateway   = true   # Solo 1 NAT para ahorrar ($0.045/hr por cada uno)
  enable_dns_hostnames = true   # Necesario para que EKS funcione
  enable_dns_support   = true

  # Tags OBLIGATORIOS para que EKS descubra las subnets automáticamente
  # Sin estos tags, EKS no sabe dónde poner los Load Balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1    # "Pon LBs públicos aquí"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1    # "Pon LBs internos aquí"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
```

> **🏆 Buena práctica: `single_nat_gateway = true` para labs.**
>
> En producción usarías un NAT Gateway por AZ (3 total = $0.135/hr).
> Para labs, uno solo es suficiente y ahorra $0.09/hr. Si la AZ del NAT
> se cae, los pods pierden internet temporalmente, pero para un lab no importa.

> **🏆 Buena práctica: Tags de Kubernetes en las subnets.**
>
> EKS necesita estos tags para saber dónde crear Load Balancers automáticamente.
> Sin `kubernetes.io/role/elb = 1` en las subnets públicas, cuando crees un
> Service tipo LoadBalancer, EKS no sabrá en qué subnet ponerlo y fallará.

---

### `eks.tf` — El cluster EKS y Fargate (explicado a detalle)

**¿Qué es EKS?** Kubernetes administrado por AWS. Tú no instalas ni mantienes
el control plane (API server, etcd, scheduler). AWS lo hace y te cobra $0.10/hr.

**¿Qué es Fargate?** En vez de tener servidores EC2 como nodos de Kubernetes,
AWS corre cada pod en su propia micro-VM aislada. No gestionas servidores.

**¿Qué es un Fargate Profile?** Una regla que dice: "todos los pods que se creen
en el namespace X, córrelos en Fargate". Sin un profile que matchee, el pod
se queda en `Pending` para siempre (Kubernetes no sabe dónde ponerlo).

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name      # "platform-cluster"
  cluster_version = var.cluster_version   # "1.29"

  # Endpoint público = puedes usar kubectl desde tu laptop via internet
  # En producción pondrías esto en false y usarías VPN
  cluster_endpoint_public_access = true

  # Add-ons: componentes esenciales que EKS necesita para funcionar
  cluster_addons = {
    # CoreDNS: resuelve nombres dentro del cluster
    # (para que un pod pueda hablar con otro por nombre, ej: "mi-servicio.apps")
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"   # Decirle a CoreDNS que corre en Fargate
      })
    }
    # kube-proxy: reglas de red para que los Services funcionen
    kube-proxy = {}
    # vpc-cni: asigna IPs de la VPC a cada pod (networking de AWS)
    vpc-cni = {}
  }

  # En qué VPC y subnets corre el cluster
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets   # Pods corren en subnets PRIVADAS
```

**Fargate Profiles — La parte más importante:**

```hcl
  fargate_profiles = {
    # ──────────────────────────────────────────────────────────────────
    # Profile: system
    # Para: pods del sistema de Kubernetes (CoreDNS, kube-proxy)
    # Sin esto: el cluster no arranca (CoreDNS no tiene dónde correr)
    # ──────────────────────────────────────────────────────────────────
    system = {
      name = "system"
      selectors = [
        { namespace = "kube-system" }
      ]
    }

    # ──────────────────────────────────────────────────────────────────
    # Profile: ingress
    # Para: NGINX Ingress Controller y cert-manager (etapa 2)
    # Sin esto: no puedes exponer servicios al exterior
    # Nota: un profile puede tener múltiples selectors (namespaces)
    # ──────────────────────────────────────────────────────────────────
    ingress = {
      name = "ingress"
      selectors = [
        { namespace = "ingress-nginx" },
        { namespace = "cert-manager" }
      ]
    }

    # ──────────────────────────────────────────────────────────────────
    # Profile: monitoring
    # Para: Prometheus, Grafana, Alertmanager (etapa 3)
    # Sin esto: los pods de monitoreo quedan en Pending
    # ──────────────────────────────────────────────────────────────────
    monitoring = {
      name = "monitoring"
      selectors = [
        { namespace = "monitoring" }
      ]
    }

    # ──────────────────────────────────────────────────────────────────
    # Profile: argocd
    # Para: ArgoCD server, repo-server, controller, redis (etapa 4)
    # Sin esto: no puedes instalar ArgoCD
    # ──────────────────────────────────────────────────────────────────
    argocd = {
      name = "argocd"
      selectors = [
        { namespace = "argocd" }
      ]
    }

    # ──────────────────────────────────────────────────────────────────
    # Profile: datadog
    # Para: Datadog Operator y Agent (etapa 5)
    # ──────────────────────────────────────────────────────────────────
    datadog = {
      name = "datadog"
      selectors = [
        { namespace = "datadog" }
      ]
    }

    # ──────────────────────────────────────────────────────────────────
    # Profile: apps
    # Para: tus aplicaciones (lo que tú despliegues)
    # Este es el namespace donde pones tus cosas
    # ──────────────────────────────────────────────────────────────────
    apps = {
      name = "apps"
      selectors = [
        { namespace = "apps" }
      ]
    }
  }
}
```

> **¿Cómo funciona el matching de Fargate Profiles?**
>
> Cuando creas un pod, EKS revisa todos los Fargate Profiles en orden:
> 1. ¿El namespace del pod coincide con algún selector? → SÍ → corre en Fargate
> 2. ¿No coincide con ninguno? → el pod queda en `Pending` para siempre
>
> Por eso creamos un profile por cada namespace que vamos a usar.
> Si mañana quieres agregar un namespace nuevo (ej: "staging"), necesitas
> agregar un Fargate Profile para él en este archivo y hacer `terraform apply`.

> **¿Por qué no un solo profile con `namespace = "*"` (todos)?**
>
> Fargate no soporta wildcards. Cada namespace debe estar explícito.
> Además, tener profiles separados te da control: podrías tener un profile
> con instancias más grandes para "monitoring" y más pequeñas para "apps".

> **🏆 Buena práctica: Crear los Fargate Profiles desde el inicio.**
>
> Si creas el cluster sin profiles y luego intentas instalar Prometheus,
> los pods quedan en Pending y no sabes por qué. Mejor crear todos los
> profiles que vas a necesitar desde el principio (es gratis, no cuestan nada).

---

### `main.tf` — Providers (cómo Terraform se conecta)

```hcl
provider "aws" {
  region = var.aws_region

  # Tags que se agregan AUTOMÁTICAMENTE a todo recurso creado
  default_tags {
    tags = var.tags
  }
}

# Provider de Kubernetes: para que Terraform pueda configurar cosas dentro del cluster
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  # Usa AWS CLI para autenticarse (mismo mecanismo que kubectl)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}
```

> **🏆 Buena práctica: Tags por defecto en el provider.**
>
> `default_tags` agrega tags a TODOS los recursos sin tener que ponerlos
> uno por uno. Cuando llega la factura de AWS, puedes filtrar por
> `Project = cloud-platform-engineering` y ver exactamente cuánto gastaste.

---

### `outputs.tf` — Qué te muestra al terminar

Después de `terraform apply`, Terraform imprime estos valores:

```hcl
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
```

Así no tienes que recordar el comando. Terraform te lo da listo para copiar y pegar.

---

### `backend.tf` — Remote state (opcional pero recomendado)

> **🏆 Buena práctica: Remote state en S3 + DynamoDB.**
>
> Por defecto, Terraform guarda el state en un archivo local (`terraform.tfstate`).
> Problemas:
> - Si borras tu laptop, pierdes el state y Terraform no sabe qué creó
> - Si trabajas en equipo, dos personas pueden aplicar al tiempo y corromperlo
>
> Solución: Guardar el state en S3 (encriptado, versionado) con DynamoDB
> para locking (solo una persona aplica a la vez).
>
> **Para este lab es OPCIONAL.** Si estás solo, el state local funciona bien.
> Pero si quieres practicar (recomendado), sigue las instrucciones en `backend.tf`.

---

## Paso 6: Inicializar Terraform

```bash
cd terraform/
terraform init
```

Esto descarga:
- Provider de AWS (~200MB la primera vez)
- Módulo de VPC (terraform-aws-modules/vpc/aws)
- Módulo de EKS (terraform-aws-modules/eks/aws)

Deberías ver:
```
Terraform has been successfully initialized!
```

Si falla: verifica tu conexión a internet y que Terraform está instalado.

---

## Paso 7: Revisar el plan

```bash
terraform plan
```

**SIEMPRE revisa el plan antes de aplicar.** Esto te muestra TODO lo que
Terraform va a crear sin crear nada. Verás algo como:

```
Plan: 55 to add, 0 to change, 0 to destroy.
```

Esos 55 recursos incluyen: VPC, 6 subnets, route tables, NAT gateway,
internet gateway, IAM roles, EKS cluster, fargate profiles, add-ons, etc.

> **🏆 Buena práctica: Nunca hacer `apply` sin revisar el `plan`.**
>
> En producción, un `apply` sin revisar puede borrar una base de datos
> o cambiar un security group. Siempre lee qué va a hacer.

---

## Paso 8: Crear la infraestructura

```bash
terraform apply
```

Terraform te muestra el plan de nuevo y pregunta:
```
Do you want to perform these actions?
  Enter a value: yes
```

Escribe `yes` y espera.

⏱️ **Tiempo: 12-18 minutos** (el cluster EKS tarda ~10 min en crearse)

Al terminar verás los outputs:
```
cluster_name = "platform-cluster"
configure_kubectl = "aws eks update-kubeconfig --name platform-cluster --region us-east-1"
fargate_profiles = ["apps", "argocd", "datadog", "ingress", "monitoring", "system"]
```

---

## Paso 9: Conectar kubectl al cluster

kubectl es la herramienta para hablar con Kubernetes. Necesita saber
dónde está tu cluster. Este comando configura eso:

```bash
aws eks update-kubeconfig --name platform-cluster --region us-east-1
```

Verificar que funciona:
```bash
kubectl cluster-info
```

Debe mostrar algo como:
```
Kubernetes control plane is running at https://XXXXX.gr7.us-east-1.eks.amazonaws.com
CoreDNS is running at https://XXXXX.gr7.us-east-1.eks.amazonaws.com/api/v1/...
```

> **¿Qué pasó aquí?**
> `aws eks update-kubeconfig` descargó un archivo de configuración y lo guardó
> en `~/.kube/config`. Ese archivo tiene la URL del cluster y cómo autenticarse.
> kubectl lee ese archivo cada vez que ejecutas un comando.

---

## Paso 10: Verificar el cluster

```bash
# Ver namespaces (como "carpetas" dentro del cluster)
kubectl get ns
```

Deberías ver:
```
NAME              STATUS   AGE
default           Active   5m
kube-node-lease   Active   5m
kube-public       Active   5m
kube-system       Active   5m
```

```bash
# Ver pods del sistema
kubectl get pods -n kube-system
```

Deberías ver CoreDNS corriendo:
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
```

```bash
# Ver nodos (en Fargate, los nodos aparecen cuando hay pods)
kubectl get nodes
```

Deberías ver nodos Fargate:
```
NAME                                      STATUS   ROLES    AGE   VERSION
fargate-ip-10-0-1-xxx.ec2.internal        Ready    <none>   5m    v1.29.x
fargate-ip-10-0-2-xxx.ec2.internal        Ready    <none>   5m    v1.29.x
```

---

## Paso 11: Probar desplegando un pod

Vamos a crear un pod simple para verificar que Fargate funciona:

```bash
# Crear el namespace "apps" (tiene Fargate profile, así que los pods correrán ahí)
kubectl create namespace apps

# Crear un pod de nginx
kubectl run test-nginx --image=nginx:alpine -n apps

# Ver el estado (esperar ~30-60 seg por el cold start de Fargate)
kubectl get pods -n apps -w
```

Verás la progresión:
```
NAME         READY   STATUS    RESTARTS   AGE
test-nginx   0/1     Pending   0          5s     ← Fargate creando la micro-VM
test-nginx   0/1     Pending   0          30s    ← Todavía creando...
test-nginx   1/1     Running   0          45s    ← ¡Listo!
```

> **¿Por qué tarda 30-60 segundos?**
> Fargate crea una micro-VM exclusiva para cada pod. Eso toma tiempo
> (se llama "cold start"). En EC2 nodes normales es instantáneo porque
> el nodo ya existe. Es el trade-off de Fargate: no gestionas nodos
> pero tienes cold start.

Eliminar el pod de prueba:
```bash
kubectl delete pod test-nginx -n apps
```

---

## Paso 12: (Opcional) Configurar remote state

Si quieres practicar remote state (recomendado para aprender):

```bash
# 1. Crear el bucket S3 y tabla DynamoDB
cd backend/
terraform init
terraform apply
# Escribe "yes"
cd ..

# 2. Editar backend.tf → descomentar el bloque "terraform { backend "s3" {...} }"
# Cambiar el nombre del bucket si es necesario (debe ser único globalmente)

# 3. Migrar el state local al remoto
terraform init -migrate-state
# Terraform pregunta si quieres copiar el state → yes
```

Ahora tu state está seguro en S3, encriptado y con locking.

---

## ✅ Etapa 1 completada

Si llegaste hasta aquí, tienes:
- ✅ VPC con subnets públicas y privadas en 3 AZs
- ✅ Cluster EKS corriendo Kubernetes 1.29
- ✅ Fargate profiles para todos los namespaces que necesitarás
- ✅ kubectl conectado y funcionando
- ✅ (Opcional) Remote state en S3

**Siguiente paso:** Ve a `etapa-02-ingress-controller/README.md`

> ⚠️ **NO destruyas el cluster todavía** si vas a seguir con las otras etapas.
> Destruye solo cuando termines TODO lo que quieras hacer hoy.

---

## 🔴 Destruir (cuando termines TODAS las etapas del día)

> ⚠️ **IMPORTANTE: No hagas `terraform destroy` directamente.**
>
> Kubernetes crea Load Balancers (NLB/ALB) que viven en tu VPC pero Terraform
> no sabe que existen (porque los creó Kubernetes, no Terraform). Si haces
> `terraform destroy` sin eliminarlos primero, falla con un error tipo:
> `"DependencyViolation: VPC has dependencies and cannot be deleted"`.
>
> **Siempre elimina los recursos de Kubernetes ANTES de destruir con Terraform.**

```bash
# PASO 1: Eliminar Services tipo LoadBalancer (esto borra los NLB/ALB en AWS)
kubectl delete svc ingress-nginx-controller -n ingress-nginx 2>/dev/null
kubectl delete ingress --all-namespaces --all 2>/dev/null

# PASO 2: Desinstalar Helm releases
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null
helm uninstall cert-manager -n cert-manager 2>/dev/null
helm uninstall monitoring -n monitoring 2>/dev/null
helm uninstall argocd -n argocd 2>/dev/null
helm uninstall datadog-operator -n datadog 2>/dev/null

# PASO 3: Esperar a que AWS elimine los Load Balancers (~60 seg)
echo "Esperando que AWS elimine los LBs..."
sleep 60

# PASO 4: Verificar que no quedan LBs (debe estar vacío)
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[].DNSName'

# PASO 5: Ahora sí, destruir la infraestructura
cd etapa-01-cluster-eks/terraform/
terraform destroy -auto-approve
```

⏱️ Tiempo total de destrucción: ~12 minutos.

**¿Y si terraform destroy falla de todas formas?**

```bash
# Opción A: Esperar más y reintentar
sleep 60
terraform destroy -auto-approve

# Opción B: Eliminar el LB manualmente desde la consola AWS
# EC2 → Load Balancers → seleccionar → Actions → Delete
# Luego reintentar terraform destroy

# Opción C: Forzar eliminación de la VPC (último recurso)
# VPC → seleccionar la VPC → Actions → Delete VPC
# (esto elimina subnets, routes, etc. en cascada)
# Luego: terraform destroy (solo quedan IAM roles y el cluster)
```

**O usa el script que ya tiene todo esto automatizado:**
```bash
chmod +x scripts/destroy-all.sh
./scripts/destroy-all.sh
```

**Verificar que no queda nada:**
```bash
aws eks list-clusters --region us-east-1
# Debe devolver: { "clusters": [] }
```

---

## Errores comunes

| Error | Qué significa | Solución |
|-------|--------------|----------|
| `terraform init` falla | Sin internet o proxy corporativo | Verificar conexión |
| `ResourceInUseException` | Ya existe un cluster con ese nombre | Cambiar `cluster_name` en terraform.tfvars |
| `insufficient free addresses` | Límite de Elastic IPs en tu cuenta | Liberar EIPs en la consola o pedir aumento |
| `kubectl: connection refused` | kubeconfig no configurado | Ejecutar `aws eks update-kubeconfig` de nuevo |
| Pods en `Pending` para siempre | No hay Fargate Profile para ese namespace | Verificar que el namespace tiene profile en eks.tf |
| `Unauthorized` | IAM no tiene permisos | Usar el mismo user/role que creó el cluster |
| `Error: creating EKS Cluster: timeout` | AWS tardó más de lo esperado | Ejecutar `terraform apply` de nuevo (es idempotente) |
