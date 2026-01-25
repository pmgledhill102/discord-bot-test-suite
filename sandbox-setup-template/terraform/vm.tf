# Compute Engine instance for Claude Code sandbox
resource "google_compute_instance" "sandbox" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  labels = var.labels

  # Use spot instances for cost savings (optional)
  dynamic "scheduling" {
    for_each = var.use_spot ? [1] : []
    content {
      preemptible                 = true
      automatic_restart           = false
      provisioning_model          = "SPOT"
      instance_termination_action = "STOP"
    }
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
      labels = var.labels
    }
  }

  network_interface {
    network    = google_compute_network.sandbox.id
    subnetwork = google_compute_subnetwork.sandbox.id

    # External IP for direct SSH (can be removed if using IAP only)
    access_config {
      network_tier = "STANDARD"
    }
  }

  # Run as dedicated service account
  service_account {
    email  = google_service_account.sandbox.email
    scopes = ["cloud-platform"]
  }

  # Startup script to install dependencies
  metadata = {
    startup-script = file("${path.module}/../scripts/provision-vm.sh")
    enable-oslogin = "TRUE"
  }

  # Allow stopping for updates
  allow_stopping_for_update = true

  depends_on = [
    google_project_service.apis,
  ]
}

# Reserve static internal IP
resource "google_compute_address" "sandbox_internal" {
  name         = "${var.vm_name}-internal"
  subnetwork   = google_compute_subnetwork.sandbox.id
  address_type = "INTERNAL"
  region       = var.region
}
