# Etapa 3: Observabilidad (Prometheus + Grafana)

¡Bienvenido a la Etapa 3! Ahora que ya tienes tus aplicaciones corriendo y puedes acceder a ellas, es momento de saber qué está pasando dentro del clúster. Si algo se rompe, ¿cómo te enteras? Si una app consume toda la memoria, ¿cómo lo ves? Para eso sirve la observabilidad.

## 1. Resumen

En esta etapa vamos a instalar el **Kube-Prometheus-Stack**, que es un paquete completo de observabilidad para Kubernetes. 

**¿Qué incluye el paquete?**
*   **Prometheus:** Recolecta métricas.
*   **Grafana:** Muestra las métricas en paneles hermosos.
*   **Alertmanager:** Envía alertas cuando algo falla.
*   **Kube-state-metrics:** Expone métricas sobre los objetos de K8s (ej: cuántos pods están corriendo).

💰 **Estimación de costos:**
| Recurso | Tipo | Costo Estimado |
|---|---|---|
| Pods en Fargate | ~4 Pods (Prometheus, Grafana, Alertmanager, Operator) | ~$0.15 - $0.20 USD / día |
| Almacenamiento | Efímero (`emptyDir`) | $0 (Gratis) |

> [!NOTE] 
> Como Fargate cobra por la memoria/CPU reservada por Pod, estos componentes de monitoreo sumarán un poco al costo de la infraestructura base.

---

## 2. Conceptos Previos

Antes de instalar cosas a lo loco, entendamos qué hace cada pieza.

### ¿Qué es la observabilidad?
En un sistema distribuido como Kubernetes, no puedes simplemente "entrar por SSH a la máquina" para ver por qué falla un proceso. La observabilidad es la capacidad de entender el estado interno de tu sistema basándote en los datos que genera externamente (métricas, logs, trazas).

### Los protagonistas de nuestra pila (stack):

*   **Prometheus:** Es una base de datos de series temporales (Time Series Database). Funciona con un modelo de **pull (rascado / scraping)**: en lugar de que las apps le envíen datos, Prometheus tiene una lista de objetivos y va periódicamente a preguntarles "¿Cómo estás? Dame tus métricas".
*   **Grafana:** Prometheus guarda los datos, pero leerlos en crudo es feo. Grafana se conecta a Prometheus y crea gráficos visuales increíbles.
*   **Alertmanager:** Se conecta a Prometheus. Si Prometheus detecta que el uso de CPU superó el 90% (según una regla que definiste), se lo dice a Alertmanager. Alertmanager agrupa, silencia y envía el mensaje por Slack, Email, PagerDuty, etc.
*   **kube-state-metrics:** Prometheus por sí solo no entiende de "Pods" o "Deployments". Kube-state-metrics habla con la API de Kubernetes y le traduce a Prometheus cuántos Pods hay, si están listos, cuántos reinicios tuvieron, etc.
*   **Prometheus Operator:** Administrar Prometheus a mano es complicado. El Operator es un controlador de Kubernetes que te permite administrar Prometheus usando recursos nativos de K8s (CRDs como `ServiceMonitor` o `PrometheusRule`). ¡Hace que configurar el monitoreo sea tan fácil como desplegar un Pod!

```text
+-----------------------+     (Rasca/Scrape)       +---------------------+
| Tus Apps y K8s Clúster| -----------------------> |     Prometheus      |
+-----------------------+                          | (Guarda las métricas|
                                                   |  en base de datos)  |
+-----------------------+                          +---------------------+
| kube-state-metrics    | ----------------------->         |        |
| (Métricas del Clúster)|                                  |        |
+-----------------------+                                  |        |
                                             (Envía Alerta)|        |(Consulta datos
                                                           v        v PromQL)
+-----------------------+                          +---------------------+
|   Slack / Email       | <----------------------- |    Alertmanager     |
+-----------------------+      (Notifica)          +---------------------+
                                                                    
                                                   +---------------------+
|    Tú (Navegador)     | <----------------------- |      Grafana        |
+-----------------------+      (Ve Dashboards)     | (Muestra Gráficos)  |
                                                   +---------------------+
```

---

## 3. ⚠️ Limitaciones CRÍTICAS de AWS Fargate (¡Lee esto!)

Nuestro clúster funciona 100% sobre AWS Fargate (Serverless). Fargate es fantástico porque no administras servidores, pero tiene limitaciones importantes para herramientas diseñadas para nodos físicos/virtuales:

1.  **NO hay DaemonSets:** Un `DaemonSet` asegura que un Pod corra en cada nodo. Fargate no tiene el concepto de "nodos" expuestos para ti. Por esto, **`node-exporter` (que lee CPU/RAM del host físico) NO FUNCIONARÁ y debemos desactivarlo**.
2.  **NO hay volúmenes EBS (Elastic Block Store):** Prometheus y Grafana normalmente usan discos EBS (como `gp2` o `gp3`) para guardar datos permanentemente. **Fargate no soporta EBS**. 
    *   *Solución de producción:* Usar Amazon EFS (Elastic File System) o Amazon Managed Prometheus (AMP).
    *   *Solución de laboratorio:* Usaremos `emptyDir` (volumen efímero en memoria/disco temporal). **Si el Pod de Prometheus se reinicia, perderás el historial de métricas.** Para aprender, esto está perfecto.

---

## 4. Paso 1: Preparar el archivo de valores (Values File)

Ya he preparado el archivo `helm/values-prometheus.yaml` con las modificaciones necesarias para que funcione en Fargate. Puedes ver el archivo creado, pero aquí te explico los cambios clave:

```yaml
# 1. Desactivamos métricas de control plane de K8s (EKS no nos da acceso a ellas)
kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false

# 2. Fargate NO soporta DaemonSets (¡Adiós node-exporter!)
nodeExporter:
  enabled: false

prometheus:
  prometheusSpec:
    # 3. Usamos emptyDir porque no tenemos EBS
    storageSpec:
      emptyDir:
        medium: ""

grafana:
  # 4. Sin persistencia por la misma razón
  persistence:
    enabled: false
  # 5. Configuración para que funcione en un subpath (/grafana) en el Ingress
  grafana.ini:
    server:
      domain: localhost
      root_url: "%(protocol)s://%(domain)s/grafana"
      serve_from_sub_path: true
```

> **¿Por qué hacemos esto?** Si instaláramos el Chart por defecto, Helm intentaría crear PersistentVolumeClaims (PVC) para EBS y los Pods se quedarían en estado `Pending` para siempre esperando discos que nunca llegarán.

---

## 5. Paso 2: Instalar kube-prometheus-stack

¡A instalar! Usaremos Helm, el gestor de paquetes de Kubernetes. Vamos a fijar la versión (`68.4.0`) para asegurar que el lab sea estable y no se rompa por actualizaciones futuras.

Abre PowerShell y ejecuta:

```powershell
# 1. Añadir el repositorio oficial de Prometheus a Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Crear un namespace dedicado para el monitoreo
kubectl create namespace monitoring

# 3. Instalar el paquete (Asegúrate de estar en la carpeta etapa-03-observability)
helm install monitoring prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --version 68.4.0 `
  -f helm/values-prometheus.yaml
```

⏳ Esto tomará un par de minutos. Puedes ver cómo se crean los pods con:
```powershell
kubectl get pods -n monitoring -w
```
*(Presiona `Ctrl+C` para salir del modo "watch" cuando todos los pods estén en `Running`)*.

---

## 6. Paso 3: Exponer Grafana a través de Ingress

Tenemos Grafana corriendo, pero está escondido dentro del clúster. Vamos a usar el Ingress Controller (que instalamos en la etapa anterior) para hacerlo accesible desde tu navegador a través de la ruta `/grafana`.

Crea el archivo o asegúrate de que exista `manifests/grafana-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: nginx
    # IMPORTANTE: nginx enviará la petición a Grafana quitando cualquier cosa antes. 
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - http:
        paths:
          - path: /grafana(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: monitoring-grafana
                port:
                  number: 80
```

Aplícalo:
```powershell
kubectl apply -f manifests/grafana-ingress.yaml
```

Busca la URL del Ingress:
```powershell
kubectl get ingress -n monitoring
```

Abre en tu navegador: `http://<URL_DEL_INGRESS>/grafana`
*   **Usuario:** `admin`
*   **Contraseña:** `admin` (la que definimos en el values.yaml).

---

## 7. Paso 4: Explorar los Dashboards

Grafana viene con docenas de dashboards (paneles) listos para usar, creados gracias a `kube-state-metrics`.

🏆 **Buena práctica:** En la lupa lateral (Search), navega por la carpeta `General` o busca por `Kubernetes`.

**Dashboards interesantes para mirar:**
1.  **Kubernetes / Compute Resources / Namespace (Pods):** Aquí verás cuánta RAM y CPU gastan tus apps (busca el namespace `default` o donde hayas desplegado tus apps).
2.  **Kubernetes / Networking / Cluster:** Tráfico de red.

> [!WARNING]
> Verás que los dashboards relacionados con los **Nodes (Nodos)** no tienen datos o muestran errores (`N/A`). ¡Esto es normal y esperado! Al desactivar `node-exporter` porque estamos en Fargate, no recolectamos datos del hardware base subyacente.

---

## 8. Paso 5: (Opcional) Acceder a Prometheus UI

Prometheus también tiene su propia interfaz web. No es bonita como Grafana, pero es la mejor para probar consultas directas al lenguaje de Prometheus, llamado **PromQL**.

Como no creamos un Ingress para Prometheus (es peligroso exponerlo al público), usaremos Port-Forward:

```powershell
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Abre `http://localhost:9090` en tu navegador.

Prueba estas consultas (cópialas en la barra de búsqueda y dale a `Execute` / `Graph`):

*   **¿Cuántos Pods hay por Namespace?**
    `count(kube_pod_info) by (namespace)`
*   **Uso total de memoria por Pod (en Megabytes):**
    `sum(container_memory_working_set_bytes{image!=""}) by (pod) / 1024 / 1024`

---

## 9. Paso 6: Entender las alertas (Alertmanager)

Prometheus ya viene con un montón de reglas de alerta por defecto. Por ejemplo, te avisará si un Pod se reinicia muchas veces (CrashLoopBackOff) o si el clúster se queda sin recursos (bueno, en Fargate esto es casi imposible porque crece infinitamente, pero K8s lo revisa).

Puedes ver las alertas configuradas desde:
1.  **Prometheus UI** -> Pestaña `Alerts`.
2.  **Grafana** -> Menú lateral de Alerting.

En un entorno real, configurarías Alertmanager (editando el archivo de values de Helm) para que cuando una alerta cambie a estado `FIRING` (Disparada), haga un *POST* a un Webhook de Slack, Discord o Microsoft Teams.

---

## 10. Errores Comunes y Soluciones

| Error / Síntoma | Posible Causa | Solución |
|---|---|---|
| Pods de prometheus o grafana en `Pending` eternamente | El clúster está esperando volúmenes EBS | Verifica que pusiste `persistence.enabled: false` y el `emptyDir` en el `values-prometheus.yaml`. Borra la instalación y vuelve a instalar. |
| Pod de `prometheus-node-exporter` falla o da error `CrashLoopBackOff` | Olvidaste desactivarlo. Fargate no soporta DaemonSets | Actualiza la release usando el archivo YAML donde pusimos `nodeExporter.enabled: false` |
| Grafana no carga estilos, solo texto roto, o redirige en bucle infinito | El subpath no está bien configurado | Revisar que la configuración de `serve_from_sub_path: true` está aplicada en el values.yaml |
| `helm install` da error de timeout | Los Pods tardaron mucho en levantar en Fargate | No te preocupes. Fargate puede tardar hasta 2-3 mins en aprovisionar la VM bajo el Pod. Revisa con `kubectl get pods -n monitoring` |

---

## 11. Desinstalar (Limpieza)

Si quieres liberar espacio/costos en Fargate, para eliminar toda la pila de observabilidad:

```powershell
# Borrar Ingress
kubectl delete -f manifests/grafana-ingress.yaml

# Borrar Prometheus Stack
helm uninstall monitoring -n monitoring

# (Opcional) Borrar los CRDs sobrantes
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com alertmanagers.monitoring.coreos.com podmonitors.monitoring.coreos.com probes.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com scrapeconfigs.monitoring.coreos.com prometheusagents.monitoring.coreos.com

# Borrar Namespace
kubectl delete namespace monitoring
```

---

## 12. Lecciones Aprendidas

1.  **Cloud-Native Observability:** Kube-Prometheus-Stack agrupa todas las piezas necesarias de forma ordenada usando Helm.
2.  **Serverless Trade-offs:** Fargate quita el dolor de cabeza de parchar nodos, pero rompe herramientas clásicas como `node-exporter` o volúmenes EBS locales. Hay que adaptar las herramientas (usar `emptyDir` y apagar DaemonSets).
3.  **PromQL:** Es el lenguaje universal para consultar métricas en entornos Kubernetes.
4.  **Ingress Paths:** Entendiste cómo usar un Ingress con reescritura de rutas (`rewrite-target`) para servir múltiples aplicaciones desde el mismo balanceador de carga.

---
🚀 **Siguiente paso:** ¡Avanza a la Etapa 4 para aprender sobre GitOps y Argo CD!
