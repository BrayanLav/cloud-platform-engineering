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
