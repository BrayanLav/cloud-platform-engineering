# Etapa 3: Observability (Prometheus + Grafana)

## Qué vamos a hacer

Instalar un stack de monitoreo completo: Prometheus recolecta métricas de todo
el cluster, Grafana las muestra en dashboards bonitos, y Alertmanager te notifica
si algo se rompe. Todo con UN solo comando de Helm.

Al terminar esta etapa vas a poder abrir `http://<TU_URL>/grafana` en tu navegador
y ver dashboards con CPU, RAM, red, pods, etc. de todo tu cluster en tiempo real.

---

## Antes de empezar

**Prerequisitos:**
- ✅ Etapa 1 completada (cluster EKS corriendo)
- ✅ Etapa 2 completada (Ingress Controller instalado)

Verifica:
```bash
kubectl get pods -n ingress-nginx
# Debe mostrar pods Running

export LB_URL=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "URL: $LB_URL"
# Debe mostrar el DNS del Load Balancer
```

**Costo adicional:**

| Recurso | Costo/hora |
|---------|-----------|
| Fargate - Prometheus (1 vCPU, 2GB) | $0.05 |
| Fargate - Grafana (0.5 vCPU, 1GB) | $0.03 |
| Fargate - Alertmanager + Operator + kube-state-metrics | $0.03 |
| EBS 10GB (datos de Prometheus) | ~$0.001 |
| **Total adicional** | **~$0.11/hr** |

> 💡 Prometheus, Grafana y Alertmanager son **100% open source y gratis**.
> Solo pagas la infraestructura donde corren (Fargate + disco).

---

## Paso 1: Entender el stack

```
kube-prometheus-stack (un solo Helm chart que instala TODO):
├── Prometheus        → Recolecta métricas cada 30 segundos de todos los pods
├── Grafana           → UI web con dashboards (lo que vas a ver en el navegador)
├── Alertmanager      → Envía alertas por email/Slack cuando algo falla
├── kube-state-metrics → Expone métricas del estado de Kubernetes (pods, deployments)
└── Prometheus Operator → Gestiona la configuración de Prometheus automáticamente
```

**¿Cómo funciona Prometheus?**
Prometheus hace "scraping": cada 30 segundos le pregunta a cada pod
"¿cuánta CPU estás usando? ¿cuánta RAM? ¿cuántos requests recibiste?"
Los pods exponen esa info en un endpoint `/metrics` (texto plano).

---

## Paso 2: Revisar los values

Abre `helm/values-prometheus.yaml`. Puntos clave:

```yaml
grafana:
  adminPassword: "DevOps2024!"  # ← CAMBIAR en producción

  grafana.ini:
    server:
      root_url: "%(protocol)s://%(domain)s/grafana"
      serve_from_sub_path: true  # Para que funcione en /grafana (no en /)
```

> **🏆 Buena práctica: Configurar subpath cuando usas Ingress compartido.**
>
> Como tenemos UN solo Load Balancer para todo, cada servicio va en un path:
> `/grafana`, `/argocd`, `/prometheus`. Hay que decirle a Grafana que su
> "root URL" incluye `/grafana`, si no los links internos se rompen.

```yaml
nodeExporter:
  enabled: false  # NO funciona en Fargate
```

> **Nota importante:** node-exporter necesita un DaemonSet (un pod en cada nodo).
> Fargate no soporta DaemonSets porque no hay "nodos" tradicionales.
> Si algún día usas EC2 nodes, habilítalo.

---

## Paso 3: Instalar el stack

```bash
# Agregar repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Crear namespace
kubectl create namespace monitoring

# Instalar (un solo comando instala Prometheus + Grafana + Alertmanager + todo)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/values-prometheus.yaml
```

Esperar ~3-5 minutos (Fargate cold start para varios pods):
```bash
kubectl get pods -n monitoring -w
```

Todos deben llegar a `Running`:
```
monitoring-grafana-xxxxx                          3/3  Running
monitoring-kube-prometheus-operator-xxxxx         1/1  Running
monitoring-kube-prometheus-prometheus-0           2/2  Running
monitoring-kube-prometheus-alertmanager-0         2/2  Running
monitoring-kube-state-metrics-xxxxx              1/1  Running
```

---

## Paso 4: Exponer Grafana por Ingress

Crear el Ingress para que Grafana sea accesible por URL pública:

```bash
kubectl apply -f manifests/grafana-ingress.yaml
```

Mira el archivo `manifests/grafana-ingress.yaml`:
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - http:
        paths:
          - path: /grafana(/|$)(.*)
            pathType: ImplementationSpecific
```

> **¿Qué hace ese rewrite-target?**
> Cuando alguien pide `/grafana/dashboards`, NGINX le quita el `/grafana`
> y le pasa solo `/dashboards` a Grafana. Sin esto, Grafana recibe
> `/grafana/dashboards` y no sabe qué hacer con eso.

---

## Paso 5: Acceder a Grafana

Abre en tu navegador:
```
http://<TU_LB_URL>/grafana
```

Credenciales:
- **Usuario:** admin
- **Password:** DevOps2024!

Si funciona, verás el dashboard de bienvenida de Grafana.

---

## Paso 6: Explorar dashboards preconfigurados

El chart viene con ~34 dashboards listos. Para verlos:

1. Menú hamburguesa (☰) → Dashboards
2. Buscar "Kubernetes" en el buscador
3. Dashboards recomendados para empezar:
   - **Kubernetes / Compute Resources / Cluster** → Vista general de CPU y RAM
   - **Kubernetes / Compute Resources / Namespace (Pods)** → Detalle por namespace
   - **Kubernetes / Networking / Cluster** → Tráfico de red
   - **CoreDNS** → DNS del cluster

---

## Paso 7: (Opcional) Acceder a Prometheus directamente

Si quieres hacer queries manuales:

```bash
kubectl apply -f manifests/prometheus-ingress.yaml
```

Acceder: `http://<TU_LB_URL>/prometheus`

Queries útiles para probar:

```promql
# Cuántos pods hay por namespace
count(kube_pod_info) by (namespace)

# Uso de CPU por pod (últimos 5 minutos)
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod)

# Memoria usada por namespace (en MB)
sum(container_memory_working_set_bytes{container!=""}) by (namespace) / 1024 / 1024

# Pods que NO están Ready
kube_pod_status_ready{condition="false"}
```

---

## ✅ Etapa 3 completada

Ahora tienes:
- ✅ Prometheus recolectando métricas de todo el cluster
- ✅ Grafana con 34 dashboards accesible por URL pública
- ✅ Alertmanager listo para configurar notificaciones
- ✅ kube-state-metrics exponiendo estado de Kubernetes

**Siguiente paso:** Ve a `etapa-04-gitops-argocd/README.md`

---

## Desinstalar (solo si quieres quitar esta etapa)

```bash
kubectl delete -f manifests/
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

---

## Errores comunes

| Error | Qué significa | Solución |
|-------|--------------|----------|
| Pods en Pending | Namespace sin Fargate profile | Verificar profile `monitoring` en etapa 1 |
| Grafana muestra "Bad Gateway" | Pod de Grafana no está Ready todavía | Esperar 1-2 min más |
| Grafana no carga en /grafana | Falta configurar subpath | Verificar `serve_from_sub_path: true` en values |
| Prometheus sin datos | Targets no están UP | Acceder a Prometheus → Status → Targets |
| Dashboards vacíos | Prometheus acaba de arrancar | Esperar 2-3 min para que recolecte datos |
