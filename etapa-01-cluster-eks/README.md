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

## Paso 5: Entender los archivos Terraform

Abre cada archivo y lee los comentarios. Aquí te explico qué hace cada uno:

### `versions.tf` — Versiones pinneadas

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

### `vpc.tf` — La red

Usa el módulo oficial `terraform-aws-modules/vpc/aws` que crea:
- VPC con el CIDR que definas
- 3 subnets públicas (una por AZ) → para Load Balancers
- 3 subnets privadas (una por AZ) → para tus pods
- Internet Gateway → para que las subnets públicas tengan internet
- NAT Gateway → para que las subnets privadas puedan salir a internet
- Route Tables → reglas de tráfico

> **🏆 Buena práctica: Usar módulos oficiales en vez de escribir todo a mano.**
>
> El módulo `terraform-aws-modules/vpc/aws` tiene 5+ años de desarrollo,
> miles de usuarios y cientos de bugs corregidos. Escribir una VPC desde cero
> son ~200 líneas de código donde es fácil olvidar algo (como los tags que
> EKS necesita en las subnets). El módulo lo hace todo en 20 líneas.

### `eks.tf` — El cluster

Usa el módulo `terraform-aws-modules/eks/aws` que crea:
- El cluster EKS (control plane)
- Fargate Profiles (uno por cada namespace que usaremos)
- Add-ons (CoreDNS, kube-proxy, vpc-cni)
- IAM roles con permisos mínimos

Los **Fargate Profiles** son clave. Le dicen a EKS: "los pods que se creen
en el namespace X, córrelos en Fargate". Si un pod se crea en un namespace
que NO tiene profile, se queda en `Pending` para siempre.

Por eso creamos profiles para todos los namespaces que usaremos:
- `kube-system` → pods del sistema (CoreDNS)
- `apps` → tus aplicaciones
- `monitoring` → Prometheus/Grafana (etapa 3)
- `argocd` → ArgoCD (etapa 4)
- `ingress-nginx` → Ingress Controller (etapa 2)
- `cert-manager` → Certificados TLS (etapa 2)
- `datadog` → Datadog (etapa 5)

### `main.tf` — Providers

Configura cómo Terraform se conecta a AWS y a Kubernetes.

> **🏆 Buena práctica: Tags por defecto en el provider.**
>
> ```hcl
> provider "aws" {
>   default_tags {
>     tags = var.tags
>   }
> }
> ```
>
> Esto agrega tags automáticamente a TODOS los recursos sin tener que
> ponerlos uno por uno. Útil para:
> - Saber quién creó qué (cuando llega la factura)
> - Filtrar en AWS Cost Explorer por proyecto
> - Identificar recursos huérfanos

### `outputs.tf` — Información post-apply

Después de `terraform apply`, Terraform muestra estos valores:
- Nombre del cluster
- Comando para configurar kubectl
- Fargate profiles creados

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

```bash
# PRIMERO: eliminar lo que instalaste con Helm (etapas 2-5)
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null
helm uninstall cert-manager -n cert-manager 2>/dev/null
helm uninstall monitoring -n monitoring 2>/dev/null
helm uninstall argocd -n argocd 2>/dev/null
helm uninstall datadog-operator -n datadog 2>/dev/null

# Esperar 30 seg (para que se eliminen Load Balancers)
sleep 30

# LUEGO: destruir la infraestructura base
cd etapa-01-cluster-eks/terraform/
terraform destroy -auto-approve
```

⏱️ Tiempo de destrucción: ~10 minutos.

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
