# Etapa 2: Ingress Controller + TLS

## Qué vamos a hacer

Instalar NGINX Ingress Controller para poder acceder a los servicios del cluster
desde un navegador web. AWS te da una URL pública automáticamente (sin comprar dominio).

Al terminar esta etapa vas a poder abrir un navegador, pegar una URL de AWS,
y ver tus aplicaciones corriendo en Kubernetes.

---

## Antes de empezar

**Prerequisito:** Etapa 1 completada (cluster EKS corriendo).

Verifica:
```bash
kubectl get nodes
# Debe mostrar nodos Fargate
```

**Costo adicional de esta etapa:**

| Recurso | Costo/hora |
|---------|-----------|
| Fargate - NGINX Ingress (2 pods) | $0.06 |
| Fargate - cert-manager (3 pods) | $0.03 |
| AWS NLB (Load Balancer) | $0.023 |
| **Total adicional** | **~$0.11/hr** |

---

## Paso 1: Entender qué es un Ingress Controller

Sin Ingress Controller, la única forma de ver algo en tu cluster es con `port-forward`
(un túnel temporal que se cae cuando cierras el terminal).

Con Ingress Controller:
```
Internet → AWS Load Balancer → NGINX Ingress → Tu servicio → Tu pod
           (URL pública)       (routing)
```

AWS te da una URL tipo `a1b2c3d4.elb.us-east-1.amazonaws.com`.
Cualquier persona con esa URL puede acceder (desde cualquier navegador o celular).

**¿Por qué NGINX y no otro?** NGINX Ingress es el más usado en la industria,
tiene la mejor documentación y es el que vas a encontrar en ofertas laborales.

---

## Paso 2: Entender qué es Helm

Helm es como `apt-get` o `yum` pero para Kubernetes. En vez de escribir
50 archivos YAML a mano, instalas un "chart" (paquete) con un comando:

```bash
helm install <nombre> <chart> --values <configuración>
```

Un chart contiene templates de Kubernetes (Deployments, Services, etc.)
con valores configurables. Tú le pasas un archivo `values.yaml` con tu
configuración específica.

> **🏆 Buena práctica: Siempre usar un archivo de values propio.**
>
> Nunca instalar un chart sin `--values`. Los defaults del chart son genéricos
> y no están optimizados para tu caso. Siempre crea tu propio `values.yaml`
> donde defines recursos, réplicas, configuración específica, etc.

---

## Paso 3: Revisar los values de NGINX Ingress

Abre `helm/values-ingress-nginx.yaml` y lee los comentarios. Puntos clave:

```yaml
controller:
  replicaCount: 2  # Siempre >= 2 para alta disponibilidad

  service:
    annotations:
      # Esto le dice a AWS: "crea un Network Load Balancer internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
```

> **🏆 Buena práctica: Réplicas >= 2 para servicios críticos.**
>
> Si el Ingress Controller tiene 1 sola réplica y se muere (o Fargate lo recicla),
> TODO tu tráfico se cae hasta que se levante otro (~30-60 seg de cold start).
> Con 2 réplicas, si una muere la otra sigue atendiendo.

> **🏆 Buena práctica: Definir resources (CPU/RAM) en cada componente.**
>
> En Fargate es OBLIGATORIO (Fargate cobra por los resources que declaras).
> Pero incluso en EC2 nodes es buena práctica: evita que un pod se coma
> toda la RAM del nodo y mate a los demás.

---

## Paso 4: Instalar NGINX Ingress Controller

```bash
# Agregar el repositorio de Helm (como agregar un PPA en Ubuntu)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Crear namespace
kubectl create namespace ingress-nginx

# Instalar
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values helm/values-ingress-nginx.yaml
```

Esperar ~2-3 minutos:
```bash
kubectl get pods -n ingress-nginx -w
```

Cuando veas `1/1 Running`, está listo.

---

## Paso 5: Obtener tu URL pública

AWS tarda ~2 minutos en crear el Load Balancer y asignarle un DNS:

```bash
# Ver el servicio
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Cuando la columna `EXTERNAL-IP` muestre un DNS (no `<pending>`):

```bash
# Guardar la URL en una variable
export LB_URL=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Tu URL pública: http://$LB_URL"
```

Esa URL es accesible desde cualquier navegador del mundo.
Si la abres ahora, verás un error 404 (porque no hay nada desplegado todavía).

---

## Paso 6: Desplegar una app de prueba

Mira el archivo `manifests/hello-app.yaml`. Tiene un Deployment y un Service.

Puntos importantes del manifest:

```yaml
labels:
  app.kubernetes.io/name: hello-app        # Label estándar de Kubernetes
  app.kubernetes.io/component: web
  app.kubernetes.io/part-of: cloud-platform
```

> **🏆 Buena práctica: Usar labels estándar `app.kubernetes.io/*`.**
>
> Kubernetes recomienda estas labels. Herramientas como Grafana, ArgoCD,
> Lens y kubectl las entienden automáticamente. Si inventas tus propias
> labels (`app: mi-app`), funcionan pero pierdes compatibilidad.
>
> Labels principales:
> - `app.kubernetes.io/name` → nombre de la app
> - `app.kubernetes.io/component` → web, api, worker, db
> - `app.kubernetes.io/part-of` → sistema al que pertenece
> - `app.kubernetes.io/managed-by` → quién lo gestiona (helm, argocd, kubectl)

```yaml
resources:
  requests:
    cpu: 50m       # Mínimo garantizado
    memory: 64Mi
  limits:
    cpu: 100m      # Máximo permitido
    memory: 128Mi
```

> **🏆 Buena práctica: SIEMPRE definir resources requests y limits.**
>
> - `requests` = lo mínimo que el pod necesita. Kubernetes usa esto para
>   decidir dónde ponerlo. Fargate cobra por esto.
> - `limits` = el máximo. Si el pod intenta usar más RAM, Kubernetes lo mata
>   (OOMKilled). Si intenta usar más CPU, lo throttlea (va más lento).
>
> Regla general: limits = 2x requests.

```yaml
livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 3
  periodSeconds: 5
```

> **🏆 Buena práctica: Siempre definir probes de salud.**
>
> - `livenessProbe`: "¿Estás vivo?" Si falla 3 veces, Kubernetes reinicia el pod.
>   Útil para apps que se cuelgan (deadlock, memory leak).
> - `readinessProbe`: "¿Estás listo para recibir tráfico?" Si falla, Kubernetes
>   deja de enviarle requests (pero no lo mata). Útil durante el arranque.
>
> Sin probes, Kubernetes no sabe si tu app está muerta o viva.

Ahora despliega:

```bash
# Crear namespace apps (si no existe)
kubectl create namespace apps 2>/dev/null || true

# Desplegar la app
kubectl apply -f manifests/hello-app.yaml

# Esperar a que esté lista
kubectl get pods -n apps -w
# Esperar hasta ver: 1/1 Running
```

---

## Paso 7: Crear el Ingress (regla de routing)

El Ingress le dice a NGINX: "cuando llegue tráfico a `/`, mándalo al servicio `hello-app`".

Mira `manifests/hello-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-app
  namespace: apps
  annotations:
    kubernetes.io/ingress.class: nginx  # Usar NGINX como controller
spec:
  rules:
    - http:  # Sin "host" = acepta cualquier dominio (perfecto para DNS de AWS)
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello-app
                port:
                  number: 80
```

Aplicar:
```bash
kubectl apply -f manifests/hello-ingress.yaml
```

---

## Paso 8: Probar acceso desde el navegador

Espera ~30 segundos y luego:

```bash
curl http://$LB_URL
```

Debe responder:
```
Hola desde EKS! La plataforma funciona. 🚀
```

**¡También puedes abrir esa URL en tu navegador o celular!**

---

## Paso 9: Instalar cert-manager (para HTTPS)

cert-manager gestiona certificados TLS automáticamente. Aunque no tengas dominio
propio, lo instalamos porque en la etapa 3 Grafana puede usarlo.

```bash
# Agregar repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Crear namespace
kubectl create namespace cert-manager

# Instalar
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --values helm/values-cert-manager.yaml

# Verificar (3 pods deben estar Running)
kubectl get pods -n cert-manager
```

Crear el ClusterIssuer self-signed (para labs sin dominio):
```bash
kubectl apply -f manifests/cluster-issuer-selfsigned.yaml
```

> **¿Qué es un ClusterIssuer?**
> Le dice a cert-manager de dónde obtener certificados. `selfsigned` genera
> certificados que funcionan pero el browser muestra advertencia de "no seguro".
> Cuando compres un dominio, cambias a Let's Encrypt (gratis y válido).

---

## ✅ Etapa 2 completada

Ahora tienes:
- ✅ NGINX Ingress Controller con 2 réplicas
- ✅ Load Balancer con URL pública de AWS
- ✅ App de prueba accesible desde cualquier navegador
- ✅ cert-manager listo para gestionar certificados
- ✅ Routing por path funcionando

**Siguiente paso:** Ve a `etapa-03-observability/README.md`

En la siguiente etapa instalarás Prometheus y Grafana, y podrás acceder
a Grafana directamente por `http://<TU_URL>/grafana` gracias al Ingress
que acabas de configurar.

---

## Desinstalar (solo si quieres quitar esta etapa sin destruir el cluster)

```bash
kubectl delete -f manifests/
helm uninstall cert-manager -n cert-manager
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace cert-manager ingress-nginx apps
```

---

## Errores comunes

| Error | Qué significa | Solución |
|-------|--------------|----------|
| EXTERNAL-IP en `<pending>` mucho tiempo | Fargate profile no existe para `ingress-nginx` | Verificar etapa 1 tiene el profile |
| 404 al acceder al LB | No hay Ingress resource | Aplicar `hello-ingress.yaml` |
| 503 Service Unavailable | Los pods de la app no están Ready | `kubectl get pods -n apps` y esperar |
| Pods de cert-manager en Pending | Namespace sin Fargate profile | Verificar profile para `cert-manager` |
