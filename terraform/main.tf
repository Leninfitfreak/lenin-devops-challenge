resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_resource_quota" "runtime" {
  metadata {
    name      = "runtime-quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.cpu_request_quota
      "requests.memory" = var.memory_request_quota
      "limits.cpu"      = var.cpu_limit_quota
      "limits.memory"   = var.memory_limit_quota
    }
  }
}

resource "kubernetes_secret" "api_token" {
  metadata {
    name      = "api-token"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  data = {
    token = var.api_token
  }

  type = "Opaque"
}
