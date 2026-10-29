# destroy.ps1 - Elimina TODOS los recursos de TODAS las etapas del lab
# Uso: .\destroy.ps1
#
# Este script elimina todo en el orden correcto para evitar errores de
# dependencia. SIEMPRE úsalo en vez de borrar cosas manualmente.
#
# Orden de destrucción:
# 1. Recursos de Kubernetes (Services, Deployments, etc.)
# 2. Helm releases (NGINX Ingress, Prometheus, ArgoCD, Datadog, cert-manager)
# 3. Load Balancers (esperar a que AWS los elimine)
# 4. IAM Service Account y Policy del LB Controller
# 5. OIDC Provider
# 6. Fargate Profiles (uno por uno)
# 7. Cluster EKS
# 8. NAT Gateway + Elastic IP
# 9. IAM Roles
# 10. VPC (manual desde consola)

param(
    [Parameter(Mandatory=$false)]
    [string]$AccountId
)

# Obtener Account ID automáticamente si no se pasó como parámetro
if (-not $AccountId) {
    $AccountId = aws sts get-caller-identity --query "Account" --output text
    Write-Host "Account ID detectado: $AccountId" -ForegroundColor DarkGray
}

Write-Host "" 
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  ⚠️  DESTRUYENDO TODA LA INFRAESTRUCTURA DEL LAB            ║" -ForegroundColor Red
Write-Host "║  Esto elimina: EKS, VPC, Load Balancers, IAM, todo.        ║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "¿Estás seguro? Escribe 'destruir' para confirmar"
if ($confirm -ne "destruir") {
    Write-Host "Cancelado." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# ============================================================================
# PASO 1: Eliminar recursos de Kubernetes
# ============================================================================
Write-Host "[1/12] Eliminando recursos de Kubernetes..." -ForegroundColor Yellow

# Etapa 5: Datadog
kubectl delete -f etapa-05-datadog-monitoring/manifests/datadog-agent.yaml 2>$null
kubectl delete secret datadog-keys -n datadog 2>$null

# Etapa 4: ArgoCD
kubectl delete -f etapa-04-gitops-argocd/apps/ 2>$null

# Etapa 3: Observability
kubectl delete -f etapa-03-observability/manifests/ 2>$null

# Etapa 2: Ingress
kubectl delete -f etapa-02-ingress-controller/manifests/ 2>$null
kubectl delete svc ingress-nginx-controller -n ingress-nginx 2>$null

# Apps
kubectl delete namespace apps 2>$null

# ============================================================================
# PASO 2: Desinstalar Helm releases (orden inverso)
# ============================================================================
Write-Host "[2/12] Desinstalando Helm releases..." -ForegroundColor Yellow

helm uninstall datadog-operator -n datadog 2>$null
Write-Host "  → datadog-operator" -ForegroundColor DarkYellow

helm uninstall argocd -n argocd 2>$null
Write-Host "  → argocd" -ForegroundColor DarkYellow

helm uninstall monitoring -n monitoring 2>$null
Write-Host "  → monitoring (Prometheus/Grafana)" -ForegroundColor DarkYellow

helm uninstall cert-manager -n cert-manager 2>$null
Write-Host "  → cert-manager" -ForegroundColor DarkYellow

helm uninstall ingress-nginx -n ingress-nginx 2>$null
Write-Host "  → ingress-nginx" -ForegroundColor DarkYellow

helm uninstall aws-load-balancer-controller -n kube-system 2>$null
Write-Host "  → aws-load-balancer-controller" -ForegroundColor DarkYellow

# ============================================================================
# PASO 3: Esperar que AWS elimine los Load Balancers
# ============================================================================
Write-Host "[3/12] Esperando 90s para que AWS elimine los Load Balancers..." -ForegroundColor Yellow
Write-Host "  (Si no esperas, la VPC no se puede borrar después)" -ForegroundColor DarkYellow
Start-Sleep -Seconds 90

# Verificar
$lbCount = aws elbv2 describe-load-balancers --region us-east-1 --query 'length(LoadBalancers)' --output text 2>$null
if ($lbCount -and $lbCount -ne "0") {
    Write-Host "  Todavia hay $lbCount LB(s), esperando 60s más..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 60
}

# ============================================================================
# PASO 4: Eliminar IAM Service Account del LB Controller
# ============================================================================
Write-Host "[4/12] Eliminando IAM Service Account del LB Controller..." -ForegroundColor Yellow
eksctl delete iamserviceaccount --cluster=platform-lab-cluster --namespace=kube-system --name=aws-load-balancer-controller --region us-east-1 2>$null
Start-Sleep -Seconds 30

# ============================================================================
# PASO 5: Eliminar IAM Policy del LB Controller
# ============================================================================
Write-Host "[5/12] Eliminando IAM Policy del LB Controller..." -ForegroundColor Yellow
aws iam delete-policy --policy-arn "arn:aws:iam::${AccountId}:policy/AWSLoadBalancerControllerIAMPolicy" 2>$null

# ============================================================================
# PASO 6: Eliminar Fargate Profiles (uno por uno, no se pueden en paralelo)
# ============================================================================
Write-Host "[6/12] Eliminando Fargate Profiles (esto tarda ~10 min)..." -ForegroundColor Yellow

$profiles = @("fp-apps", "fp-datadog", "fp-argocd", "fp-monitoring", "fp-ingress", "fp-system")
foreach ($profile in $profiles) {
    Write-Host "  Eliminando $profile..." -ForegroundColor DarkYellow
    aws eks delete-fargate-profile --cluster-name platform-lab-cluster --fargate-profile-name $profile --region us-east-1 2>$null | Out-Null
    aws eks wait fargate-profile-deleted --cluster-name platform-lab-cluster --fargate-profile-name $profile --region us-east-1 2>$null
    if ($LASTEXITCODE -ne 0) {
        Start-Sleep -Seconds 30
    }
    Start-Sleep -Seconds 5
}

# ============================================================================
# PASO 7: Eliminar el cluster EKS
# ============================================================================
Write-Host "[7/12] Eliminando cluster EKS..." -ForegroundColor Yellow
aws eks delete-cluster --name platform-lab-cluster --region us-east-1 2>$null | Out-Null

Write-Host "[8/12] Esperando a que el cluster se elimine (~10 min)..." -ForegroundColor Yellow
aws eks wait cluster-deleted --name platform-lab-cluster --region us-east-1 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Timeout del waiter, esperando 120s extra..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 120
}

# ============================================================================
# PASO 8: Eliminar NAT Gateway y Elastic IP
# ============================================================================
Write-Host "[9/12] Eliminando NAT Gateway y Elastic IP..." -ForegroundColor Yellow
$vpcId = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=platform-lab-vpc" --region us-east-1 --query "Vpcs[0].VpcId" --output text

if ($vpcId -and $vpcId -ne "None") {
    # Eliminar NAT Gateway
    $natId = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpcId" --region us-east-1 --query "NatGateways[?State!='deleted'].NatGatewayId" --output text
    if ($natId -and $natId -ne "None" -and $natId -ne "") {
        aws ec2 delete-nat-gateway --nat-gateway-id $natId --region us-east-1 | Out-Null
        Write-Host "  NAT Gateway $natId eliminandose, esperando 60s..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds 60
    }

    # Liberar Elastic IP
    $eipAllocId = aws ec2 describe-addresses --filters "Name=tag:Name,Values=*platform-lab*" --region us-east-1 --query "Addresses[0].AllocationId" --output text
    if ($eipAllocId -and $eipAllocId -ne "None" -and $eipAllocId -ne "") {
        aws ec2 release-address --allocation-id $eipAllocId --region us-east-1
        Write-Host "  Elastic IP $eipAllocId liberada" -ForegroundColor DarkYellow
    }
}

# ============================================================================
# PASO 9: Recordatorio VPC
# ============================================================================
Write-Host "[10/12] VPC: eliminala desde la consola" -ForegroundColor Cyan
Write-Host "  → VPC → $vpcId → Actions → Delete VPC" -ForegroundColor DarkCyan
Write-Host "  (La consola borra subnets, IGW y route tables automaticamente)" -ForegroundColor DarkCyan

# ============================================================================
# PASO 10: Eliminar IAM roles
# ============================================================================
Write-Host "[11/12] Eliminando IAM roles..." -ForegroundColor Yellow

aws iam detach-role-policy --role-name platform-lab-cluster-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>$null
aws iam delete-role --role-name platform-lab-cluster-role 2>$null

aws iam detach-role-policy --role-name platform-lab-fargate-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy 2>$null
aws iam delete-role --role-name platform-lab-fargate-role 2>$null

# ============================================================================
# PASO 11: Eliminar OIDC Provider
# ============================================================================
Write-Host "[12/12] Eliminando OIDC Provider..." -ForegroundColor Yellow
$oidcArn = aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'platform-lab-cluster')].Arn" --output text 2>$null
if ($oidcArn -and $oidcArn -ne "None" -and $oidcArn -ne "") {
    aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $oidcArn
    Write-Host "  OIDC Provider eliminado" -ForegroundColor DarkYellow
} else {
    Write-Host "  OIDC Provider no encontrado (puede que eksctl ya lo haya eliminado)" -ForegroundColor DarkYellow
}

# ============================================================================
# VERIFICACIÓN FINAL
# ============================================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ Todo destruido. Verificando...                          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

$clusters = aws eks list-clusters --region us-east-1 --query 'clusters' --output text 2>$null
if ($clusters -and $clusters -ne "") {
    Write-Host "⚠️  Clusters encontrados: $clusters" -ForegroundColor Yellow
} else {
    Write-Host "✅ No hay clusters EKS corriendo" -ForegroundColor Green
}

Write-Host ""
Write-Host "Solo queda borrar la VPC desde la consola (si no lo hiciste ya)." -ForegroundColor Cyan
Write-Host "Después de eso, tu cuenta está limpia. `$0/hr." -ForegroundColor Green
