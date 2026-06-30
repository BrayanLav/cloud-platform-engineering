#!/bin/bash
###############################################################################
# Script: Destruir toda la infraestructura del lab
###############################################################################
# Este script elimina todo en el orden correcto para evitar errores de
# dependencia. SIEMPRE úsalo en vez de terraform destroy directo.
#
# Uso:
#   chmod +x scripts/destroy-all.sh
#   ./scripts/destroy-all.sh
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ⚠️  DESTRUYENDO TODA LA INFRAESTRUCTURA DEL LAB           ║${NC}"
echo -e "${RED}║  Esto elimina: EKS, VPC, Load Balancers, todo.             ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -p "¿Estás seguro? Escribe 'destruir' para confirmar: " confirm
if [ "$confirm" != "destruir" ]; then
  echo -e "${YELLOW}Cancelado.${NC}"
  exit 0
fi

echo ""
echo -e "${YELLOW}Paso 1/5: Eliminando Helm releases...${NC}"
helm uninstall datadog-operator -n datadog 2>/dev/null || echo "  → datadog-operator no encontrado (OK)"
helm uninstall argocd -n argocd 2>/dev/null || echo "  → argocd no encontrado (OK)"
helm uninstall monitoring -n monitoring 2>/dev/null || echo "  → monitoring no encontrado (OK)"
helm uninstall cert-manager -n cert-manager 2>/dev/null || echo "  → cert-manager no encontrado (OK)"
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || echo "  → ingress-nginx no encontrado (OK)"

echo ""
echo -e "${YELLOW}Paso 2/5: Eliminando recursos de Kubernetes...${NC}"
kubectl delete ingress --all-namespaces --all 2>/dev/null || true
kubectl delete svc -n ingress-nginx ingress-nginx-controller 2>/dev/null || true
kubectl delete -f etapa-04-gitops-argocd/apps/ 2>/dev/null || true
kubectl delete -f etapa-05-datadog-monitoring/manifests/ 2>/dev/null || true

echo ""
echo -e "${YELLOW}Paso 3/5: Esperando que AWS elimine los Load Balancers (90 seg)...${NC}"
echo "  Los Load Balancers tardan ~60 seg en eliminarse de AWS."
echo "  Si no esperas, terraform destroy falla con DependencyViolation."
sleep 90

echo ""
echo -e "${YELLOW}Paso 4/5: Verificando que no quedan Load Balancers...${NC}"
LB_COUNT=$(aws elbv2 describe-load-balancers --region us-east-1 \
  --query 'length(LoadBalancers)' --output text 2>/dev/null || echo "0")

if [ "$LB_COUNT" != "0" ]; then
  echo -e "${YELLOW}  ⚠️  Todavía hay $LB_COUNT Load Balancer(s). Esperando 60 seg más...${NC}"
  sleep 60
fi

echo ""
echo -e "${YELLOW}Paso 5/5: Destruyendo infraestructura con Terraform...${NC}"
cd etapa-01-cluster-eks/terraform/
terraform destroy -auto-approve

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ Todo destruido. Verificando...                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

aws eks list-clusters --region us-east-1 --query 'clusters' --output text
echo ""
echo -e "${GREEN}Si no aparece nada arriba, tu cuenta está limpia. $0/hr.${NC}"
