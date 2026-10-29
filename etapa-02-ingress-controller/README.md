# Etapa 2: Ingress Controller + Acceso Web 🌐

¡Hola de nuevo! Si ya terminaste la Etapa 1, tienes un clúster de Kubernetes en AWS (EKS) funcionando perfectamente. Sin embargo, en este momento tus aplicaciones están "encerradas" dentro del clúster; nadie desde internet puede acceder a ellas. 

En esta etapa, vamos a abrir la puerta (de forma segura) para que el tráfico externo pueda llegar a tus aplicaciones usando un **Ingress Controller** y el **AWS Load Balancer Controller**.

### 💰 Estimación de Costos (Mensual)

| Recurso AWS | Uso estimado | Costo Aproximado |
|-------------|--------------|------------------|
| Network Load Balancer (NLB) | 1 balanceador (730 horas) + datos | ~$16.00 USD |
| Pods de NGINX Ingress (Fargate) | 2 réplicas (0.25 vCPU, 0.5 GB) | ~$10.00 USD |
| Pods de cert-manager (Fargate) | 1 réplica (0.25 vCPU, 0.5 GB) | ~$5.00 USD |
| **Total Estimado** | | **~$31.00 USD / mes** |

> [!NOTE] 
> Recuerda destruir los recursos cuando termines el laboratorio para evitar cobros inesperados. Al final de este documento encontrarás los comandos para desinstalar todo.

---

## 2. Conceptos previos 🧠

Antes de teclear comandos, entendamos qué vamos a instalar. No te preocupes si todo es nuevo, lo explicaremos desde cero.

### ¿Qué es un Ingress Controller?
Imagina un gran edificio de oficinas (tu clúster). Dentro hay muchas empresas (tus aplicaciones). Si un visitante (un usuario web) quiere ir a una empresa específica, no entra por cualquier ventana; entra por la puerta principal, donde hay un **recepcionista**. El visitante dice "Quiero ir a la empresa X" y el recepcionista le indica el camino exacto.

Un **Ingress Controller** es ese recepcionista. Es un pod especial en K8s que recibe todo el tráfico web externo (HTTP/HTTPS) y, usando reglas definidas (objetos "Ingress"), decide a qué aplicación interna enviarlo basándose en la URL o la ruta (ej. `midominio.com/api` va a la app de backend, `midominio.com/web` va a la app de frontend).

```text
                  Internet
                     |
              [AWS NLB (Puerta)]
                     |
       +----------------------------+
       | Ingress Controller (Pod)   | <-- "El Recepcionista"
       | "midominio.com/api" ------>|---> [App Backend]
       | "midominio.com/web" ------>|---> [App Frontend]
       +----------------------------+
```

### ¿Qué es NGINX Ingress?
Es el Ingress Controller más popular del mundo, basado en el famoso servidor web NGINX. 

> [!WARNING] 
> **Nota histórica importante:** El proyecto oficial `ingress-nginx` fue **ARCHIVADO** en marzo de 2026. Esto significa que ya no recibe nuevas características ni parches menores. Sin embargo, su última versión (el chart 4.15+ o 4.12.0+) sigue siendo súper estable, segura y se usa en miles de empresas. 
> Para **nuevos proyectos reales**, deberías evaluar alternativas modernas como:
> 1. AWS Load Balancer Controller con **Gateway API**
> 2. Envoy Gateway
> 3. NGINX Gateway Fabric

Nosotros usaremos `ingress-nginx` porque la mayoría de las empresas lo siguen utilizando y es vital que sepas cómo operarlo.

### ¿Qué es Helm?
En Linux usas `apt-get` o `yum` para instalar programas. En Windows usas `winget` o `choco`. En Kubernetes, usas **Helm**. 
Helm es el administrador de paquetes para Kubernetes. Te permite instalar aplicaciones complejas (que requieren decenas de archivos de configuración) con un solo comando. Los paquetes en Helm se llaman **Charts**.

### ¿Qué es OIDC y para qué lo necesitamos? (IRSA)
Por defecto, los Pods de Kubernetes no tienen permiso para hablar con los servicios de AWS (como crear un Balanceador de Carga). Necesitamos darles permisos.
**OIDC** (OpenID Connect) es un estándar de identidad. En K8s, usamos una técnica llamada **IRSA** (IAM Roles for Service Accounts). Funciona como un "puente de confianza" entre tu clúster de K8s y AWS IAM.

```text
[Pod de K8s] --(1. Solicita acceso con un Token JWT)--> [AWS STS]
                                                              |
                                                    (2. Valida Token vía OIDC)
                                                              |
[AWS IAM Role] <--(3. Otorga credenciales temporales)---------+
```
Con IRSA, le damos permisos a un Pod específico en lugar de a todo el clúster.

### ¿Qué es el AWS Load Balancer Controller?
Es un programa que corre en tu clúster y habla con la API de AWS. Su trabajo es escuchar cuando creas un Ingress o un Servicio tipo LoadBalancer en K8s, y automáticamente ir a AWS y crear un balanceador real (ALB o NLB) para ti. 
> **¿Por qué en Fargate?** En versiones antiguas, K8s traía este código integrado ("in-tree"). Eso ya se eliminó. Ahora necesitas instalar este controlador sí o sí, especialmente en Fargate, que no soporta muchas de las características de red tradicionales.

### Tipos de Balanceadores en AWS (Tabla comparativa)

| Tipo | Capa OSI | Uso Principal | ¿Lo usaremos hoy? |
|------|----------|---------------|-------------------|
| **ALB** (Application) | Capa 7 (HTTP/HTTPS) | Enrutamiento avanzado, reglas web, inyección de headers. | No directamente. |
| **NLB** (Network) | Capa 4 (TCP/UDP) | Ultra rápido, millones de peticiones por segundo, IPs estáticas. | **SÍ**. Para apuntarlo a NGINX. |
| **CLB** (Classic) | Capa 4/7 | Balanceador antiguo (Legacy). | NO (está obsoleto). |

---

## Paso 1: Crear el Proveedor OIDC 🔑

Vamos a decirle a AWS IAM que confíe en nuestro clúster de Kubernetes. Abre tu terminal de **PowerShell** y ejecuta:

```powershell
# Asocia el proveedor OIDC de tu clúster con tu cuenta de AWS IAM.
# Esto habilita la funcionalidad IRSA (IAM Roles for Service Accounts).
eksctl utils associate-iam-oidc-provider --cluster platform-lab-cluster --region us-east-1 --approve
```

**¿Por qué hacemos esto?**
Sin este comando, AWS bloquearía cualquier intento de un Pod de crear recursos en la nube. ¡Seguridad ante todo!

---

## Paso 2: Instalar AWS Load Balancer Controller ⚖️

El controlador necesita una política de IAM que le diga exactamente qué cosas puede crear (balanceadores, reglas, target groups).

**1. Descargamos la política oficial:**
```powershell
# Usamos Invoke-WebRequest (PowerShell) para bajar el archivo JSON con los permisos
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json" -OutFile "iam_policy.json"
```

**2. Creamos la política en AWS:**
```powershell
# Crea la política en IAM basándose en el archivo descargado
aws iam create-policy `
    --policy-name AWSLoadBalancerControllerIAMPolicy `
    --policy-document file://iam_policy.json
```
*(Copia el `Arn` que sale en la pantalla, lo usaremos en el siguiente comando).*

**3. Creamos el Service Account y el Rol de IAM:**
```powershell
# Crea la cuenta de servicio en el clúster Y el rol en AWS al mismo tiempo
# REEMPLAZA "111122223333" por tu ID de cuenta real en el ARN
eksctl create iamserviceaccount `
  --cluster=platform-lab-cluster `
  --namespace=kube-system `
  --name=aws-load-balancer-controller `
  --role-name AmazonEKSLoadBalancerControllerRole `
  --attach-policy-arn=arn:aws:iam::111122223333:policy/AWSLoadBalancerControllerIAMPolicy `
  --approve
```

**4. Instalamos el Controlador con Helm:**
```powershell
# 1. Agregamos el repositorio de EKS a Helm (donde está el paquete)
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# 2. Obtenemos el VPC ID de nuestro cluster (lo necesita el controlador)
$VPC_ID = aws eks describe-cluster --name platform-lab-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.vpcId" --output text
Write-Host "VPC ID: $VPC_ID"

# 3. Instalamos el chart
helm install aws-load-balancer-controller eks/aws-load-balancer-controller `
  -n kube-system `
  --set clusterName=platform-lab-cluster `
  --set serviceAccount.create=false `
  --set serviceAccount.name=aws-load-balancer-controller `
  --set vpcId=$VPC_ID
```

> 🏆 **Buena práctica:** Siempre usar `--version` al instalar con Helm. Si no lo haces, instalará la última disponible hoy, pero si ejecutas el script mañana, podría instalar una versión mayor que rompa todo.

Verificamos que los pods estén corriendo:
```powershell
# Deberías ver 2 pods en estado "Running"
kubectl get deployment -n kube-system aws-load-balancer-controller
```

---

## Paso 3: Instalar NGINX Ingress Controller 🚪

Ahora vamos a instalar a nuestro "Recepcionista". Le pediremos a Kubernetes que exponga este servicio hacia internet; como tenemos el AWS LB Controller instalado, esto creará automáticamente un NLB en AWS.

```powershell
# Agregamos el repositorio de NGINX a Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Creamos un namespace dedicado para mantener todo ordenado
kubectl create namespace ingress-nginx
```

Instalamos con Helm (fijando la versión a la 4.12.0 para evitar sorpresas o CVEs recientes, como IngressNightmare CVE-2025-1974 que obligaba a usar versiones parchadas).

En la carpeta `helm/` ya tienes un archivo `values-ingress-nginx.yaml` con la configuración correcta. Los puntos clave del archivo:

- **`replicaCount: 2`** — Para alta disponibilidad, queremos 2 "recepcionistas"
- **`aws-load-balancer-type: "external"`** — Le dice al AWS LB Controller que cree un NLB
- **`aws-load-balancer-nlb-target-type: "ip"`** — **Vital para Fargate**: enruta tráfico directo a las IPs de los pods
- **`aws-load-balancer-scheme: "internet-facing"`** — El NLB es accesible desde internet
- **`resources`** — **Obligatorio en Fargate**: sin esto los pods no arrancan
- **`defaultBackend`** — Un pod que responde 404 cuando la URL no matchea ningún Ingress

Y ejecutamos la instalación:
```powershell
# Instalamos usando nuestro archivo de valores
helm install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx `
  --version 4.12.0 `
  -f helm/values-ingress-nginx.yaml
```

Esperamos unos minutos y obtenemos la URL del balanceador:
```powershell
# Busca en la columna "EXTERNAL-IP". Copia esa dirección gigante (ej. k8s-nlb-123.elb.amazonaws.com)
kubectl get svc -n ingress-nginx
```

---

## Paso 4: Instalar cert-manager 🔒

Un Ingress necesita manejar tráfico HTTPS seguro. En lugar de comprar e instalar certificados a mano (lo cual es terrible), usamos **cert-manager**. Este programa automatiza la creación y renovación de certificados (por ejemplo, con Let's Encrypt).

> [!IMPORTANT]
> **RESTRICCIÓN DE FARGATE:** El puerto por defecto del webhook de cert-manager (10250) choca con el kubelet interno en Fargate. **DEBEMOS** cambiarlo al `10260`.

```powershell
# Agregamos el repositorio
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Instalamos cert-manager en su versión v1.16.2
helm install cert-manager jetstack/cert-manager `
  --namespace cert-manager `
  --create-namespace `
  --version v1.16.2 `
  --set crds.enabled=true `
  --set webhook.securePort=10260
```

Creamos un **ClusterIssuer** (el que emite los certificados). Para este laboratorio, usaremos uno "Self-Signed" (Auto-firmado):

```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```
```powershell
kubectl apply -f cluster-issuer.yaml
```

---

## Paso 5: Desplegar nuestra primera app de prueba 🚀

¡Llegó la hora de la verdad! Vamos a desplegar una pequeña aplicación web y exponerla a internet.

En la carpeta `manifests/` ya tienes los archivos necesarios:
- `hello-app.yaml` — Deployment + Service de la app
- `hello-ingress.yaml` — Regla de Ingress para exponer la app
- `cluster-issuer-selfsigned.yaml` — Emisor de certificados para el lab
- `network-policy-apps.yaml` — Reglas de firewall interno (Paso 6)

> **¿Qué contiene `hello-app.yaml`?** Un Deployment con 2 réplicas de `hashicorp/http-echo:0.2.3` 
> (una app simple que devuelve un texto). Incluye buenas prácticas que vale la pena entender:
> - **Labels estándar** (`app.kubernetes.io/name`) — Convención de K8s para identificar recursos
> - **Resource requests + limits** — **Obligatorio en Fargate** (sin esto el pod no arranca)
> - **Liveness + readiness probes** — K8s revisa periódicamente que tu app esté viva y lista
> - **Security context** — Restringe permisos del contenedor (sin escalamiento de privilegios)

Aplícalo en tu clúster:
```powershell
# Creamos el namespace apps (matchea con el Fargate Profile fp-apps)
kubectl create namespace apps

# Desplegamos la app (Deployment + Service)
kubectl apply -f manifests/hello-app.yaml

# Creamos el issuer de certificados self-signed
kubectl apply -f manifests/cluster-issuer-selfsigned.yaml

# Creamos la regla de Ingress que expone la app en /
kubectl apply -f manifests/hello-ingress.yaml

# Esperamos ~1-2 min (cold start de Fargate)
kubectl get pods -n apps -w
```

**Prueba:**
```powershell
# Obtenemos la URL del NLB
$NLB_URL = kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
Write-Host "URL: http://$NLB_URL"

# Probamos con curl
curl "http://$NLB_URL/"
```
¡Deberías ver: `Hola desde EKS! La plataforma funciona. 🎉`!

---

## Paso 6: Seguridad con NetworkPolicies 🛡️

**¿Por qué necesitamos esto?**
Por defecto, Kubernetes es como una fiesta donde todos los invitados pueden hablar entre sí libremente. Si un hacker entra a un pod (ej. frontend), puede conectarse a tu base de datos fácilmente. 
Las **NetworkPolicies** son como "cortafuegos" (Firewalls) internos que prohíben la comunicación por defecto y sólo permiten lo estrictamente necesario.

En la carpeta `manifests/` ya tienes el archivo `network-policy-apps.yaml` que hace esto:

1. **Bloquea TODO el tráfico entrante** a los pods del namespace `apps` por defecto
2. **Solo permite** tráfico desde el namespace `ingress-nginx` (para que el Ingress funcione)
3. **Permite DNS** (para que los pods resuelvan nombres)
4. **Permite salida a internet** (para APIs externas) pero **bloquea acceso a la VPC interna**
5. **Permite comunicación intra-namespace** (pods de apps entre sí)

```powershell
kubectl apply -f manifests/network-policy-apps.yaml
```

> 🏆 **Buena práctica:** En producción, SIEMPRE aplica NetworkPolicies.
> Sin ellas, un pod comprometido podría acceder a Prometheus, ArgoCD,
> o cualquier otro servicio del cluster.

---

## 🛑 Errores comunes y soluciones

| Error / Síntoma | Posible Causa | Solución |
|-----------------|---------------|----------|
| Los pods del Ingress están en estado `Pending` por siempre. | Fargate no sabe dónde colocar los pods. | Verifica que tienes un Fargate Profile creado para el namespace `ingress-nginx`. |
| El balanceador no se crea en AWS (EXTERNAL-IP dice `<pending>`). | AWS LB Controller no tiene permisos. | Verifica que creaste el ServiceAccount de IAM (IRSA) y asociaste la política correcta. |
| Cert-manager se reinicia o tira error de Webhook Timeout. | Conflicto de puerto 10250 en Fargate. | Actualiza los values de Helm: `--set webhook.securePort=10260`. |
| Error "OIDC provider already exists". | Ya corriste el comando OIDC antes. | Ignora el error, tu clúster ya tiene OIDC configurado. |

---

## 🧹 Desinstalar esta etapa

Si quieres borrar todo lo que hicimos en esta etapa (para ahorrar dinero):

```powershell
# 1. Borrar la app y las reglas
kubectl delete -f manifests/hello-ingress.yaml
kubectl delete -f manifests/hello-app.yaml
kubectl delete -f manifests/network-policy-apps.yaml
kubectl delete -f manifests/cluster-issuer-selfsigned.yaml

# 2. Desinstalar NGINX Ingress y cert-manager
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall cert-manager -n cert-manager

# 3. Desinstalar el AWS LB Controller
helm uninstall aws-load-balancer-controller -n kube-system
eksctl delete iamserviceaccount --cluster platform-lab-cluster --name aws-load-balancer-controller --namespace kube-system --region us-east-1

# 4. Borrar namespaces
kubectl delete namespace apps
kubectl delete namespace ingress-nginx
kubectl delete namespace cert-manager

# (El NLB se borrará automáticamente cuando se desinstale NGINX Ingress ~1-2 min)
```

---

## 🎓 Lecciones Aprendidas

1. **La comunicación en la nube es explícita:** K8s por sí solo no crea recursos en AWS. Necesitamos Controladores (como el AWS LB Controller) y permisos mediante identidades puente (IRSA).
2. **Fargate tiene sus propias reglas:** Hemos visto cómo Fargate nos obliga a definir siempre Recursos (requests/limits) y nos cambia los puertos de ciertas herramientas (cert-manager).
3. **Todo como código:** Un Ingress no es más que un manifiesto de texto. Si nuestro clúster muere hoy, levantaríamos la misma arquitectura mañana en 5 minutos corriendo estos mismos comandos.

¡Felicidades! Tienes tu puerta de entrada configurada. En la **Etapa 3** instalaremos **Prometheus + Grafana** para monitorear todo lo que pasa en tu clúster (CPU, memoria, pods, errores) con dashboards visuales.
