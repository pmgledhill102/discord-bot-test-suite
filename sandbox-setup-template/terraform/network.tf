# Dedicated VPC for sandbox isolation
resource "google_compute_network" "sandbox" {
  name                    = "${var.vm_name}-network"
  auto_create_subnetworks = false
  description             = "Isolated network for Claude sandbox"
}

resource "google_compute_subnetwork" "sandbox" {
  name          = "${var.vm_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.sandbox.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT for outbound internet access without external IP
resource "google_compute_router" "sandbox" {
  name    = "${var.vm_name}-router"
  region  = var.region
  network = google_compute_network.sandbox.id
}

resource "google_compute_router_nat" "sandbox" {
  name                               = "${var.vm_name}-nat"
  router                             = google_compute_router.sandbox.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: Allow SSH via IAP
resource "google_compute_firewall" "iap_ssh" {
  count   = var.enable_iap ? 1 : 0
  name    = "${var.vm_name}-allow-iap-ssh"
  network = google_compute_network.sandbox.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]

  target_service_accounts = [google_service_account.sandbox.email]
}

# Firewall: Allow direct SSH from specific IPs (optional, less secure)
resource "google_compute_firewall" "direct_ssh" {
  count   = length(var.allowed_ssh_ranges) > 0 ? 1 : 0
  name    = "${var.vm_name}-allow-direct-ssh"
  network = google_compute_network.sandbox.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges           = var.allowed_ssh_ranges
  target_service_accounts = [google_service_account.sandbox.email]
}

# Firewall: Allow all egress (agents need internet access)
resource "google_compute_firewall" "allow_egress" {
  name      = "${var.vm_name}-allow-egress"
  network   = google_compute_network.sandbox.id
  direction = "EGRESS"

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  destination_ranges = ["0.0.0.0/0"]
}

# Firewall: Deny all ingress by default (except SSH above)
resource "google_compute_firewall" "deny_ingress" {
  name     = "${var.vm_name}-deny-ingress"
  network  = google_compute_network.sandbox.id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}
