# Etapa 1: Crear el Cluster EKS con Fargate (desde la consola)

## Resumen

Crear un cluster Kubernetes (EKS) en AWS con Fargate, paso a paso desde la consola.
Este cluster es la **base** de todo el proyecto — las 5 etapas se construyen sobre él.

Al terminar esta etapa vas a tener un cluster Kubernetes corriendo en AWS
al que puedes conectarte con `kubectl` desde tu PC.

**Costo estimado:** ~$0.155/hr (EKS $0.10 + NAT $0.045 + Fargate CoreDNS ~$0.01)

**Herramientas necesarias en tu PC:**
- AWS CLI v2
- kubectl
- eksctl
- helm (se usa desde etapa 2)

---

## ¿Qué estamos construyendo en TODO el proyecto?

Antes de empezar, mira el panorama completo. Son 5 etapas donde cada una
agrega una capa sobre la anterior:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     TU PLATAFORMA KUBERNETES                        │
│                                                                     │
│  ETAPA 5 ─── Datadog ───── Monitoreo enterprise (logs, APM, todo)  │
│  ETAPA 4 ─── ArgoCD ────── GitOps (despliegues automáticos)        │
│  ETAPA 3 ─── Prometheus ── Monitoreo open source (métricas, alertas)│
│  ETAPA 2 ─── Ingress ───── Acceso web (URL pública, routing HTTP)  │
│  ETAPA 1 ─── EKS + VPC ─── El cluster base (estás aquí 👈)         │
│                                                                     │
│  Cada capa necesita las anteriores. No puedes saltarte ninguna.    │
└─────────────────────────────────────────────────────────────────────┘
```

**¿Qué es cada cosa?** (te lo explico todo a lo largo del lab, pero el resumen rápido):

| Herramienta | Qué es | Analogía |
|-------------|--------|----------|
| **EKS** | Kubernetes administrado por AWS | Un "servidor de apps" que AWS mantiene por ti |
| **Fargate** | Ejecuta tus pods sin que gestiones servidores | Como Lambda pero para contenedores |
| **Ingress** | Puerta de entrada desde internet a tu cluster | Un recepcionista que dirige visitantes |
| **Prometheus** | Recolecta métricas de todo | Un sensor que mide temperatura de todo |
| **Grafana** | Dashboards bonitos para ver métricas | El tablero con las pantallas del sensor |
| **ArgoCD** | Despliegues automáticos desde Git | Un robot que aplica tus cambios de Git |
| **Datadog** | Monitoreo todo-en-uno enterprise | Como Prometheus+Grafana pero cloud y de pago |

---

## Conceptos clave (para entender qué estamos haciendo)

### ¿Qué es Kubernetes?

Kubernetes (K8s) es un sistema que **ejecuta y gestiona aplicaciones en contenedores**.
Imagina que tienes 10 aplicaciones. Sin Kubernetes, tendrías que:
- Configurar 10 servidores manualmente
- Si un servidor se cae, levantarlo tú
- Escalar manualmente cuando hay más tráfico
- Actualizar una por una

Con Kubernetes, le dices: "quiero 3 copias de mi app corriendo" y él se encarga
de TODO: dónde ponerlas, reiniciarlas si fallan, escalar si hay tráfico.

### ¿Qué es EKS (Elastic Kubernetes Service)?

Es Kubernetes pero **administrado por AWS**. En vez de instalar y mantener
Kubernetes tú mismo (que es MUY complejo), AWS se encarga del "cerebro"
(control plane: API server, etcd, scheduler) y tú solo despliegas tus apps.

```
┌────────────────────────────────────────────────────┐
│                    EKS CLUSTER                      │
│                                                    │
│  ┌──────────────────────┐    ┌──────────────────┐  │
│  │   Control Plane      │    │   Tus apps       │  │
│  │   (AWS lo mantiene)  │    │   (tú las pones) │  │
│  │                      │    │                  │  │
│  │   • API Server       │◄──►│   • Pod nginx    │  │
│  │   • etcd (base datos)│    │   • Pod api      │  │
│  │   • Scheduler        │    │   • Pod frontend │  │
│  └──────────────────────┘    └──────────────────┘  │
│         $0.10/hr                  Variable          │
└────────────────────────────────────────────────────┘
```

### ¿Qué es Fargate?

Normalmente, los "pods" (contenedores) corren en servidores EC2 que tú eliges
y gestionas. **Fargate elimina eso**: AWS crea una micro-VM aislada para cada pod
automáticamente. No ves servidores, no los actualizas, no los escalas.

**Trade-off:**
| Ventaja | Desventaja |
|---------|-----------|
| No gestionas servidores | Cold start de 30-60 seg por pod |
| Pagas solo por lo que usas | No puedes hacer SSH a los nodos |
| Aislamiento de seguridad por pod | No soporta DaemonSets (un pod en cada nodo) |
| Escala automáticamente | No soporta volúmenes EBS (disco persistente) |

### ¿Por qué Fargate y no EC2 o Auto Mode?

Para este proyecto usamos Fargate porque:
1. **No tienes que gestionar nodos** — te enfocas en aprender Kubernetes, no en administrar EC2
2. **Es más barato para labs** — solo pagas los pods que corren, no instancias idle
3. **Es lo que muchas empresas usan** — especialmente para workloads stateless

Si ya hiciste los otros labs (EC2, Auto Mode), esto te da la perspectiva Fargate
para comparar. En producción real, Auto Mode es la opción más nueva y recomendada.

---

## Costos detallados

| Recurso | Costo/hora | ¿Se cobra siempre? |
|---------|-----------|-------------------|
| EKS Control Plane | $0.10 | Sí, mientras exista el cluster |
| NAT Gateway | $0.045 | Sí, mientras exista |
| Fargate - CoreDNS (2 pods) | ~$0.01 | Sí, son pods del sistema |
| **Total base** | **~$0.155/hr** | |

| Duración | Costo estimado |
|----------|---------------|
| 2 horas (solo esta etapa) | ~$0.31 |
| 4 horas (etapas 1-3) | ~$1.50 |
| 6 horas (todas las etapas) | ~$2.50 |
| ⚠️ Se te olvidó destruir 1 día | ~$3.72 |
| ⚠️ Se te olvidó destruir 1 semana | ~$26 |

> **REGLA #1:** Siempre destruye todo cuando termines. Si no vas a seguir
> con las etapas siguientes HOY, destruye el cluster y vuelve a crearlo mañana.
> Es más barato recrear que dejarlo corriendo.

---

## Paso 0: Preparar tu PC

### Instalar herramientas

Necesitas 4 herramientas. Abre PowerShell y verifica cada una:

```powershell
aws --version        # Necesitas v2.x
kubectl version --client  # Cualquier versión reciente
eksctl version       # Cualquier versión reciente
helm version         # Necesitas v3.x (se usa desde etapa 2)
```

Si alguna falta:
- **AWS CLI**: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- **kubectl**: `winget install Kubernetes.kubectl`
- **eksctl**: `winget install weaveworks.eksctl`
- **Helm**: `winget install Helm.Helm`

### Verificar credenciales AWS

```powershell
aws sts get-caller-identity
```

Debe mostrar tu Account ID y ARN. Si da error:

```powershell
aws configure
# AWS Access Key ID: (tu access key)
# AWS Secret Access Key: (tu secret key)
# Default region name: us-east-1
# Default output format: json
```

### Configurar alerta de billing

**HAZLO ANTES DE CREAR CUALQUIER RECURSO.**

1. Ir a: https://console.aws.amazon.com/billing/home#/budgets
2. Create Budget → **Cost Budget**
3. Period: Monthly
4. Budget amount: **$10 USD**
5. Alert threshold: 80% ($8)
6. Email: tu correo personal
7. Create

Si se te olvida destruir algo, esta alerta te avisa antes de que la factura crezca.

---

## Paso 1: Crear IAM Roles

Necesitas **2 roles**: uno para el cluster y otro para Fargate.

### ¿Qué es un IAM Role?

Un rol es un conjunto de permisos. En vez de darle credenciales directas a un
servicio (como darle la llave de tu casa), le asignas un rol que dice
"puedes hacer X, Y y Z" y el servicio asume ese rol temporalmente.

### Rol 1: Cluster EKS

El cluster necesita un rol para gestionar recursos en AWS (crear interfaces de red,
comunicarse con EC2, registrar nodos, etc.)

1. **IAM** → **Roles** → **Create role**
2. Trusted entity type: **Custom trust policy**
3. Pegar esta política de confianza:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

> **¿Qué dice esta política?** "Confío en el servicio `eks.amazonaws.com` para
> que asuma este rol." Es decir, solo EKS puede usar estos permisos, no cualquiera.

4. Next → buscar y marcar **AmazonEKSClusterPolicy** → Next
5. Role name: **`platform-lab-cluster-role`** → Create role

### Rol 2: Fargate Pod Execution

Fargate necesita un rol para ejecutar los pods (descargar imágenes Docker,
escribir logs, etc.)

1. **IAM** → **Roles** → **Create role**
2. Trusted entity type: **Custom trust policy**
3. Pegar:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks-fargate-pods.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

> **¿Por qué el servicio es diferente?** Porque el cluster y los pods de Fargate
> son servicios diferentes de AWS. El cluster es `eks.amazonaws.com`, pero los
> pods de Fargate los ejecuta `eks-fargate-pods.amazonaws.com`. Cada uno necesita
> su propio rol con sus propios permisos.

4. Next → buscar y marcar **AmazonEKSFargatePodExecutionRolePolicy** → Next
5. Role name: **`platform-lab-fargate-role`** → Create role

---

## Paso 2: Crear VPC

### ¿Qué es una VPC?

VPC = Virtual Private Cloud. Es tu **red privada** dentro de AWS. Es como tener
tu propio "piso" en un edificio de oficinas: tú controlas quién entra, quién sale,
y cómo se organizan las "habitaciones" (subnets).

TODO recurso en AWS vive dentro de una VPC.

### ¿Por qué subnets públicas Y privadas?

```
┌─────────────────────────────────────────────────────┐
│                        VPC                           │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │         SUBNETS PÚBLICAS                      │   │
│  │  Tienen ruta directa a internet              │   │
│  │  Aquí viven: Load Balancers (las "puertas")  │   │
│  └──────────────────────┬───────────────────────┘   │
│                         │                           │
│                    NAT Gateway                       │
│              (permite SALIR a internet               │
│               SIN ser accesible DESDE internet)      │
│                         │                           │
│  ┌──────────────────────┴───────────────────────┐   │
│  │         SUBNETS PRIVADAS                      │   │
│  │  NO tienen ruta directa a internet           │   │
│  │  Aquí viven: Todos tus pods (más seguro)     │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**¿Por qué los pods van en subnets PRIVADAS?** Porque no quieres que nadie de
internet pueda llegar directamente a tus aplicaciones. El tráfico debe pasar
por el Load Balancer (que filtra y controla el acceso).

**¿Qué es el NAT Gateway?** Los pods necesitan salir a internet para descargar
imágenes Docker, pero NO deben ser accesibles DESDE internet. El NAT permite
exactamente eso: salida sí, entrada no. Como un proxy de salida.

### Crear la VPC

1. **VPC** → **Create VPC** → **VPC and more**
2. Configurar:

| Campo | Valor | Por qué |
|-------|-------|---------|
| Name tag | `platform-lab` | Prefijo para todos los recursos de la VPC |
| IPv4 CIDR | `10.0.0.0/16` | 65,536 IPs disponibles (más que suficiente) |
| Number of AZs | **2** | Alta disponibilidad: si una AZ se cae, la otra sigue |
| Public subnets | **2** | Una por AZ, para Load Balancers |
| Private subnets | **2** | Una por AZ, para tus pods |
| NAT gateways | **In 1 AZ** | Suficiente para un lab ($0.045/hr c/u) |
| VPC endpoints | **None** | No necesitamos para este lab |

3. **Create VPC** (~1-2 min)

> **¿Por qué 2 AZs?** AZ = Availability Zone. Son datacenters físicamente
> separados dentro de una región. Si usas 2 AZs, tu aplicación sobrevive
> aunque un datacenter completo se caiga. En producción se usan 3, pero 2
> es suficiente para un lab y más barato.

> **¿Por qué "In 1 AZ" para NAT?** Cada NAT cuesta $0.045/hr (~$33/mes).
> Con 1 es suficiente para un lab. Si esa AZ se cae, los pods pierden internet
> temporalmente, pero para aprender no importa.

---

## Paso 3: Crear Cluster EKS

1. **EKS** → **Add cluster** → **Create**
2. Seleccionar: **Configuración personalizada**
3. **Desactivar "Utilizar el modo automático de EKS"** ❌

> **¿Qué es Auto Mode?** Es un modo donde AWS gestiona todo: nodos, escalado,
> load balancers, storage. Es más simple pero cuesta ~12% más. Nosotros usamos
> Fargate para aprender cómo funciona el modelo clásico. Si ya hiciste el lab
> de Auto Mode, sabes la diferencia.

4. Configurar cada campo:

| Campo | Valor | Por qué |
|-------|-------|---------|
| Nombre | `platform-lab-cluster` | Identificador del cluster |
| Rol del cluster | `platform-lab-cluster-role` | El rol que creaste en Paso 1 |
| Versión Kubernetes | **1.36** (la más reciente) | Siempre usar la última estable |
| Política de actualización | **Soporte estándar** | Gratis (el extendido cuesta extra) |
| Nivel de escalado | **NO activar** | No lo necesitamos para un lab |
| Acceso administrador | **Permitir** | Para que tu usuario pueda gestionar el cluster |
| Modo de autenticación | **API de EKS** | El modo moderno (no ConfigMap) |
| Cifrado de sobre | **NO** | Agrega complejidad, no necesario para lab |
| Cambio de zona ARC | **Desactivado** | Feature avanzada, no la necesitamos |
| Protección contra eliminaciones | **NO** | Queremos poder destruir el cluster fácilmente |

5. **Next** → Networking:

| Campo | Valor | Por qué |
|-------|-------|---------|
| VPC | `platform-lab-vpc` | La VPC que acabas de crear |
| Subnets | **Las 4** (2 públicas + 2 privadas) | EKS necesita acceso a ambas |
| Security groups | **Dejar vacío** | EKS crea uno automáticamente |
| Cluster endpoint access | **Público y privado** | "Público" = puedes usar kubectl desde tu PC |
| Modo de salida | **Administrado por AWS** | AWS decide el mejor path de salida |

> **¿Por qué "Público y privado"?** "Público" significa que puedes hablar con
> el API server del cluster desde internet (tu PC). "Privado" significa que los
> pods también pueden hablar con el API server internamente (más rápido).
> En producción con VPN, pondrías "Solo privado".

6. **Next** → Observability: **todo desactivado** (genera costos extra, instalaremos
   nuestro propio monitoreo en la Etapa 3)

7. **Next** → Add-ons: solo los 3 básicos deben estar seleccionados:
   - ✅ **CoreDNS** — DNS interno del cluster (para que los pods se encuentren entre sí)
   - ✅ **Amazon VPC CNI** — Asigna IPs de la VPC a cada pod
   - ✅ **kube-proxy** — Reglas de red para que los Services funcionen

   **Quitar todo lo demás** si aparece seleccionado (supervisión de nodos, Pod Identity,
   DNS externo, servidor de métricas, etc.)

8. **Next** → Review → **Create**

⏱️ **Tarda ~10-12 minutos en quedar Active.** Ve por un café. ☕

### ¿Qué son esos 3 Add-ons?

| Add-on | Qué hace | Analogía |
|--------|----------|----------|
| **CoreDNS** | Traduce nombres a IPs dentro del cluster | Como Google DNS (8.8.8.8) pero solo para el cluster |
| **VPC CNI** | Le da una IP real de tu VPC a cada pod | Cada pod tiene su propia "dirección" en tu red |
| **kube-proxy** | Mantiene las reglas de red de los Services | Como un router que sabe a qué pod mandar el tráfico |

Sin estos 3, el cluster arranca pero no funciona (los pods no se pueden comunicar).

---

## Paso 4: Dar acceso al cluster

Si tu usuario de la consola web es diferente al de tu CLI
(o si usas un usuario IAM para la CLI), necesitas crear un Access Entry.

1. **EKS** → `platform-lab-cluster` → **Access**
2. **Create access entry**
3. IAM principal: selecciona tu usuario de CLI

   > Para saber cuál es tu usuario de CLI:
   > ```powershell
   > aws sts get-caller-identity
   > ```
   > El ARN que muestra es el que debes seleccionar.

4. Policy: **`AmazonEKSClusterAdminPolicy`**

   > ⚠️ **NO confundir con `AmazonEKSAdminPolicy`** (sin "Cluster").
   > | Policy | Permisos |
   > |--------|----------|
   > | `AmazonEKSAdminPolicy` | Admin de namespaces, pero NO puede crear namespaces |
   > | `AmazonEKSClusterAdminPolicy` | Acceso total (equivale a `system:masters`) |

5. Scope: **Cluster**
6. **Create**

---

## Paso 5: Crear Fargate Profiles

### ¿Qué es un Fargate Profile?

Es una **regla** que dice: "todos los pods que se creen en el namespace X,
córrelos en Fargate". Sin un profile que matchee el namespace de tu pod,
el pod se queda en `Pending` para siempre (Kubernetes no sabe dónde ponerlo).

### ¿Por qué tantos profiles?

Necesitamos **6 profiles**, uno para cada namespace que usaremos en las 5 etapas:

| Profile | Namespace(s) | Para qué (etapa) |
|---------|-------------|-------------------|
| `fp-system` | `kube-system` | CoreDNS y componentes del sistema (Etapa 1) |
| `fp-ingress` | `ingress-nginx`, `cert-manager` | Ingress Controller y certificados (Etapa 2) |
| `fp-monitoring` | `monitoring` | Prometheus y Grafana (Etapa 3) |
| `fp-argocd` | `argocd` | ArgoCD para GitOps (Etapa 4) |
| `fp-datadog` | `datadog` | Datadog Agent (Etapa 5) |
| `fp-apps` | `apps` | Tus aplicaciones de prueba (todas las etapas) |

> **¿Por qué no un solo profile con todos los namespaces?**
> Fargate no soporta wildcards (namespace = `*`). Cada namespace debe estar
> explícito en un selector. Además, tener profiles separados te permite
> borrar uno sin afectar los demás. Crear un profile es gratis (no cuesta nada).

### Crear cada profile

**EKS** → `platform-lab-cluster` → **Compute** → **Fargate Profiles** → **Add**

> ⚠️ **IMPORTANTE:** Fargate solo permite crear UN profile a la vez. Debes esperar
> a que el anterior termine de crearse (~1-2 min) antes de crear el siguiente.
> Si intentas crear dos en paralelo, da error.

#### Profile 1: fp-system
| Campo | Valor |
|-------|-------|
| Name | `fp-system` |
| Pod execution role | `platform-lab-fargate-role` |
| Subnets | Solo las 2 **privadas** |
| Pod selectors → Namespace | `kube-system` |

Click **Create** → esperar ~1-2 min a que diga "Active"

#### Profile 2: fp-ingress
| Campo | Valor |
|-------|-------|
| Name | `fp-ingress` |
| Pod execution role | `platform-lab-fargate-role` |
| Subnets | Solo las 2 **privadas** |
| Pod selectors → Namespace 1 | `ingress-nginx` |

Click **Add pod selector** para agregar el segundo namespace:

| Pod selectors → Namespace 2 | `cert-manager` |

> **Nota:** Un profile puede tener múltiples selectores. Agregamos `ingress-nginx`
> Y `cert-manager` en el mismo profile porque son del mismo "tema" (acceso web).

Click **Create** → esperar

#### Profile 3: fp-monitoring
| Campo | Valor |
|-------|-------|
| Name | `fp-monitoring` |
| Pod execution role | `platform-lab-fargate-role` |
| Subnets | Solo las 2 **privadas** |
| Pod selectors → Namespace | `monitoring` |

Click **Create** → esperar

#### Profile 4: fp-argocd
| Campo | Valor |
|-------|-------|
| Name | `fp-argocd` |
| Pod execution role | `platform-lab-fargate-role` |
| Subnets | Solo las 2 **privadas** |
| Pod selectors → Namespace | `argocd` |

Click **Create** → esperar

#### Profile 5: fp-datadog
| Campo | Valor |
|-------|-------|
| Name | `fp-datadog` |
| Pod execution role | `platform-lab-fargate-role` |
| Subnets | Solo las 2 **privadas** |
| Pod selectors → Namespace | `datadog` |

Click **Create** → esperar

#### Profile 6: fp-apps
| Campo | Valor |
|-------|-------|
| Name | `fp-apps` |
| Pod execution role | `platform-lab-fargate-role` |
| Subnets | Solo las 2 **privadas** |
| Pod selectors → Namespace | `apps` |

Click **Create** → esperar

⏱️ **Total: ~10-15 minutos para los 6 profiles.**

Al terminar, en la pestaña Compute debes ver los 6 profiles en estado "Active".

---

## Paso 6: Conectar kubectl

kubectl es la herramienta para hablar con Kubernetes desde tu terminal.
Necesita saber dónde está tu cluster. Este comando configura eso:

```powershell
aws eks update-kubeconfig --name platform-lab-cluster --region us-east-1
```

> **¿Qué hizo este comando?** Descargó un archivo de configuración y lo guardó
> en `~/.kube/config`. Ese archivo tiene:
> - La URL del cluster (a dónde enviar los comandos)
> - Cómo autenticarse (usa tu AWS CLI automáticamente)
> kubectl lee ese archivo cada vez que ejecutas un comando.

Verificar que funciona:

```powershell
kubectl cluster-info
```

Debe mostrar algo como:
```
Kubernetes control plane is running at https://XXXXX.gr7.us-east-1.eks.amazonaws.com
CoreDNS is running at https://XXXXX.gr7.us-east-1.eks.amazonaws.com/api/v1/...
```

---

## Paso 7: Verificar el cluster

### Ver namespaces

```powershell
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

### Ver pods del sistema

```powershell
kubectl get pods -n kube-system
```

Deberías ver CoreDNS corriendo:
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
```

#### Si CoreDNS está en Pending:

En algunas versiones de EKS, CoreDNS tiene una anotación que lo obliga a correr
en EC2 (no Fargate). Si ves `Pending`, reinicia el deployment:

```powershell
kubectl rollout restart deployment coredns -n kube-system
```

Esperar ~1-2 min hasta que los pods estén en Running.

### Ver nodos

```powershell
kubectl get nodes
```

Deberías ver nodos Fargate (se crean automáticamente para los pods del sistema):
```
NAME                                      STATUS   ROLES    AGE   VERSION
fargate-ip-10-0-1-xxx.ec2.internal        Ready    <none>   5m    v1.36.x
fargate-ip-10-0-2-xxx.ec2.internal        Ready    <none>   5m    v1.36.x
```

> **¿Qué son esos "nodos"?** En Fargate, cada pod corre en su propia micro-VM.
> Esas micro-VMs aparecen como "nodos" en Kubernetes, pero no son instancias EC2
> que puedas ver en la consola EC2. Son invisibles para ti — AWS las gestiona.

---

## Paso 8: Desplegar un pod de prueba

Vamos a verificar que Fargate funciona correctamente desplegando un pod simple.

```powershell
# Crear el namespace "apps" (matchea con el Fargate Profile fp-apps)
kubectl create namespace apps

# Crear un pod de nginx
kubectl run test-nginx --image=nginx:alpine -n apps

# Ver el estado (esperar ~30-60 seg por el cold start de Fargate)
kubectl get pods -n apps -w
```

> **¿Qué es `-w`?** Es `--watch`. kubectl se queda escuchando cambios en tiempo real.
> Cada vez que el pod cambia de estado, imprime una nueva línea. Para salir: `Ctrl+C`.

Verás la progresión:
```
NAME         READY   STATUS    RESTARTS   AGE
test-nginx   0/1     Pending   0          5s     ← Fargate creando la micro-VM
test-nginx   0/1     Pending   0          30s    ← Todavía creando...
test-nginx   1/1     Running   0          45s    ← ¡Listo!
```

> **¿Por qué tarda 30-60 segundos?** Es el "cold start" de Fargate. AWS crea
> una micro-VM exclusiva para tu pod (descargar imagen, configurar red, etc.)
> En EC2 nodes esto es instantáneo porque el nodo ya existe. Es el trade-off
> de Fargate: no gestionas nodos pero tienes cold start.

Eliminar el pod de prueba:
```powershell
kubectl delete pod test-nginx -n apps
```

---

## ✅ Etapa 1 completada

Si llegaste hasta aquí, tienes:
- ✅ 2 IAM roles (cluster + Fargate)
- ✅ VPC con subnets públicas y privadas en 2 AZs
- ✅ Cluster EKS corriendo Kubernetes 1.36
- ✅ 6 Fargate profiles para todos los namespaces que necesitarás
- ✅ kubectl conectado y funcionando

**Siguiente paso:** Ve a la [Etapa 2: Ingress Controller](../etapa-02-ingress-controller/README.md)

> ⚠️ **NO destruyas el cluster todavía** si vas a seguir con las otras etapas.
> Destruye solo cuando termines TODO lo que quieras hacer hoy.

---

## 🔴 Destruir todo (cuando termines TODAS las etapas del día)

> ⚠️ **IMPORTANTE:** Si instalaste cosas de las etapas 2-5 (Helm releases,
> Load Balancers, etc.), debes desinstalar ESO PRIMERO antes de borrar el cluster.
> Ver las instrucciones de destrucción de cada etapa.
>
> Si solo hiciste la Etapa 1, puedes destruir directamente:

### Ejecutar script de destrucción:

```powershell
.\destroy.ps1
```

### O hacerlo manualmente paso a paso:

```powershell
# 1. Eliminar recursos de Kubernetes
kubectl delete namespace apps 2>$null

# 2. Eliminar todos los Fargate Profiles (uno a la vez, no se pueden borrar en paralelo)
# Cada uno tarda ~1-2 minutos en eliminarse
$profiles = @("fp-apps", "fp-datadog", "fp-argocd", "fp-monitoring", "fp-ingress", "fp-system")
foreach ($profile in $profiles) {
    Write-Host "Eliminando Fargate Profile: $profile"
    aws eks delete-fargate-profile --cluster-name platform-lab-cluster --fargate-profile-name $profile --region us-east-1 | Out-Null
    aws eks wait fargate-profile-deleted --cluster-name platform-lab-cluster --fargate-profile-name $profile --region us-east-1 2>$null
    Start-Sleep -Seconds 5
}

# 3. Eliminar el cluster
Write-Host "Eliminando cluster EKS..."
aws eks delete-cluster --name platform-lab-cluster --region us-east-1 | Out-Null
aws eks wait cluster-deleted --name platform-lab-cluster --region us-east-1 2>$null

# 4. Eliminar NAT Gateway
$vpcId = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=platform-lab-vpc" --region us-east-1 --query "Vpcs[0].VpcId" --output text
$natId = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpcId" --region us-east-1 --query "NatGateways[?State!='deleted'].NatGatewayId" --output text
if ($natId -and $natId -ne "None") {
    aws ec2 delete-nat-gateway --nat-gateway-id $natId --region us-east-1 | Out-Null
    Write-Host "NAT Gateway eliminandose, esperando 60s..."
    Start-Sleep -Seconds 60
}

# 5. Liberar Elastic IP
$eipAllocId = aws ec2 describe-addresses --filters "Name=tag:Name,Values=*platform-lab*" --region us-east-1 --query "Addresses[0].AllocationId" --output text
if ($eipAllocId -and $eipAllocId -ne "None") {
    aws ec2 release-address --allocation-id $eipAllocId --region us-east-1
}

# 6. Eliminar VPC desde la consola
Write-Host "VPC: eliminala desde la consola -> VPC -> $vpcId -> Actions -> Delete VPC"

# 7. Eliminar IAM roles
aws iam detach-role-policy --role-name platform-lab-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam delete-role --role-name platform-lab-cluster-role

aws iam detach-role-policy --role-name platform-lab-fargate-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy
aws iam delete-role --role-name platform-lab-fargate-role

Write-Host "¡Listo! Solo queda borrar la VPC desde la consola."
```

---

## Errores comunes y soluciones

| Error | Causa | Solución |
|-------|-------|----------|
| Cluster creation error con el rol | Falta `AmazonEKSClusterPolicy` en el rol | Verificar la policy en IAM → Roles |
| "the server has asked for the client to provide credentials" | Tu usuario CLI no tiene acceso al cluster | Crear Access Entry (Paso 4) |
| "namespaces is forbidden" | Tienes `AmazonEKSAdminPolicy` en vez de `AmazonEKSClusterAdminPolicy` | Cambiar la policy en Access Entry |
| CoreDNS en Pending | Anotación `compute-type: ec2` | `kubectl rollout restart deployment coredns -n kube-system` |
| Pods en Pending para siempre | No hay Fargate Profile para ese namespace | Verificar que el namespace tiene un profile creado |
| "Fargate profile already being modified" | Intentaste crear 2 profiles al tiempo | Esperar a que el anterior termine (estado "Active") |
| `kubectl: connection refused` | kubeconfig no configurado | Ejecutar `aws eks update-kubeconfig` de nuevo |
| Error de VPC al crear cluster | La VPC no tiene DNS habilitado | Activar "DNS hostnames" y "DNS support" en la VPC |

---

## Conceptos que vas a necesitar en las siguientes etapas

### ¿Qué es Helm?

Helm es un **package manager para Kubernetes** (como apt-get para Ubuntu o winget
para Windows). Un "chart" de Helm es un paquete que contiene todos los archivos YAML
necesarios para instalar una aplicación compleja. Lo usarás desde la Etapa 2.

Sin Helm tendrías que crear 10-20 archivos YAML manualmente. Con Helm es un comando.

### ¿Qué es OIDC?

OIDC (OpenID Connect) es un protocolo de identidad. En EKS, permite que los pods
obtengan credenciales AWS de forma segura. Lo configurarás en la Etapa 2 cuando
instales el AWS Load Balancer Controller. Ahí te lo explico en detalle.

### ¿Qué es un Ingress?

Es una "puerta de entrada" que dirige el tráfico HTTP a diferentes servicios
basándose en la URL. Por ejemplo:
- `/grafana` → Grafana
- `/argocd` → ArgoCD
- `/` → Tu aplicación

Lo instalarás en la Etapa 2.

---

## Lecciones aprendidas

1. **Fargate es serverless pero no "sin configuración"** — necesitas crear un
   Fargate Profile para CADA namespace donde quieras correr pods. Si lo olvidas,
   los pods quedan en Pending y no sabes por qué.

2. **Los 3 add-ons son obligatorios** — sin CoreDNS, VPC CNI y kube-proxy,
   el cluster no funciona. Son como los drivers de una computadora.

3. **El cold start es real** — cada pod nuevo tarda 30-60 seg en arrancar.
   En producción esto importa para escalado rápido. Para un lab está bien.

4. **Fargate tiene limitaciones** — no soporta DaemonSets (un pod en cada nodo),
   no soporta volúmenes EBS, y el node-exporter de Prometheus no funciona.
   Veremos cómo manejarlo en las etapas 3 y 5.

5. **Crear todo desde la consola te da visibilidad** — ves exactamente qué se crea,
   dónde, y con qué configuración. Cuando después aprendas Terraform (Infrastructure
   as Code), entenderás qué está haciendo por debajo porque ya lo hiciste manualmente.
