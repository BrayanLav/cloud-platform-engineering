# Etapa 5: Datadog Monitoring (Nivel Enterprise) 🐶📊

¡Hola de nuevo! En esta última etapa de nuestro laboratorio, vamos a explorar **Datadog**, una plataforma comercial (de pago) que es el estándar de la industria en muchas empresas grandes para monitorización, logs y rendimiento de aplicaciones (APM).

## 📋 Resumen

En esta etapa vamos a:
1. Crear una cuenta de prueba gratuita en Datadog.
2. Aprender qué es un **Operator** y un **CRD** en Kubernetes.
3. Instalar el Datadog Operator en nuestro clúster EKS.
4. Conectar nuestro clúster EKS Fargate con Datadog.
5. Aprender cómo destruir completamente el laboratorio al finalizar.

**Estimación de Costos:**
| Servicio | Costo Estimado |
|----------|----------------|
| Datadog (Trial de 14 días) | **$0.00** (Es gratis la prueba) |
| EKS Fargate Pods | ~$0.10 por un par de horas |

---

## 🧠 Conceptos Previos

### ¿Qué es Datadog?
Datadog es una plataforma SaaS (Software as a Service) todo en uno. A diferencia de Prometheus (que es de código abierto y tú lo administras), Datadog almacena tus datos en sus servidores y te da una interfaz web hermosa y lista para usar. Ofrece métricas, logs, trazas de red y APM (Application Performance Monitoring) en un solo lugar.

### 🆚 Prometheus vs Datadog
¿Cuándo deberías usar cada uno?

| Característica | Prometheus + Grafana (Open Source) | Datadog (Enterprise) |
|----------------|------------------------------------|----------------------|
| **Costo** | Gratis (solo pagas la infraestructura donde corre) | Pago (por host/contenedor, puede ser muy costoso) |
| **Administración**| Tú mantienes los servidores, discos y actualizaciones | Ellos mantienen todo (SaaS) |
| **Setup inicial**| Medio/Complejo (requiere configurar dashboards) | Muy fácil (dashboards automáticos) |
| **Integraciones**| Buenas, pero a veces requieren trabajo manual | Excelentes, cientos de plugins oficiales |
| **Ideal para...**| Startups, empresas con presupuesto ajustado, puristas open source | Grandes empresas (Bancos, Fintech) con presupuesto que prefieren pagar para no gestionar la monitorización |

> [!NOTE] ¿Por qué aprender ambos?
> En el mercado laboral (especialmente en LATAM y Colombia), verás empresas divididas. Las startups suelen usar Prometheus, mientras que los bancos y grandes corporativos usan Datadog o Dynatrace. ¡Saber ambos te hace un perfil DevOps muy completo!

### ¿Qué es un Operator en Kubernetes? 🤖
Hasta ahora, hemos instalado aplicaciones usando Helm que crean Pods y Services. Pero, ¿qué pasa si una aplicación es muy compleja y requiere mantenimiento constante, como hacer backups o reconfigurarse sola?

Un **Operator** es como un "robot administrador" dentro de tu clúster. Es un Pod que vigila tu clúster y sabe cómo administrar una aplicación específica (en este caso, Datadog).

```text
+-------------------+       Vigila       +-----------------------+
|  Tú (Humano)      | -----------------> | Tu Clúster Kubernetes |
+-------------------+                    +-----------------------+
                                                   ^
                                                   | Administra
+-------------------+       Vigila       +-----------------------+
| Operator (Robot)  | -----------------> | Pods de Datadog       |
+-------------------+                    +-----------------------+
```

### ¿Qué es un CRD (Custom Resource Definition)?
Kubernetes trae objetos de fábrica: `Pod`, `Deployment`, `Service`. 
Un **CRD** te permite inventar tus propios objetos. Cuando instalas el Datadog Operator, él crea un nuevo CRD llamado `DatadogAgent`.

**Flujo del Operator + CRD:**
1. Tú escribes un YAML con `kind: DatadogAgent`.
2. El Operator lee ese YAML.
3. El Operator, como buen robot, crea los `Deployments` necesarios para cumplir lo que le pediste.

---

## ⚠️ CRÍTICO: Limitaciones de Fargate con Datadog

Normalmente, Datadog se instala en Kubernetes usando un **DaemonSet**. 
¿Recuerdas qué es un DaemonSet? Es un tipo de controlador que asegura que haya exactamente **un Pod corriendo en cada servidor físico/virtual (Nodo)** de tu clúster. Esto es ideal para monitorización porque ese Pod recopila las métricas de todos los demás contenedores en ese mismo servidor.

**🚨 ¡Pero nosotros estamos usando EKS Fargate!**
Fargate **NO soporta DaemonSets** (porque no tienes acceso a los Nodos/servidores subyacentes, AWS los administra por ti y cada Pod corre en su propia mini-VM aislada).

Por lo tanto:
- No podemos usar el `nodeAgent` (el agente tradicional).
- Datadog en Fargate funciona usando el patrón **Sidecar** (inyectando un contenedor de Datadog extra *dentro* del Pod de tu aplicación).
- En Fargate no hay métricas de host (CPU de la máquina real), no hay eBPF y la recolección de logs es diferente.

> [!IMPORTANT] Para este laboratorio:
> Configurar inyección automática de sidecars es un poco avanzado y costoso en recursos para un lab. Así que **solo instalaremos el Operator y el Cluster Agent**. Esto será suficiente para que Datadog lea los objetos de tu clúster (Deployments, Pods, Nodos Fargate) y los muestre en su interfaz web, pero no recolectaremos métricas profundas de las aplicaciones.
> 
> En un entorno de producción real en Fargate, sí configurarías la inyección de sidecars a través del Operator.

---

## 🛠️ Paso a Paso

### Paso 0: Crear cuenta en Datadog

1. Ve a [datadoghq.com](https://www.datadoghq.com/) y haz clic en "Free Trial".
2. Regístrate (tienes 14 días gratis, no piden tarjeta de crédito).
3. **MUY IMPORTANTE**: Cuando te pregunte la región de tus datos, selecciona **US1** (datadoghq.com). El manifiesto está configurado para esa región.
4. Al entrar, Datadog te pedirá configurar un Agente. Ignora eso por ahora y ve al menú izquierdo inferior: **Organization Settings > API Keys**.
5. Copia tu **API Key** y luego ve a **Application Keys** y crea una nueva **App Key**. Cópiala también.

### Paso 1: Crear namespace y secret

Nunca debemos guardar contraseñas o tokens en nuestros archivos YAML que subimos a Git. Usaremos un `Secret` de Kubernetes.

Abre PowerShell en tu PC y ejecuta:

```powershell
# 1. Crear el namespace (nuestro Fargate Profile lo detectará)
kubectl create namespace datadog

# 2. Crear el Secret con tus llaves (Reemplaza con tus llaves reales)
# NO guardes tus llaves reales en este README
$DATADOG_API_KEY="TU_API_KEY_AQUI"
$DATADOG_APP_KEY="TU_APP_KEY_AQUI"

kubectl create secret generic datadog-keys `
  --namespace datadog `
  --from-literal=api-key=$DATADOG_API_KEY `
  --from-literal=app-key=$DATADOG_APP_KEY
```
*Comentario:* Creamos un lugar seguro (`Secret`) llamado `datadog-keys` para que Datadog lea las credenciales sin que estén en texto plano en nuestros archivos.

### Paso 2: Instalar el Datadog Operator

Vamos a instalar al "robot administrador" usando Helm.

```powershell
# 1. Agregar el repositorio de Helm de Datadog
helm repo add datadog https://helm.datadoghq.com
helm repo update

# 2. Instalar el Operator (Fijamos la versión 2.5.0 por estabilidad en este lab)
helm install datadog-operator datadog/datadog-operator `
  --namespace datadog `
  --version 2.5.0
```
*Comentario:* Helm descarga e instala el Operator. ¡Ojo! Aún no hemos instalado Datadog, solo hemos instalado al robot que instalará Datadog por nosotros.

Verifica que el robot esté corriendo:
```powershell
kubectl get pods -n datadog
```
Deberías ver un pod llamado `datadog-operator-...` en estado `Running`.

### Paso 3: Revisar y Aplicar el DatadogAgent

Ahora le daremos instrucciones al Operator a través de nuestro CRD. Abre el archivo `manifests/datadog-agent.yaml` y revísalo.

Notarás que eliminamos por completo la sección `nodeAgent` y activamos el `clusterAgent`. Además, referenciamos nuestro secreto `datadog-keys`.

```powershell
# Aplicar el manifiesto CRD
kubectl apply -f manifests/datadog-agent.yaml
```
*Comentario:* Aquí le entregamos nuestro YAML al clúster. El Operator lo detecta y dice "¡Oh! Quieres un Cluster Agent de Datadog. ¡Yo lo creo!".

Verifica los pods:
```powershell
kubectl get pods -n datadog
```
Deberías ver aparecer un pod que empieza con `datadog-cluster-agent-...`

🏆 **Buena práctica:** Usar Operators simplifica enormemente la gestión del ciclo de vida de aplicaciones complejas. Si Datadog saca una nueva versión, solo actualizas tu YAML y el Operator se encarga del proceso de actualización de forma segura.

### Paso 4: Verificar en Datadog UI

1. Vuelve a la página web de Datadog.
2. En el menú de la izquierda, ve a **Infrastructure > Kubernetes**.
3. ¡Magia! Deberías ver aparecer tu clúster `platform-lab-cluster` 🥳.
4. Puedes explorar los Nodos (que en este caso son perfiles Fargate), los Deployments y los Pods.
5. *Nota:* Puede tardar unos 5 minutos en aparecer la información después de que el pod esté `Running`.

---

## 🐞 Errores comunes y soluciones

| Error | Causa Posible | Solución |
|-------|---------------|----------|
| El pod del Cluster Agent dice `CrashLoopBackOff` | Credenciales incorrectas en el Secret | Borra el secret, recréalo verificando que copiaste bien la API y APP key, y reinicia el pod. |
| El pod se queda en `Pending` por siempre | Problemas con Fargate Profile | Revisa si creaste el Fargate profile `fp-datadog` para el namespace `datadog` en la Etapa 1. |
| No veo datos en la web de Datadog | Región equivocada | Si creaste tu cuenta en EU (Europa) pero tu agent apunta a US, los datos no llegarán. Revisa el valor `site:` en el yaml. |
| Error `nodeAgent no es compatible` (si intentas copiar tutoriales de internet) | EKS Fargate no soporta DaemonSets | Elimina todo lo relacionado con `nodeAgent` de tu YAML. En Fargate usamos Cluster Agent + Sidecars. |

---

## 📚 Lecciones Aprendidas

1. **Enterprise vs Open Source:** Herramientas como Datadog ahorran horas de configuración de dashboards a cambio de un costo monetario.
2. **El poder de los Operators:** Los Operators extienden Kubernetes permitiendo automatizar el día a día (Día 2 operations) de herramientas complejas.
3. **El desafío de Serverless:** EKS Fargate es genial para no administrar servidores, pero rompe paradigmas clásicos como los DaemonSets. Siempre debes verificar si la herramienta de monitoreo/seguridad que quieres usar es compatible con Fargate.

---

## 🔴 DESTRUIR TODO (Final del Proyecto) 🔴

¡Has terminado el laboratorio completo! 🏆
Dado que estamos usando recursos en la nube de AWS, **es crítico limpiar todo** para evitar que te sigan cobrando por el clúster. Vamos a destruir todo en orden inverso.

Abre PowerShell en tu PC y ejecuta estos comandos con paciencia:

### 1. Eliminar Datadog y Prometheus (Etapas 4 y 5)
```powershell
# Borrar CRD de Datadog
kubectl delete -f cloud-platform-engineering/etapa-05-datadog-monitoring/manifests/datadog-agent.yaml
# Borrar Operator de Datadog
helm uninstall datadog-operator -n datadog
kubectl delete namespace datadog

# Borrar kube-prometheus-stack
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

### 2. Eliminar Ingress, Cert-Manager y Apps (Etapas 2 y 3)
```powershell
# Borrar nuestra app y namespace
kubectl delete namespace labs

# Borrar ingress-nginx
helm uninstall ingress-nginx -n ingress-nginx

# Borrar cert-manager
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
kubectl delete namespace ingress-nginx
```

### 3. Borrar el clúster de EKS (Etapa 1 - Consola de AWS)
Dado que creamos el clúster desde la consola de AWS, debemos borrarlo desde ahí:

1. Ve a la consola de AWS > **EKS** > **Clusters**.
2. Selecciona `platform-lab-cluster`.
3. En la pestaña **Compute**, selecciona todos los **Fargate Profiles** (fp-apps, fp-datadog, fp-argocd, etc.) y presiona **Delete**. *(Esto toma unos 5-10 minutos, espera a que terminen)*.
4. Una vez borrados los perfiles, ve a la esquina superior derecha y presiona **Delete cluster**. Escribe el nombre del clúster para confirmar. *(Esto toma unos 10 minutos)*.

### 4. Borrar la Red (VPC)
1. Ve a la consola de AWS > **VPC**.
2. Selecciona tu VPC `platform-lab-vpc`.
3. Haz clic en **Actions > Delete VPC**.
4. Te pedirá confirmar escribiendo "delete". Esto borrará las subredes, el Internet Gateway y la VPC al mismo tiempo.

### 5. Borrar los Roles de IAM
1. Ve a la consola de AWS > **IAM** > **Roles**.
2. Busca y borra `platform-lab-cluster-role`.
3. Busca y borra `platform-lab-fargate-role`.

> [!CAUTION] ¡Verificación Final!
> Ve a tu consola de AWS y revisa en **EKS** y **VPC** que no quede nada. Recuerda que la cuenta es tuya y los cargos extra se cobrarán a tu tarjeta. ¡Mejor revisar dos veces!

¡Felicidades por completar este viaje construyendo una plataforma Cloud Native en EKS Fargate! 🎉🚀
