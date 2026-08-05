variable "do_token" {
  description = "DigitalOcean personal access token with read/write scope."
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = <<-EOT
    Name of an SSH key already uploaded to your DigitalOcean account
    (Settings > Security > SSH keys). List them with:
      doctl compute ssh-key list
  EOT
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the matching private key on this machine. Written into the generated Ansible inventory."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "region" {
  description = "DigitalOcean region slug. All droplets land here; keep them co-located for VPC networking."
  type        = string
  default     = "nyc3"
}

variable "ubuntu_image" {
  description = <<-EOT
    Droplet image slug. Defaults to the current LTS, Ubuntu 26.04 "Resolute Raccoon"
    (released 2026-04-23). Verify availability in your region before applying:
      doctl compute image list-distribution --public | grep -i ubuntu
    Fall back to "ubuntu-24-04-x64" if 26.04 is not yet published for your region.
  EOT
  type        = string
  default     = "ubuntu-26-04-x64"
}

variable "control_plane_size" {
  description = "Droplet size for control plane nodes. kubeadm requires a minimum of 2 vCPU."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "worker_size" {
  description = "Droplet size for worker nodes."
  type        = string
  default     = "s-2vcpu-2gb"
}

variable "cluster1_worker_count" {
  description = <<-EOT
    Workers in cluster-1. The mock exam is written for 2 (c1-node-1 is broken for
    Task 15, c1-node-2 carries the version skew for Task 3 and the GPU taint for
    Task 7). Set to 3 if you would rather not have Tasks 3 and 7 share a node.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.cluster1_worker_count >= 2 && var.cluster1_worker_count <= 4
    error_message = "cluster1_worker_count must be between 2 and 4."
  }
}

variable "cluster2_worker_count" {
  description = "Workers in cluster-2. The exam is written for 1."
  type        = number
  default     = 1
}

variable "allowed_ssh_cidrs" {
  description = <<-EOT
    CIDRs permitted to reach SSH, the API servers and NodePorts. Leave empty to
    auto-detect this machine's public /32 via ifconfig.co. Never open to 0.0.0.0/0 —
    these clusters run deliberately broken components.
  EOT
  type        = list(string)
  default     = []
}

variable "project_name" {
  description = "DigitalOcean project to group the droplets under."
  type        = string
  default     = "cka-mock-exam"
}

variable "name_prefix" {
  description = "Prefix for droplet names. Keep it short; it becomes part of the Kubernetes node name."
  type        = string
  default     = "cka"
}

variable "vpc_cidr" {
  description = "Private VPC range for node-to-node traffic. Must not overlap pod_cidr or service_cidr."
  type        = string
  default     = "10.20.0.0/20"
}
