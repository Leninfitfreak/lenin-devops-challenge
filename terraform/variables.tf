variable "namespace" {
  type        = string
  description = "Namespace to provision"
  default     = "devops-challenge"
}

variable "memory_quota" {
  type        = string
  description = "Total memory quota for the namespace"
  default     = "512Mi"
}

variable "api_token" {
  type        = string
  description = "API token consumed by the app"
}
