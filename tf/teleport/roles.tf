// roles.tf - Teleport role definitions

# Admin role - Full cluster access
resource "teleport_role" "admin" {
  version = "v7"
  metadata = {
    name        = "admin"
    description = "Full administrative access to all resources"
  }

  spec = {
    options = {
      max_session_ttl = "12h"
    }

    allow = {
      # SSH logins - use traits from OIDC
      logins = ["root", "admin", "{{internal.logins}}"]

      # Access all nodes
      node_labels = {
        "*" = ["*"]
      }

      # Full Kubernetes access
      kubernetes_groups = ["system:masters"]
      kubernetes_labels = {
        "*" = ["*"]
      }
      kubernetes_resources = [{
        kind      = "*"
        namespace = "*"
        name      = "*"
        verbs     = ["*"]
      }]

      # Full Teleport admin access
      rules = [{
        resources = ["*"]
        verbs     = ["*"]
      }]
    }
  }
}

# Access role - Standard user access
resource "teleport_role" "access" {
  version = "v7"
  metadata = {
    name        = "access"
    description = "Standard SSH and Kubernetes read access"
  }

  spec = {
    options = {
      max_session_ttl = "8h"
    }

    allow = {
      # SSH logins - use traits from OIDC
      logins = ["{{internal.logins}}"]

      # Access production nodes
      node_labels = {
        "env" = ["production"]
      }

      # Read-only Kubernetes access
      kubernetes_groups = ["view"]
      kubernetes_labels = {
        "*" = ["*"]
      }
      kubernetes_resources = [
        {
          kind      = "pod"
          namespace = "*"
          name      = "*"
          verbs     = ["get", "list", "watch"]
        },
        {
          kind      = "deployment"
          namespace = "*"
          name      = "*"
          verbs     = ["get", "list", "watch"]
        },
        {
          kind      = "service"
          namespace = "*"
          name      = "*"
          verbs     = ["get", "list", "watch"]
        }
      ]
    }
  }
}
