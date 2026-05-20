# Etapa 5: Datadog Monitoring (Enterprise)

## Qué vamos a hacer

Integrar Datadog con el cluster EKS. Datadog es la herramienta de monitoreo
más usada en empresas grandes. A diferencia de Prometheus (que corre dentro
de tu cluster), Datadog envía todo a su cloud y tú ves los datos en datadoghq.com.

Al terminar esta etapa vas a ver tu cluster completo en la UI de Datadog:
pods, containers, métricas, logs, todo.

---

## Antes de empezar

**Prerequisitos:**
- ✅ Etapa 1 completada (cluster EKS corriendo)
- ✅ Cuenta Datadog creada (14 días gratis con todo)

**Costo:**

| Recurso | Costo |
|---------|-------|
| **Datadog (14 días trial)** | **$0** |
| Datadog Free (después del trial) | $0 (5 hosts, 1 día retención) |
| Fargate - Operator + Agent | ~$0.03/hr |

---

## Paso 1: Crear cuenta Datadog

1. Ir a https://www.datadoghq.com/
2. Click "Get Started Free"
3. Seleccionar región: **US1** (datadoghq.com)
4. Completar registro

El trial de 14 días incluye TODAS las features (APM, Logs, Infra, etc.)

---

## Paso 2: Obtener API Keys

En la UI de Datadog:
1. Organization Settings → API Keys → "New Key" → nombre: "eks-lab" → copiar
2. Organization Settings → Application Keys → "New Key" → nombre: "eks-lab" → copiar

> **🏆 Buena práctica: Nunca poner API keys en archivos que van a Git.**
>
> Las keys se crean como Kubernetes Secrets (desde la terminal, no desde un archivo).
> El `.gitignore` ya excluye archivos `*-secret.yaml` por si acaso.

---

## Paso 3: Entender qué es un Operator

Hasta ahora instalaste cosas con Helm directamente (NGINX, Prometheus, ArgoCD).
Datadog usa un patrón diferente: **Operator**.

```
HELM CHART normal:
  helm install → crea Deployments, Services, etc.
  Si quieres cambiar algo → helm upgrade
  Helm NO vigila nada después de instalar

OPERATOR:
  helm install → instala el Operator (un programa que corre en el cluster)
  Tú creas un Custom Resource (un YAML especial tipo "DatadogAgent")
  El Operator LEE ese YAML y crea/configura todo automáticamente
  Si algo se rompe, el Operator lo arregla solo
  Si cambias el YAML, el Operator aplica los cambios
```

> **🏆 Buena práctica: Usar Operators para software complejo.**
>
> Un Operator es como tener un "admin robot" dentro del cluster que sabe
> cómo gestionar un software específico. Para cosas simples (NGINX) un
> Helm chart basta. Para cosas complejas (Datadog, bases de datos), un
> Operator es mejor porque puede hacer rolling updates, backups, etc.

**¿Qué es un CRD (Custom Resource Definition)?**

Kubernetes viene con tipos de recursos nativos: Pod, Service, Deployment, etc.
Un CRD te permite crear NUEVOS tipos. Datadog crea el tipo `DatadogAgent`.
Cuando aplicas un YAML de tipo `DatadogAgent`, el Operator lo detecta y actúa.

---

## Paso 4: Crear namespace y secret

```bash
# Crear namespace
kubectl create namespace datadog

# Crear secret con tus API keys (REEMPLAZAR con tus keys reales)
kubectl create secret generic datadog-keys \
  --namespace datadog \
  --from-literal=api-key=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX \
  --from-literal=app-key=YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

Verificar:
```bash
kubectl get secret datadog-keys -n datadog
# Debe existir
```

---

## Paso 5: Instalar el Datadog Operator

```bash
# Agregar repo
helm repo add datadog https://helm.datadoghq.com
helm repo update

# Instalar el Operator
helm install datadog-operator datadog/datadog-operator \
  --namespace datadog \
  --values helm/values-operator.yaml

# Verificar
kubectl get pods -n datadog
# datadog-operator-xxxxx  1/1  Running
```

El Operator ya está corriendo pero no hace nada todavía.
Necesita que le digas QUÉ hacer → eso es el Custom Resource.

---

## Paso 6: Revisar el DatadogAgent manifest

Abre `manifests/datadog-agent.yaml`. Este es el Custom Resource que le dice
al Operator cómo configurar Datadog:

```yaml
apiVersion: datadoghq.com/v2alpha1
kind: DatadogAgent          # ← Tipo custom (no existe en Kubernetes vanilla)
metadata:
  name: datadog
spec:
  global:
    credentials:
      apiSecret:
        secretName: datadog-keys   # ← Referencia al secret que creaste
        keyName: api-key
    tags:
      - "env:development"
      - "cluster:platform-cluster"
      - "team:devops"
```

> **🏆 Buena práctica: Tags en todo.**
>
> Los tags `env`, `cluster` y `team` aparecen en TODAS las métricas de Datadog.
> Puedes filtrar dashboards por ambiente, cluster o equipo. En una empresa
> con múltiples clusters, esto es esencial para no mezclar datos.

```yaml
  features:
    logCollection:
      enabled: true
      containerCollectAll: true  # Recolectar logs de TODOS los containers
    apm:
      enabled: true             # Application Performance Monitoring (traces)
    orchestratorExplorer:
      enabled: true             # Vista de Kubernetes en Datadog UI
```

---

## Paso 7: Aplicar el DatadogAgent

```bash
kubectl apply -f manifests/datadog-agent.yaml

# Esperar ~2 min
kubectl get pods -n datadog -w
```

Pods esperados:
```
datadog-operator-xxxxx          1/1  Running
datadog-cluster-agent-xxxxx     1/1  Running
datadog-xxxxx                   3/3  Running  (agent + trace-agent + process-agent)
```

---

## Paso 8: Verificar en Datadog UI

Espera ~5 minutos (los datos tardan en llegar) y luego:

1. **Infrastructure:** https://app.datadoghq.com/infrastructure
   - Tu cluster debe aparecer listado

2. **Kubernetes:** https://app.datadoghq.com/orchestration/overview/pod
   - Vista de todos los pods con métricas

3. **Containers:** https://app.datadoghq.com/containers
   - Containers corriendo con CPU/RAM en tiempo real

4. **Logs:** https://app.datadoghq.com/logs
   - Logs de todos los pods (si habilitaste logCollection)

---

## Paso 9: Comparar Prometheus vs Datadog

Ahora que tienes ambos, puedes comparar:

| Aspecto | Prometheus + Grafana (Etapa 3) | Datadog (Etapa 5) |
|---------|-------------------------------|-------------------|
| **Costo** | Gratis (solo infra ~$0.11/hr) | $15/host/mes (o trial gratis) |
| **Dónde corre** | Dentro de tu cluster | Cloud de Datadog |
| **Si el cluster muere** | Pierdes el monitoreo | Sigues viendo datos históricos |
| **Setup** | Más manual (values, ingress) | Más automático (operator) |
| **Retención** | Tú decides (disco) | 15 meses incluidos |
| **APM/Tracing** | Necesitas Jaeger o Tempo | Incluido |
| **Logs** | Necesitas Loki | Incluido |
| **Alertas** | Alertmanager (config YAML) | UI visual fácil |
| **Dashboards** | Grafana (muy flexible) | Preconfigurados + custom |
| **En entrevistas** | "Conozco Prometheus y Grafana" | "Conozco Datadog" |

**Conclusión:** En el mercado colombiano te van a pedir conocer ambos.
Prometheus/Grafana para empresas que no quieren pagar licencias.
Datadog para empresas grandes con presupuesto.

---

## ✅ Etapa 5 completada

Ahora tienes:
- ✅ Datadog Operator corriendo
- ✅ Agent recolectando métricas, logs y traces
- ✅ Cluster visible en Datadog UI
- ✅ Entiendes la diferencia entre Operator y Helm chart normal
- ✅ Entiendes CRDs (Custom Resource Definitions)

**🎉 ¡Completaste todas las etapas!**

---

## Desinstalar

```bash
kubectl delete -f manifests/datadog-agent.yaml
helm uninstall datadog-operator -n datadog
kubectl delete secret datadog-keys -n datadog
kubectl delete namespace datadog
```

---

## 🔴 Destruir TODO (fin del lab)

Ahora sí, destruye toda la infraestructura:

```bash
# Volver a la raíz del proyecto
cd ../../

# Usar el script de destrucción
chmod +x scripts/destroy-all.sh
./scripts/destroy-all.sh

# O manual:
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null
helm uninstall cert-manager -n cert-manager 2>/dev/null
helm uninstall monitoring -n monitoring 2>/dev/null
helm uninstall argocd -n argocd 2>/dev/null
helm uninstall datadog-operator -n datadog 2>/dev/null
sleep 30
cd etapa-01-cluster-eks/terraform/
terraform destroy -auto-approve
```

Verificar:
```bash
aws eks list-clusters --region us-east-1
# { "clusters": [] }  ← Nada corriendo, nada cobrando
```

---

## Errores comunes

| Error | Qué significa | Solución |
|-------|--------------|----------|
| "Invalid API Key" | Key incorrecta en el secret | Recrear el secret con la key correcta |
| Agent en CrashLoopBackOff | Configuración inválida | `kubectl logs <pod> -n datadog -c agent` |
| No aparece en Datadog UI | Datos tardan ~5 min | Esperar y refrescar |
| Pods en Pending | Namespace sin Fargate profile | Verificar profile `datadog` en etapa 1 |
