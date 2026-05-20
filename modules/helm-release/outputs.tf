output "release_name" {
  description = "Nombre del release instalado"
  value       = helm_release.this.name
}

output "release_namespace" {
  description = "Namespace donde se instaló"
  value       = helm_release.this.namespace
}

output "release_version" {
  description = "Versión del chart instalada"
  value       = helm_release.this.version
}

output "release_status" {
  description = "Status del release"
  value       = helm_release.this.status
}
