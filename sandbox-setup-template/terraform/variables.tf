variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "vm_name" {
  description = "Name of the sandbox VM"
  type        = string
  default     = "claude-sandbox"
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-standard-16"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 200
}

variable "boot_disk_type" {
  description = "Boot disk type (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-ssd"
}

variable "use_spot" {
  description = "Use spot/preemptible instances for cost savings"
  type        = bool
  default     = false
}

variable "allowed_ssh_ranges" {
  description = "CIDR ranges allowed to SSH (default: your IP only)"
  type        = list(string)
  default     = []
}

variable "agent_count" {
  description = "Number of Claude agents to support"
  type        = number
  default     = 12
}

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy for SSH (more secure)"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    environment = "sandbox"
    purpose     = "claude-agents"
  }
}
