// policy-windmill-test.tf - Test policy for Windmill flow verification
// Safe to delete after testing is complete

resource "vault_policy" "windmill_test" {
  name = "windmill-test"

  policy = <<EOT
# Test policy for Windmill GitOps flow verification
# This policy grants no actual permissions and is safe to delete

# Deny all access by default (no capabilities granted)
path "secret/data/windmill-test-does-not-exist" {
  capabilities = ["deny"]
}
EOT
}
