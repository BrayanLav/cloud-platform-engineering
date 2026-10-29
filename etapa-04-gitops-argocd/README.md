# Etapa 4: GitOps con ArgoCD 🐙

¡Bienvenido a la Etapa 4! Hasta ahora, has desplegado aplicaciones y herramientas en Kubernetes usando comandos manuales (`kubectl apply` o `helm install`). En esta etapa, vamos a cambiar por completo la forma en que gestionamos el clúster usando la filosofía **GitOps** y la herramienta más popular para ello: **ArgoCD**.

## 1. Resumen 📝

En esta etapa instalaremos ArgoCD en nuestro clúster y conectaremos nuestro repositorio de GitHub. A partir de ese momento, ArgoCD se encargará de leer los manifiestos de Kubernetes que estén en GitHub y aplicarlos automáticamente en el clúster.

**¿Qué vas a lograr?**
- Instalar ArgoCD vía Helm.
- Exponer la interfaz gráfica (UI) de ArgoCD usando nuestro Ingress Nginx.
- Conectar un repositorio de Git.
- Desplegar una aplicación de prueba usando una `Application` de ArgoCD.
- Experimentar la "magia" de GitOps: hacer un cambio en GitHub y ver cómo se refleja automáticamente en Kubernetes.
- Probar la capacidad de auto-reparación (*self-healing*) de ArgoCD.

### 💰 Estimación de Costos

| Recurso | Tipo / Tamaño | Costo Mensual Estimado | Notas |
|---------|---------------|------------------------|-------|
| Pods de ArgoCD | Fargate (aprox. 1.5 vCPU, 3 GB RAM en total) | ~$45.00 USD | El costo depende del uso de Fargate. |
| Tráfico de Red | Transferencia | ~$1.00 USD | Mínimo, solo sincronización de GitHub. |

> **Nota:** Estos costos se suman a los de la VPC y el clúster EKS que creamos en etapas anteriores.

---

## 2. Conceptos previos (¡Léelo, es importante!) 🧠

Si nunca has escuchado sobre GitOps o ArgoCD, esta sección es para ti.

### ¿Qué es GitOps?
GitOps es una forma de gestionar la infraestructura y las aplicaciones donde **Git es la única fuente de la verdad**. En lugar de ejecutar `kubectl apply` desde tu computadora, pones tus archivos `.yaml` en un repositorio de Git. Un sistema automatizado (como ArgoCD) observa ese repositorio y se asegura de que el clúster de Kubernetes sea siempre idéntico a lo que dice Git.

```text
[ Flujo Tradicional (Push) ]
Tú (o un CI/CD) -> Escribes YAML -> Ejecutas `kubectl apply` -> Clúster de Kubernetes

[ Flujo GitOps (Pull) ]
Tú -> Haces `git push` a GitHub
                             |
                      (ArgoCD observa) -> Detecta cambio -> Actualiza el Clúster
```

### ¿Por qué GitOps?
- **Auditoría (Audit trail):** Sabes exactamente **quién** hizo qué cambio y **cuándo**, porque todo queda en el historial de Git (commits).
- **Revisión de código:** Antes de aplicar un cambio, puedes hacer un *Pull Request* (PR) y pedirle a un compañero que revise la configuración.
- **Rollback fácil:** Si un cambio rompe el sistema, simplemente haces un `git revert` al commit anterior. ArgoCD lo detectará y restaurará el clúster a su estado funcional.
- **Seguridad:** Nadie necesita acceso directo al clúster con `kubectl`. ¡Ni siquiera tú! El único que tiene permisos para cambiar cosas es ArgoCD.

### ¿Qué es ArgoCD?
ArgoCD es una herramienta de despliegue continuo (CD) declarativa y nativa de Kubernetes que implementa la metodología GitOps. Es como un vigilante que constantemente compara lo que hay en Git (el estado deseado) con lo que hay en el clúster (el estado actual). Si hay diferencias, toma acción para sincronizarlos.

### ¿Qué es una 'Application' en ArgoCD?
Una `Application` es un concepto propio de ArgoCD. Es la forma en que le decimos: *"Oye ArgoCD, ve a este repositorio de Git (source), toma los manifiestos de esta carpeta y aplícalos en este namespace de Kubernetes (destination)"*.

### ¿Qué es un CRD?
Un **CRD (Custom Resource Definition)** es una forma de enseñarle nuevas palabras a Kubernetes. Por defecto, Kubernetes sabe qué es un `Pod`, un `Deployment` o un `Service`. Cuando instalas ArgoCD, él crea nuevos CRDs como `Application` o `AppProject`. A partir de ese momento, Kubernetes ya entiende qué es una `Application`.

### Glosario de ArgoCD: Sync, Self-heal y Prune
- **Sync (Sincronización):** Es el acto de aplicar los cambios de Git en el clúster.
- **Self-heal (Auto-reparación):** Si alguien entra al clúster y borra un Pod o modifica un Deployment manualmente (fuera de Git), ArgoCD se da cuenta y lo deshace, devolviéndolo a lo que dice Git.
- **Prune (Podar):** Si borras un archivo `.yaml` en Git, ArgoCD borrará el recurso correspondiente en el clúster.

---

## 3. Paso 1: Instalar ArgoCD ⚙️

Vamos a instalar ArgoCD usando Helm en nuestro perfil de Fargate para herramientas del sistema.

Primero, agregamos el repositorio oficial de ArgoCD:
```powershell
# Agregamos el repositorio de Argo a Helm
helm repo add argo https://argoproj.github.io/argo-helm

# Actualizamos la lista de repositorios
helm repo update
```
> **¿Por qué hacemos esto?** Helm necesita saber de dónde descargar el "paquete" (chart) de ArgoCD antes de poder instalarlo.

Creamos el namespace para ArgoCD:
```powershell
kubectl create namespace argocd
```

Ahora, instalamos ArgoCD fijando una versión específica del chart.
**ATENCIÓN**: Usaremos la versión `7.7.0` (que instala ArgoCD v2.x). Evitaremos la serie 10.x de momento porque contiene cambios arquitectónicos mayores (ArgoCD v3) que rompen algunas configuraciones.

```powershell
# Instalamos ArgoCD con Helm
helm install argocd argo/argo-cd `
  --version 7.7.0 `
  --namespace argocd `
  --values helm/values-argocd.yaml
```

> **¿Qué hace el archivo `values-argocd.yaml`?**
> Hemos preparado un archivo con configuraciones clave para nuestro clúster:
> - `--insecure`: ArgoCD por defecto usa su propio certificado TLS, pero como lo vamos a exponer detrás de nuestro Ingress Nginx (que ya maneja SSL), le decimos que hable en HTTP normal para evitar problemas de certificados internos.
> - `rootpath /argocd`: Le indica a ArgoCD que su interfaz web vivirá bajo la ruta `/argocd` de nuestro dominio.
> - `dex disabled`: Dex es un componente para iniciar sesión con Google/GitHub, etc. Lo desactivamos para ahorrar recursos en este laboratorio (usaremos el usuario administrador local).
> - `resources`: Ajustamos la memoria y CPU para que quepan bien en AWS Fargate.

Revisa que los pods se estén creando:
```powershell
# Observamos cómo se crean los pods, presiona Ctrl+C cuando estén en Running
kubectl get pods -n argocd -w
```

**Los roles de cada Pod de ArgoCD:**
- **server:** Es la interfaz web y la API que usamos.
- **repo-server:** Se encarga de clonar los repositorios de Git y generar los manifiestos.
- **controller:** El verdadero cerebro. Es el que compara continuamente Git con el clúster.
- **redis:** Guarda caché para que ArgoCD responda súper rápido.
- **application-controller:** Gestiona el estado de los CRD de tipo `Application`.

---

## 4. Paso 2: Obtener password de admin 🔑

ArgoCD genera una contraseña inicial aleatoria para el usuario `admin` y la guarda en un `Secret` de Kubernetes.

Para obtenerla en Windows (PowerShell), ejecuta:
```powershell
# Extraemos el secreto, tomamos el valor del password (que está en Base64) y lo decodificamos a texto normal
$SECRET = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($SECRET))
```
Guarda esa contraseña, la necesitarás en un momento.

---

## 5. Paso 3: Exponer ArgoCD por Ingress 🌐

Ahora vamos a crear un Ingress para poder entrar a la interfaz web de ArgoCD desde nuestro navegador.

Aplica el manifiesto de Ingress:
```powershell
# Aplicamos la configuración del Ingress en el clúster
kubectl apply -f manifests/argocd-ingress.yaml
```

**¿Qué contiene este manifiesto?**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /argocd(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
```
> **Explicación:** Este Ingress le dice a Nginx: *"Si alguien entra a la ruta `/argocd`, envíale el tráfico al servicio `argocd-server` por el puerto 80"*.

**¡Entra a probarlo!**
1. Abre tu navegador y ve a `http://tu-dominio/argocd`.
2. Usuario: `admin`
3. Contraseña: La que obtuviste en el Paso 2.

---

## 6. Paso 4: Preparar tu repositorio de Git 🐙

Para que ArgoCD funcione, necesita leer de un repositorio de Git. ¡No puede leer de los archivos locales de tu computadora!

1. Ve a [GitHub](https://github.com/) e inicia sesión.
2. Crea un nuevo repositorio público llamado `mi-lab-gitops` (o como prefieras).
3. Sube los archivos de este laboratorio a tu repositorio de GitHub. 

Si no tienes experiencia, abre una terminal en la carpeta de este laboratorio y ejecuta:
```powershell
# Inicializamos el repo
git init
# Agregamos todos los archivos
git add .
# Creamos el commit
git commit -m "Mi primer commit para GitOps"
# Preparamos la rama main
git branch -M main
# Vinculamos tu repositorio remoto
git remote add origin https://github.com/TU_USUARIO/mi-lab-gitops.git
# Subimos los cambios a GitHub
git push -u origin main
```
*(Asegúrate de reemplazar `TU_USUARIO` con tu usuario real de GitHub).*

---

## 7. Paso 5: Crear una Application en ArgoCD 🚀

Vamos a crear la conexión entre nuestro repositorio de GitHub y el clúster usando un manifiesto `Application`.

Abre el archivo `apps/hello-gitops.yaml` y edítalo:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application # <- ¡El CRD del que hablamos!
metadata:
  name: hello-gitops # Nombre de la app en ArgoCD
  namespace: argocd  # Las Applications deben vivir en el namespace argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    # ⚠️ CAMBIAR por tu repo real
    repoURL: 'https://github.com/TU_USUARIO/cloud-platform-engineering.git'
    targetRevision: main
    path: etapa-04-gitops-argocd/manifests/hello-gitops # La carpeta con los YAMLs
  destination:
    server: 'https://kubernetes.default.svc' # Clúster local
    namespace: apps # Namespace destino para tus pods
  syncPolicy:
    automated:
      prune: true       # Borra recursos del clúster si se borran de Git
      selfHeal: true    # Restaura cambios si alguien modifica el clúster manualmente
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

Aplica este manifiesto (¡Esta será la última vez que uses `kubectl apply` para una aplicación!):
```powershell
# Creamos el namespace destino si no existe
kubectl create namespace apps

# Le decimos a ArgoCD que despliegue nuestra Application
kubectl apply -f apps/hello-gitops.yaml
```

---

## 8. Paso 6: Ver la sincronización en la UI 🖥️

1. Ve a la interfaz web de ArgoCD.
2. Verás un nuevo cuadro llamado `hello-gitops`.
3. Haz clic en él. Verás un hermoso árbol de recursos.

**¿Qué significan los estados?**
- **Synced (Verde):** Git es idéntico a Kubernetes. Todo perfecto.
- **OutOfSync (Amarillo):** Hay diferencias entre Git y el clúster.
- **Healthy (Corazón Verde):** Los pods de tu aplicación están corriendo felizmente.
- **Progressing (Círculo Azul):** Se están creando o actualizando cosas.

---

## 9. Paso 7: Probar GitOps (el momento mágico) ✨

¡Veámoslo en acción!

1. En tu PC, abre el archivo `apps/hello-gitops/manifests/deployment.yaml`.
2. Busca la línea `replicas: 2` y cámbiala a `replicas: 3`.
3. Guarda, haz commit y sube el cambio:
   ```powershell
   git add .
   git commit -m "Aumentar a 3 replicas"
   git push origin main
   ```
4. Ve a ArgoCD y espera. (Revisa Git cada ~3 minutos por defecto).
5. Verás cómo cambia a `OutOfSync`, sincroniza, ¡y aparece un tercer pod!

Comprúebalo en el clúster:
```powershell
# Verás 3 pods en lugar de 2
kubectl get pods -n apps
```
> **¿Por qué es genial?** Cambiaste la infraestructura editando texto y subiéndolo a Git. No tocaste el clúster para nada.

---

## 10. Paso 8: Probar self-healing 🛡️

¿Qué pasa si alguien entra y trata de evadir los controles?
Vamos a reducir las réplicas manualmente:
```powershell
# Escalamos manualmente intentando saltarnos a ArgoCD
kubectl scale deployment hello-gitops -n apps --replicas=1
```
Ve a ArgoCD. Detectará el estado `OutOfSync`. Como pusimos `selfHeal: true`, ¡ArgoCD inmediatamente anula tu cambio manual y vuelve a escalar a 3 réplicas!

> 🏆 **Buena práctica:** Nadie debería usar `kubectl apply` en producción. Todo debe pasar por un Pull Request en Git. ArgoCD es tu guardián.

---

## 11. Paso 9: Probar rollback ⏪

Rompamos algo a propósito.

1. Edita el `deployment.yaml` cambiando la imagen a: `image: nginx:ESTO_NO_EXISTE`.
2. Súbelo a GitHub (`git add`, `commit`, `push`).
3. ArgoCD intentará aplicarlo y los Pods darán error (`ImagePullBackOff`).

**Cómo hacer rollback:**
- **Vía GitOps (Recomendado):** Haz un `git revert` de tu último commit y un `git push`. ArgoCD verá la corrección y sanará el clúster.
- **Vía UI (Emergencia):** En ArgoCD, haz clic en `HISTORY AND ROLLBACK`, elige la versión que funcionaba y haz clic en `Rollback`. (Esto pausa temporalmente el auto-sync para que puedas arreglar Git).

---

## 12. Errores comunes y soluciones 🚑

| Problema | Causa probable | Solución |
|----------|----------------|----------|
| **La app se queda en `OutOfSync`** | Auto-sync apagado | Revisa tu manifiesto de la `Application` y asegúrate de tener el bloque `syncPolicy.automated`. |
| **ArgoCD no lee mi repo privado** | Faltan credenciales | Ve a Settings > Repositories en ArgoCD y añade tu URL con un Personal Access Token de GitHub. |
| **Pods no inician en Fargate** | Fargate no soporta volúmenes EBS | El `values-argocd.yaml` proporcionado usa `emptyDir`/EFS. Si te falta el archivo, ArgoCD no arrancará. |
| **Error de acceso a la UI** | Falla del Ingress | Asegúrate de que `--insecure` está configurado para que ArgoCD hable HTTP tras el Nginx. |

---

## 13. Desinstalar 🧹

Si deseas limpiar este laboratorio:

```powershell
# Borramos la Application (su prune=true borrará los recursos)
kubectl delete -f apps/hello-gitops.yaml

# Desinstalamos ArgoCD
helm uninstall argocd -n argocd

# Borramos namespaces
kubectl delete namespace apps
kubectl delete namespace argocd
```

---

## 14. Lecciones aprendidas 🎓

1. **Git es el rey:** Con GitOps, el estado deseado siempre vive en el repositorio y es tu única fuente de la verdad.
2. **ArgoCD es el conciliador:** Su único trabajo es comparar Git con Kubernetes y forzar que sean idénticos.
3. **Seguridad por diseño:** Al quitar los permisos manuales, el clúster está a salvo de errores humanos en la consola.
4. **Resiliencia:** El *self-healing* evita cambios manuales no autorizados, dándote control absoluto de lo que corre en producción.
