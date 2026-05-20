variable "name" {
  description = "Nombre del Helm release"
  type        = string
}

variable "namespace" {
  description = "Namespace donde instalar"
  type        = string
}

variable "create_namespace" {
  description = "Crear el namespace si no existe"
  type        = bool
  default     = true
}

variable "repository" {
  description = "URL del repositorio de Helm"
  type        = string
}

variable "chart" {
  description = "Nombre del chart"
  type        = string
}

variable "chart_version" {
  description = "Versión del chart (SIEMPRE pinnear)"
  type        = string
}

variable "values_file" {
  description = "Path al archivo de values.yaml"
  type        = string
  default     = ""
}

variable "wait" {
  description = "Esperar a que todos los recursos estén ready"
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Timeout en segundos para la instalación"
  type        = number
  default     = 600
}

variable "set_values" {
  description = "Valores individuales para override"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
