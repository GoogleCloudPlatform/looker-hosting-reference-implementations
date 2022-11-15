output "dns_nameserver" {
  value = <<-EOT
  Please ensure you update your domain's nameservers to the correct Cloud DNS nameservers. They are:
  ${join("\n", module.dns.name_servers)}
  EOT
}

output "secrets_reminder" {
  value = <<-EOT
  You will need to set secret values for the following secrets:
  ${join("\n", [ for i in values(module.secret_manager.secrets) : i.secret_id ])}

  You can generate an appropriate value for your GCM key with the following command:
  `openssl rand -base64 32`

  Secret values can be set in the GCP console or via gcloud.
  EOT
}

output "artifact_registry" {
  value = "Your artifact registry repository link is: ${var.location}-docker.pkg.dev/${var.project_id}/${var.repository_id}"
}