variable "namespace" {
  type        = string
  description = "Namespace to provision"
  default     = "devops-challenge"
}

variable "cpu_request_quota" {
  type        = string
  description = "Total CPU request quota for the namespace"
  default     = "500m"
}

variable "memory_request_quota" {
  type        = string
  description = "Total memory request quota for the namespace"
  default     = "256Mi"
}

variable "cpu_limit_quota" {
  type        = string
  description = "Total CPU limit quota for the namespace"
  default     = "1"
}

variable "memory_limit_quota" {
  type        = string
  description = "Total memory limit quota for the namespace"
  default     = "512Mi"
}

variable "api_token" {
  type        = string
  description = "API token consumed by the app"
  sensitive   = true
}
