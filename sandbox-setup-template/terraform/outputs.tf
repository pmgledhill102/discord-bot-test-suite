output "vm_name" {
  description = "Name of the sandbox VM"
  value       = google_compute_instance.sandbox.name
}

output "vm_zone" {
  description = "Zone of the sandbox VM"
  value       = google_compute_instance.sandbox.zone
}

output "vm_external_ip" {
  description = "External IP of the sandbox VM"
  value       = google_compute_instance.sandbox.network_interface[0].access_config[0].nat_ip
}

output "vm_internal_ip" {
  description = "Internal IP of the sandbox VM"
  value       = google_compute_instance.sandbox.network_interface[0].network_ip
}

output "service_account_email" {
  description = "Service account email used by the VM"
  value       = google_service_account.sandbox.email
}

output "ssh_command_iap" {
  description = "SSH command using IAP tunnel"
  value       = "gcloud compute ssh ${google_compute_instance.sandbox.name} --zone=${google_compute_instance.sandbox.zone} --tunnel-through-iap"
}

output "ssh_command_direct" {
  description = "SSH command using direct IP"
  value       = "ssh ${google_compute_instance.sandbox.network_interface[0].access_config[0].nat_ip}"
}

output "secret_add_command" {
  description = "Command to add Anthropic API key to Secret Manager"
  value       = "echo 'your-api-key' | gcloud secrets versions add anthropic-api-key --data-file=-"
}
