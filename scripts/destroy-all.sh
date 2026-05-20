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

# Primero eliminar Helm releases (para que se borren los LBs)
echo ""
echo "🧹 Eliminando Helm releases..."
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
helm uninstall monitoring -n monitoring 2>/dev/null || true
helm uninstall argocd -n argocd 2>/dev/null || true
helm uninstall datadog-operator -n datadog 2>/dev/null || true

# Esperar a que se eliminen los Load Balancers
echo "⏳ Esperando eliminación de Load Balancers (30s)..."
sleep 30

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
