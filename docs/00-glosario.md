# Glosario (For Dummies)

## Kubernetes

| Término | Qué es | Analogía |
|---------|--------|----------|
| **Pod** | La unidad más pequeña. Un container (o varios) corriendo | Una cajita con tu app adentro |
| **Deployment** | Gestiona pods. "Quiero 3 copias de mi app" | Un supervisor que mantiene 3 cajitas |
| **Service** | Dirección fija para acceder a pods | Un número de teléfono que no cambia |
| **Namespace** | Organización de recursos | Carpetas en tu PC |
| **Ingress** | Reglas de routing HTTP | Un recepcionista que dirige visitantes |
| **ConfigMap** | Configuración en texto plano | Un archivo .env |
| **Secret** | Datos sensibles (passwords) | Un archivo .env pero "secreto" |
| **Helm Chart** | Paquete de Kubernetes | Un .exe instalador |
| **DaemonSet** | Un pod en CADA nodo | Un guardia en cada puerta |
| **StatefulSet** | Pods con disco persistente | Apps que guardan datos (DBs) |
| **CRD** | Tipo de recurso custom | Crear tu propio tipo de archivo |
| **Operator** | Programa que gestiona CRDs | Un robot admin |

## AWS

| Término | Qué es | Costo |
|---------|--------|-------|
| **EKS** | Kubernetes administrado por AWS | $0.10/hr |
| **Fargate** | Serverless containers (sin EC2) | $0.04/vCPU-hr |
| **VPC** | Tu red privada en AWS | Gratis |
| **Subnet** | Subdivisión de la VPC | Gratis |
| **NAT Gateway** | Permite internet saliente desde subnets privadas | $0.045/hr |
| **NLB** | Load Balancer de red (L4) | $0.023/hr |
| **IAM Role** | Permisos para recursos | Gratis |
| **Route53** | DNS administrado | $0.50/mes por zona |

## Terraform

| Término | Qué es |
|---------|--------|
| **Provider** | Plugin para hablar con AWS/Azure/GCP |
| **Module** | Código reutilizable (como una función) |
| **State** | Archivo donde Terraform recuerda qué creó |
| **Plan** | "Muéstrame qué vas a hacer" (sin hacer nada) |
| **Apply** | "Hazlo de verdad" |
| **Destroy** | "Elimina TODO" |

## Helm

| Término | Qué es |
|---------|--------|
| **Chart** | Paquete (templates + valores) |
| **Release** | Una instalación de un chart |
| **Values** | Configuración personalizada |
| **Repository** | Donde se guardan los charts |

## Comandos kubectl esenciales

```bash
kubectl get pods -n <namespace>          # Listar pods
kubectl get svc -n <namespace>           # Listar services
kubectl get all -A                       # Todo en todos los namespaces
kubectl describe pod <nombre> -n <ns>    # Detalles + eventos
kubectl logs <pod> -n <ns>               # Ver logs
kubectl logs <pod> -n <ns> -f            # Logs en tiempo real
kubectl exec -it <pod> -n <ns> -- sh     # Shell dentro del pod
kubectl port-forward svc/<svc> 8080:80 -n <ns>  # Túnel a tu laptop
kubectl delete pod <nombre> -n <ns>      # Eliminar pod
kubectl get events -n <ns> --sort-by='.lastTimestamp'  # Eventos recientes
```

## Seguridad en Kubernetes

| Término | Qué es | Por qué importa |
|---------|--------|-----------------|
| **NetworkPolicy** | Firewall entre pods/namespaces | Sin ella, cualquier pod puede hablar con cualquier otro |
| **securityContext** | Restricciones de seguridad para un pod/container | Evita que un container comprometido haga daño |
| **runAsNonRoot** | No correr el proceso como usuario root | Si explotan tu app, el atacante no tiene permisos de admin |
| **readOnlyRootFilesystem** | El container no puede escribir en su propio disco | Evita que un atacante instale malware dentro del container |
| **allowPrivilegeEscalation** | Controla si un proceso puede ganar más privilegios | false = aunque entren, no pueden escalar a root |
| **automountServiceAccountToken** | Monta un token para hablar con el API de Kubernetes | false = un pod comprometido no puede controlar el cluster |
| **RBAC** | Role-Based Access Control: quién puede hacer qué en el cluster | Principio de least privilege dentro de Kubernetes |
| **Secret** | Dato sensible encriptado en Kubernetes | Passwords, tokens, API keys. NUNCA en código |
| **ServiceAccount** | Identidad para un pod dentro del cluster | Cada pod tiene una; define qué permisos tiene |

## Vulnerabilidades famosas (para entender el contexto)

| CVE | Nombre | Qué pasó | Lección |
|-----|--------|----------|---------|
| CVE-2025-1974 | IngressNightmare | RCE sin autenticación en ingress-nginx | SIEMPRE pinnear versiones de charts |
| CVE-2026-11417 | CDK Command Injection | Inyección de comandos en NodejsFunction bundling | Mantener CDK actualizado (>= 2.245.0) |
| - | Supply chain (npm) | Paquetes maliciosos en npm roban credenciales | Usar pnpm + lockfiles + auditoría |

## Comandos de seguridad útiles

```bash
# Ver si hay NetworkPolicies en un namespace
kubectl get networkpolicy -n <namespace>

# Ver el security context de un pod
kubectl get pod <nombre> -n <ns> -o jsonpath='{.spec.containers[*].securityContext}'

# Ver si un pod tiene el service account token montado
kubectl exec <pod> -n <ns> -- ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>/dev/null

# Auditar quién tiene acceso al cluster
kubectl auth can-i --list

# Ver secrets (sin mostrar el contenido)
kubectl get secrets -A
```
