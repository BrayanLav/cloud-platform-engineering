#!/bin/bash
###############################################################################
# Instalar herramientas necesarias
###############################################################################

set -e

echo "🔧 Verificando herramientas..."
echo ""

check_tool() {
    if command -v $1 &> /dev/null; then
        echo "✅ $1: $($1 --version 2>/dev/null | head -1 || $1 version --short 2>/dev/null || echo 'instalado')"
        return 0
    else
        echo "❌ $1: NO instalado"
        return 1
    fi
}

MISSING=0

check_tool aws || MISSING=1
check_tool terraform || MISSING=1
check_tool kubectl || MISSING=1
check_tool helm || MISSING=1

echo ""

if [ $MISSING -eq 0 ]; then
    echo "🎉 Todas las herramientas instaladas!"
    echo ""
    echo "Verificar credenciales AWS:"
    echo "  aws sts get-caller-identity"
else
    echo "📥 Instalar las herramientas faltantes:"
    echo ""
    echo "AWS CLI:    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    echo "Terraform:  https://developer.hashicorp.com/terraform/install"
    echo "kubectl:    https://kubernetes.io/docs/tasks/tools/"
    echo "Helm:       curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
fi
