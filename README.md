# Cloud Platform Engineering

Proyecto completo de plataforma Kubernetes en AWS con EKS, Fargate, Helm y Terraform.
Diseñado como un recorrido progresivo por etapas donde cada una se construye sobre la anterior.

## 🗺️ Mapa del Proyecto

```
ETAPA 1                ETAPA 2              ETAPA 3              ETAPA 4              ETAPA 5
Cluster EKS    ──►    Ingress +     ──►    Monitoreo     ──►    GitOps        ──►    Datadog
(la base)             Acceso Web           Prometheus           ArgoCD               Enterprise
                                           Grafana
```

Cada etapa depende de la anterior. No puedes hacer la 3 sin haber hecho la 1 y 2.

## 📋 Etapas

| # | Etapa | Qué creas | Qué aprendes |
|---|-------|-----------|--------------|
| 1 | [cluster-eks](./etapa-01-cluster-eks/) | VPC + EKS + Fargate con Terraform | Terraform, EKS, Fargate, VPC, IAM, networking |
| 2 | [ingress-controller](./etapa-02-ingress-controller/) | NGINX Ingress + cert-manager | Helm, Ingress, TLS, Load Balancer, routing HTTP |
| 3 | [observability](./etapa-03-observability/) | Prometheus + Grafana + Alertmanager | Helm values, métricas, dashboards, alertas |
| 4 | [gitops-argocd](./etapa-04-gitops-argocd/) | ArgoCD + apps de ejemplo | GitOps, sync policies, rollbacks, App of Apps |
| 5 | [datadog-monitoring](./etapa-05-datadog-monitoring/) | Datadog Operator + Agent | Operators, CRDs, APM, logs centralizados |

## 💰 Costos por sesión

| Duración del lab | Costo estimado |
|-----------------|---------------|
| 2 horas (solo etapa 1) | ~$0.30 |
| 3 horas (etapas 1-3) | ~$1.00 |
| 4 horas (todas las etapas) | ~$1.50 |
| Olvidaste destruir 1 día | ~$4.00 |
| Olvidaste destruir 1 semana | ~$28.00 |

> ⚠️ **REGLA #1**: Siempre ejecuta `terraform destroy` en la etapa 1 cuando termines.
> Eso elimina TODO (cluster, VPC, NAT, Load Balancers, todo).

## 🚀 Quick Start

```bash
# Clonar
git clone https://github.com/TU_USUARIO/cloud-platform-engineering.git
cd cloud-platform-engineering

# Leer el README de la etapa 1 y seguir paso a paso
# Cada README ES la guía completa (no hay docs separados)
```

## 📖 Cómo usar este proyecto

1. Abre el `README.md` de la etapa 1
2. Léelo de arriba a abajo, ejecutando cada comando
3. Las buenas prácticas están explicadas DENTRO del flujo (busca los 🏆)
4. Cuando termines una etapa, pasa a la siguiente
5. Al final del día, destruye todo (instrucciones en cada README)

## 🛠️ Herramientas necesarias

| Herramienta | Versión mínima | Para qué |
|-------------|---------------|----------|
| AWS CLI | v2.x | Hablar con AWS |
| Terraform | >= 1.5 | Crear infraestructura (etapa 1) |
| kubectl | >= 1.28 | Hablar con Kubernetes |
| Helm | >= 3.12 | Instalar paquetes en Kubernetes (etapas 2-5) |

```bash
# Verificar que tienes todo
aws --version
terraform --version
kubectl version --client
helm version --short
```

## 📁 Estructura

```
cloud-platform-engineering/
├── etapa-01-cluster-eks/           # Terraform: VPC + EKS + Fargate
│   ├── terraform/
│   ├── docs/
│   ├── scripts/
│   └── README.md
├── etapa-02-ingress-controller/    # Helm: NGINX Ingress + cert-manager
│   ├── helm/
│   ├── manifests/
│   ├── docs/
│   └── README.md
├── etapa-03-observability/         # Helm: Prometheus + Grafana
│   ├── helm/
│   ├── dashboards/
│   ├── docs/
│   └── README.md
├── etapa-04-gitops-argocd/         # Helm: ArgoCD + GitOps
│   ├── helm/
│   ├── apps/
│   ├── manifests/
│   ├── docs/
│   └── README.md
├── etapa-05-datadog-monitoring/    # Helm: Datadog Operator
│   ├── helm/
│   ├── manifests/
│   ├── docs/
│   └── README.md
├── docs/                           # Documentación general
│   ├── 00-glosario.md
│   ├── costos.md
│   └── como-acceder-servicios.md
├── scripts/
│   ├── setup-tools.sh             # Instalar herramientas
│   └── destroy-all.sh             # Destruir TODO
├── .gitignore
└── README.md
```

## Tecnologías

- **Terraform** - Infrastructure as Code (cluster, VPC, IAM)
- **AWS EKS** - Kubernetes administrado
- **AWS Fargate** - Serverless containers (sin gestionar EC2)
- **Helm** - Package manager para Kubernetes
- **NGINX Ingress** - Reverse proxy / routing HTTP
- **cert-manager** - Certificados TLS automáticos
- **Prometheus** - Recolección de métricas
- **Grafana** - Dashboards y visualización
- **ArgoCD** - GitOps continuous delivery
- **Datadog** - Monitoreo enterprise (APM, logs, métricas)

## ✅ Buenas Prácticas Aplicadas

Este proyecto aplica buenas prácticas reales de la industria. Ver [docs/buenas-practicas.md](./docs/buenas-practicas.md) para el detalle completo.

| Área | Práctica | Por qué |
|------|----------|---------|
| Terraform | Remote state en S3 + DynamoDB | State seguro, versionado, con locking |
| Terraform | Validación de variables | Fallar rápido con mensajes claros |
| Terraform | Módulos con versión pinneada | Reproducibilidad |
| Terraform | Tags en todos los recursos | Trazabilidad y control de costos |
| Kubernetes | Labels estándar (app.kubernetes.io/*) | Compatibilidad con herramientas |
| Kubernetes | Resource requests + limits | Obligatorio en Fargate, buena práctica siempre |
| Kubernetes | Liveness + readiness probes | Auto-healing y zero-downtime |
| Kubernetes | Réplicas >= 2 | Alta disponibilidad |
| Seguridad | Secrets fuera de Git | No exponer credenciales |
| Seguridad | Encriptación del state | Proteger info sensible |
| Seguridad | Least privilege IAM | Minimizar blast radius |
