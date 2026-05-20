#!/bin/bash
###############################################################################
# 🔴 DESTRUIR TODA LA INFRAESTRUCTURA 🔴
# Ejecuta esto cuando termines TODAS las etapas
###############################################################################

set -e

echo "🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴"
echo "🔴  DESTRUYENDO TODA LA INFRAESTRUCTURA       🔴"
echo "🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴"
echo ""
echo "Esto elimina:"
echo "  - Cluster EKS"
echo "  - VPC, Subnets, NAT Gateway"
echo "  - Load Balancers"
echo "  - Fargate Profiles"
echo "  - IAM Roles"
echo "  - TODO"
echo ""
read -p "⚠️  Escribe 'destroy' para confirmar: " confirm

if [[ "$confirm" != "destroy" ]]; then
    echo "❌ Cancelado"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../etapa-01-cluster-eks/terraform"

# ============================================================================
# PASO CRÍTICO: Eliminar recursos de Kubernetes ANTES de Terraform
# ============================================================================
# ¿Por qué? Kubernetes crea Load Balancers (NLB/ALB) que viven en la VPC
# pero Terraform no sabe que existen (no los creó él). Si intentas hacer
# terraform destroy sin eliminarlos primero, falla porque la VPC tiene
# recursos "huérfanos" que Terraform no puede borrar.
# ============================================================================

echo ""
echo "🧹 [1/4] Eliminando Services tipo LoadBalancer..."
# Esto le dice a Kubernetes que borre los Services, lo cual trigger
# la eliminación automática de los NLB/ALB en AWS
kubectl delete svc --all-namespaces -l app.kubernetes.io/name=ingress-nginx 2>/dev/null || true
kubectl delete svc ingress-nginx-controller -n ingress-nginx 2>/dev/null || true

echo "🧹 [2/4] Eliminando Ingress resources (pueden tener ALBs asociados)..."
kubectl delete ingress --all-namespaces --all 2>/dev/null || true

echo "🧹 [3/4] Eliminando Helm releases..."
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
helm uninstall monitoring -n monitoring 2>/dev/null || true
helm uninstall argocd -n argocd 2>/dev/null || true
helm uninstall datadog-operator -n datadog 2>/dev/null || true

# Esperar a que AWS elimine los Load Balancers (tarda ~30-60 seg)
echo "⏳ [4/4] Esperando que AWS elimine los Load Balancers (60s)..."
echo "   (Si no esperas, terraform destroy falla porque la VPC tiene LBs huérfanos)"
sleep 60

# Verificar que no quedan LBs
echo "🔍 Verificando que no quedan Load Balancers..."
LB_COUNT=$(aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[?VpcId==`'$(cd "$TERRAFORM_DIR" && terraform output -raw vpc_id 2>/dev/null)'`]' --output text 2>/dev/null | wc -l)
if [ "$LB_COUNT" -gt "1" ]; then
    echo "⚠️  Todavía hay Load Balancers en la VPC. Esperando 30s más..."
    sleep 30
fi

# Terraform destroy
echo ""
echo "💣 Ejecutando terraform destroy..."
cd "$TERRAFORM_DIR"
terraform destroy -auto-approve

echo ""
echo "✅ ¡Todo destruido! Ya no se generan costos."
echo ""
echo "Verifica en la consola:"
echo "  aws eks list-clusters --region us-east-1"
echo "  aws ec2 describe-nat-gateways --region us-east-1 --filter Name=state,Values=available"
