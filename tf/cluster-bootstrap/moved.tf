// moved.tf - Resource renames to match Kubernetes resource names

# Rename metallb_system to metallb to match actual namespace name
moved {
  from = kubernetes_namespace.metallb_system
  to   = kubernetes_namespace.metallb
}
