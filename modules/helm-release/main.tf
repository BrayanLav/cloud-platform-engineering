###############################################################################
# Módulo: Helm Release
###############################################################################
# Módulo reutilizable para instalar Helm charts de forma consistente.
# Aplica buenas prácticas: namespace dedicado, timeout, wait, values file.
#
# Uso:
#   module "ingress_nginx" {
#     source          = "../../modules/helm-release"
#     name            = "ingress-nginx"
#     namespace       = "ingress-nginx"
#     repository      = "https://kubernetes.github.io/ingress-nginx"
#     chart           = "ingress-nginx"
#     chart_version   = "4.10.0"
#     values_file     = "${path.module}/../../etapa-02-ingress-controller/helm/values-ingress-nginx.yaml"
#   }
###############################################################################

resource "helm_release" "this" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version

  values = var.values_file != "" ? [file(var.values_file)] : []

  wait    = var.wait
  timeout = var.timeout

  dynamic "set" {
    for_each = var.set_values
    content {
      name  = set.value.name
      value = set.value.value
    }
  }
}
