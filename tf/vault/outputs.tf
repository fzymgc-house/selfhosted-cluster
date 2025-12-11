// outputs.tf - Outputs for vault module

output "test_windmill_flow" {
  description = "Test output for Windmill GitOps flow verification - safe to remove after testing"
  value       = "Windmill flow test at ${timestamp()}"
}
