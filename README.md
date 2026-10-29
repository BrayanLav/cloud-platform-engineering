# Cloud Platform Engineering — Lab Completo

Laboratorio completo de plataforma Kubernetes en AWS con EKS y Fargate.
Diseñado como un recorrido progresivo por etapas donde cada una se construye sobre la anterior.

**Todo se hace desde la consola de AWS + CLI.** No se usa Terraform — el objetivo es
que entiendas exactamente qué se crea, dónde, y por qué. Cuando después aprendas
Infrastructure as Code, entenderás qué está haciendo por debajo.

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
| 1 | [Cluster EKS](./etapa-01-cluster-eks/) | VPC + EKS + Fargate (desde consola) | EKS, Fargate, VPC, IAM, networking |
| 2 | [Ingress Controller](./etapa-02-ingress-controller/) | AWS LB Controller + NGINX Ingress + cert-manager | Helm, OIDC, IRSA, Ingress, Load Balancers |
| 3 | [Observability](./etapa-03-observability/) | Prometheus + Grafana + Alertmanager | Métricas, dashboards, alertas, PromQL |
| 4 | [GitOps - ArgoCD](./etapa-04-gitops-argocd/) | ArgoCD + apps de ejemplo | GitOps, sync automático, self-healing |
| 5 | [Datadog Monitoring](./etapa-05-datadog-monitoring/) | Datadog Operator + Cluster Agent | Operators, CRDs, monitoreo enterprise |

## 💰 Costos por sesión

| Duración del lab | Costo estimado |
|-----------------|---------------|
| 2 horas (solo etapa 1) | ~$0.31 |
| 4 horas (etapas 1-3) | ~$1.50 |
| 6 horas (todas las etapas) | ~$2.50 |
| ⚠️ Se te olvidó destruir 1 día | ~$4.00 |
| ⚠️ Se te olvidó destruir 1 semana | ~$28.00 |

> ⚠️ **REGLA #1**: Siempre destruye todo cuando termines. Ejecuta el script
> de destrucción (`destroy.ps1`) o sigue las instrucciones al final de cada etapa.

## 🚀 Quick Start

```powershell
# 1. Verifica tus herramientas
aws --version        # v2.x
kubectl version --client
eksctl version
helm version

# 2. Verifica tus credenciales
aws sts get-caller-identity

# 3. Abre el README de la etapa 1 y sigue paso a paso
```

## 📖 Cómo usar este proyecto

1. Abre el `README.md` de la **Etapa 1**
2. Léelo de arriba a abajo, ejecutando cada paso
3. Los conceptos están explicados DENTRO del flujo (no en docs separados)
4. Cuando termines una etapa, pasa a la siguiente
5. Al final del día, **destruye todo** (instrucciones en cada README)

## 🛠️ Herramientas necesarias

| Herramienta | Para qué | Cómo instalar en Windows |
|-------------|----------|--------------------------|
| AWS CLI v2 | Hablar con AWS | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| kubectl | Hablar con Kubernetes | `winget install Kubernetes.kubectl` |
| eksctl | Configurar OIDC e IAM para EKS | `winget install weaveworks.eksctl` |
| Helm v3 | Instalar paquetes en Kubernetes | `winget install Helm.Helm` |

## 📁 Estructura del proyecto

```
cloud-platform-engineering/
├── etapa-01-cluster-eks/               # Crear cluster desde la consola
│   └── README.md                       # ← Guía paso a paso
├── etapa-02-ingress-controller/        # Acceso web al cluster
│   ├── helm/                           # Archivos de configuración Helm
│   ├── manifests/                      # Archivos YAML de Kubernetes
│   └── README.md
├── etapa-03-observability/             # Prometheus + Grafana
│   ├── helm/
│   ├── manifests/
│   └── README.md
├── etapa-04-gitops-argocd/             # ArgoCD + GitOps
│   ├── apps/                           # Applications de ArgoCD
│   ├── helm/
│   ├── manifests/
│   └── README.md
├── etapa-05-datadog-monitoring/        # Datadog enterprise
│   ├── helm/
│   ├── manifests/
│   └── README.md
├── docs/
│   └── 00-glosario.md                 # Glosario de términos
├── destroy.ps1                         # Script para destruir TODO
└── README.md                           # ← Estás aquí
```

## ⚠️ Limitaciones de Fargate (importante para las etapas 3 y 5)

Fargate es serverless y muy cómodo, pero tiene limitaciones que afectan
algunas herramientas de este lab:

| Limitación | Qué afecta | Cómo lo manejamos |
|-----------|-----------|-------------------|
| No soporta DaemonSets | node-exporter (Prometheus), Datadog Agent | Deshabilitamos node-exporter; Datadog solo usa Cluster Agent |
| No soporta volúmenes EBS | Persistencia de Prometheus y Grafana | Usamos emptyDir (datos se pierden al reiniciar, OK para lab) |
| No soporta Pod Identity | Autenticación de pods con AWS | Usamos IRSA con OIDC (método clásico) |
| Cold start ~30-60s | Todos los pods | Es normal, solo esperar |

En producción con Fargate, usarías Amazon EFS para storage y Amazon Managed
Prometheus (AMP) para métricas. Para un lab de aprendizaje, las alternativas
que usamos aquí son suficientes.

## 🔴 Destruir TODO

Cuando termines **todas** las etapas del día:

```powershell
.\destroy.ps1
```

O sigue las instrucciones de destrucción dentro de cada README de etapa
(en orden inverso: 5 → 4 → 3 → 2 → 1).

## Tecnologías

| Tecnología | Qué es | Tipo |
|-----------|--------|------|
| **AWS EKS** | Kubernetes administrado | Infraestructura |
| **AWS Fargate** | Serverless containers | Compute |
| **NGINX Ingress** | Reverse proxy / routing HTTP | Networking |
| **cert-manager** | Certificados TLS automáticos | Seguridad |
| **Prometheus** | Recolección de métricas | Observabilidad |
| **Grafana** | Dashboards y visualización | Observabilidad |
| **ArgoCD** | GitOps continuous delivery | Despliegues |
| **Datadog** | Monitoreo enterprise | Observabilidad |
| **Helm** | Package manager para K8s | Herramienta |
