# Etapa 4: GitOps con ArgoCD

## Qué vamos a hacer

Instalar ArgoCD para automatizar despliegues. En vez de hacer `kubectl apply`
manualmente cada vez que cambias algo, ArgoCD vigila tu repo de Git y aplica
los cambios automáticamente cuando haces push.

Al terminar esta etapa vas a poder cambiar un archivo en GitHub, hacer push,
y ver cómo ArgoCD despliega el cambio automáticamente en tu cluster.

---

## Antes de empezar

**Prerequisitos:**
- ✅ Etapa 1 completada (cluster EKS corriendo)
- ✅ Etapa 2 completada (Ingress Controller instalado)
- ✅ Este repo subido a GitHub (ArgoCD necesita un repo de donde leer)

**Costo adicional:**

| Recurso | Costo/hora |
|---------|-----------|
| Fargate - ArgoCD Server (0.5 vCPU, 1GB) | $0.03 |
| Fargate - Repo Server (0.25 vCPU, 0.5GB) | $0.01 |
| Fargate - App Controller (0.5 vCPU, 1GB) | $0.03 |
| Fargate - Redis (0.25 vCPU, 0.5GB) | $0.01 |
| **Total adicional** | **~$0.08/hr** |

---

## Paso 1: Entender GitOps

**Sin GitOps (lo que hacías hasta ahora):**
```
Tú → kubectl apply → Cluster
       ↑
  (nadie sabe qué se desplegó, cuándo, ni por qué)
  (si algo se rompe, ¿cómo haces rollback?)
```

**Con GitOps (ArgoCD):**
```
Tú → git push → GitHub → ArgoCD detecta cambio → kubectl apply → Cluster
                              ↑
                    (todo queda en el historial de Git)
                    (rollback = git revert)
                    (code review antes de desplegar = Pull Request)
```

**Beneficios reales:**
- **Auditoría gratis:** `git log` te dice quién desplegó qué y cuándo
- **Rollback fácil:** revertir un commit = revertir un despliegue
- **Self-healing:** si alguien modifica algo manualmente en el cluster, ArgoCD lo revierte
- **Code review:** puedes requerir PR approval antes de desplegar

---

## Paso 2: Revisar los values de ArgoCD

Abre `helm/values-argocd.yaml`. Puntos clave:

```yaml
server:
  extraArgs:
    - --insecure    # Para funcionar detrás del Ingress sin TLS issues
    - --rootpath
    - /argocd       # Subpath para el Ingress compartido

configs:
  params:
    server.basehref: /argocd
    server.rootpath: /argocd
```

> **¿Por qué `--insecure`?**
> ArgoCD por defecto usa HTTPS internamente. Pero como el Ingress ya maneja
> el TLS (o no, en nuestro caso), le decimos a ArgoCD que acepte HTTP.
> En producción con dominio propio y cert-manager, quitarías esto.

---

## Paso 3: Instalar ArgoCD

```bash
# Agregar repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Crear namespace
kubectl create namespace argocd

# Instalar
helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.7.0 \
  --values helm/values-argocd.yaml

# Esperar ~2-3 min
kubectl get pods -n argocd -w
```

Pods esperados:
```
argocd-server-xxxxx                    1/1  Running
argocd-repo-server-xxxxx               1/1  Running
argocd-application-controller-0        1/1  Running
argocd-redis-xxxxx                     1/1  Running
```

---

## Paso 4: Obtener password de admin

ArgoCD genera un password aleatorio al instalarse:

```bash
export ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "Password: $ARGO_PASS"
```

Guárdalo, lo necesitas para el login.

---

## Paso 5: Exponer ArgoCD por Ingress

```bash
kubectl apply -f manifests/argocd-ingress.yaml
```

Acceder: `http://<TU_LB_URL>/argocd`

Login:
- **User:** admin
- **Password:** (el del paso 4)

---

## Paso 6: Entender qué es una "Application" en ArgoCD

Una Application es un recurso de Kubernetes (CRD) que le dice a ArgoCD:
- **Source:** De dónde leer la configuración (repo Git + carpeta)
- **Destination:** Dónde desplegar (cluster + namespace)
- **Sync Policy:** Cómo sincronizar (automático o manual)

Mira `apps/hello-gitops.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/TU_USUARIO/cloud-platform-engineering.git
    targetRevision: main
    path: etapa-04-gitops-argocd/manifests/hello-gitops  # ← carpeta con los YAMLs

  destination:
    server: https://kubernetes.default.svc  # Este mismo cluster
    namespace: apps

  syncPolicy:
    automated:
      prune: true      # Eliminar recursos que ya no están en Git
      selfHeal: true   # Revertir cambios manuales en el cluster
```

> **🏆 Buena práctica: `selfHeal: true`.**
>
> Si alguien hace `kubectl edit` y cambia algo manualmente, ArgoCD lo detecta
> y lo revierte al estado que está en Git. Esto garantiza que Git es SIEMPRE
> la fuente de verdad. Nadie puede hacer "hotfixes" que se pierden.

> **🏆 Buena práctica: `prune: true`.**
>
> Si eliminas un archivo YAML de Git, ArgoCD también elimina ese recurso
> del cluster. Sin esto, los recursos eliminados de Git quedan huérfanos
> en el cluster para siempre.

---

## Paso 7: Revisar los manifests que ArgoCD va a desplegar

Mira `manifests/hello-gitops/deployment.yaml`. Usa las mismas buenas prácticas
que aprendiste en la etapa 2:
- Labels estándar `app.kubernetes.io/*`
- Resources requests + limits
- Liveness + readiness probes
- `managed-by: argocd` (para saber que ArgoCD lo gestiona)

---

## Paso 8: Crear la Application

**IMPORTANTE:** Primero edita `apps/hello-gitops.yaml` y cambia `TU_USUARIO`
por tu usuario real de GitHub.

```bash
kubectl apply -f apps/hello-gitops.yaml
```

---

## Paso 9: Ver la sincronización en la UI

Abre ArgoCD en el navegador (`http://<TU_LB_URL>/argocd`).

Deberías ver la app "hello-gitops" con:
- **Status:** Synced (verde) → el cluster tiene lo mismo que Git
- **Health:** Healthy (verde) → los pods están Running

Click en la app para ver el árbol de recursos:
```
Application
└── Deployment (hello-gitops)
    └── ReplicaSet
        ├── Pod 1 (Running)
        └── Pod 2 (Running)
└── Service (hello-gitops)
```

---

## Paso 10: Probar GitOps (cambiar algo en Git)

Ahora viene lo bueno. Edita `manifests/hello-gitops/deployment.yaml`:

```yaml
# Cambiar esto:
  replicas: 2
# Por esto:
  replicas: 3
```

Commit y push:
```bash
git add .
git commit -m "Scale hello-gitops to 3 replicas"
git push
```

Espera ~3 minutos (ArgoCD revisa cada 3 min por defecto) o click "Refresh" en la UI.

Verifica:
```bash
kubectl get pods -n apps -l app.kubernetes.io/name=hello-gitops
# Ahora hay 3 pods!
```

**¡Eso es GitOps!** Cambiaste Git y el cluster se actualizó solo.

---

## Paso 11: Probar self-healing

Intenta hacer un cambio manual en el cluster:

```bash
# Escalar manualmente a 1 réplica
kubectl scale deployment hello-gitops -n apps --replicas=1

# Esperar 30 segundos...
kubectl get pods -n apps -l app.kubernetes.io/name=hello-gitops
# ArgoCD lo revirtió a 3 réplicas (lo que dice Git)
```

ArgoCD detectó que el cluster no coincide con Git y lo corrigió automáticamente.

---

## ✅ Etapa 4 completada

Ahora tienes:
- ✅ ArgoCD instalado y accesible por URL pública
- ✅ Una Application sincronizando desde Git
- ✅ Auto-sync funcionando (cambios en Git → cluster)
- ✅ Self-healing (cambios manuales se revierten)

**Siguiente paso:** Ve a `etapa-05-datadog-monitoring/README.md`

---

## Desinstalar

```bash
kubectl delete -f apps/
kubectl delete -f manifests/argocd-ingress.yaml
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```

---

## Errores comunes

| Error | Qué significa | Solución |
|-------|--------------|----------|
| App en "Unknown" | ArgoCD no puede clonar el repo | Verificar que el repo es público o configurar credenciales |
| App en "OutOfSync" | Hay diferencias entre Git y cluster | Click "Sync" en la UI |
| "ComparisonError" | Path no existe en el repo | Verificar que `path` en la Application es correcto |
| Pods en Pending | Namespace sin Fargate profile | Verificar profile `argocd` en etapa 1 |
