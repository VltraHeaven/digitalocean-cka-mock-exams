###############################################################################
# CKA mock exam lab — DigitalOcean infrastructure
#
# Two kubeadm clusters:
#   cluster-1 : 1 control plane + N workers  (troubleshooting, RBAC, workloads)
#   cluster-2 : 1 control plane + M workers  (networking, storage, Helm/Kustomize)
###############################################################################

# ---------------------------------------------------------------------------
# Caller IP autodetection for the firewall
# ---------------------------------------------------------------------------
data "http" "my_ip" {
  count = length(var.allowed_ssh_cidrs) == 0 ? 1 : 0
  url   = "https://ifconfig.co/ip"
}

locals {
  admin_cidrs = length(var.allowed_ssh_cidrs) > 0 ? var.allowed_ssh_cidrs : [
    "${chomp(data.http.my_ip[0].response_body)}/32"
  ]

  clusters = {
    "cluster-1" = { workers = var.cluster1_worker_count, short = "c1" }
    "cluster-2" = { workers = var.cluster2_worker_count, short = "c2" }
  }

  # Flattened worker list: { "c1-node-1" = { cluster = "cluster-1", index = 1 }, ... }
  workers = merge([
    for cname, c in local.clusters : {
      for i in range(1, c.workers + 1) :
      "${c.short}-node-${i}" => { cluster = cname, short = c.short, index = i }
    }
  ]...)

  control_planes = {
    for cname, c in local.clusters :
    "${c.short}-cp-1" => { cluster = cname, short = c.short }
  }

  common_tags = ["cka-lab", replace(var.project_name, "_", "-")]
}

data "digitalocean_ssh_key" "admin" {
  name = var.ssh_key_name
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
resource "digitalocean_vpc" "lab" {
  name     = "${var.name_prefix}-vpc"
  region   = var.region
  ip_range = var.vpc_cidr
}

# ---------------------------------------------------------------------------
# Cloud-init: minimal prep so Ansible can take over immediately
# ---------------------------------------------------------------------------
locals {
  user_data = <<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - python3
      - python3-apt
      - curl
      - gnupg
      - apt-transport-https
    write_files:
      - path: /etc/sysctl.d/99-cka-lab.conf
        content: |
          net.ipv4.ip_forward = 1
    runcmd:
      - [ sysctl, --system ]
      - [ systemctl, disable, --now, unattended-upgrades ]
  CLOUDINIT
}

# ---------------------------------------------------------------------------
# Droplets
# ---------------------------------------------------------------------------
resource "digitalocean_droplet" "control_plane" {
  for_each = local.control_planes

  name      = "${var.name_prefix}-${each.key}"
  image     = var.ubuntu_image
  region    = var.region
  size      = var.control_plane_size
  vpc_uuid  = digitalocean_vpc.lab.id
  ssh_keys  = [data.digitalocean_ssh_key.admin.id]
  user_data = local.user_data
  tags      = concat(local.common_tags, ["control-plane", each.value.cluster])

  # Deliberately broken components live here; do not let DO reboot them.
  monitoring = true
  backups    = false

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_droplet" "worker" {
  for_each = local.workers

  name      = "${var.name_prefix}-${each.key}"
  image     = var.ubuntu_image
  region    = var.region
  size      = var.worker_size
  vpc_uuid  = digitalocean_vpc.lab.id
  ssh_keys  = [data.digitalocean_ssh_key.admin.id]
  user_data = local.user_data
  tags      = concat(local.common_tags, ["worker", each.value.cluster])

  monitoring = true
  backups    = false

  lifecycle {
    ignore_changes = [user_data]
  }
}

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------
resource "digitalocean_firewall" "lab" {
  name = "${var.name_prefix}-fw"

  droplet_ids = concat(
    [for d in digitalocean_droplet.control_plane : d.id],
    [for d in digitalocean_droplet.worker : d.id],
  )

  # --- SSH from admin only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = local.admin_cidrs
  }

  # --- Kubernetes API from admin only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "6443"
    source_addresses = local.admin_cidrs
  }

  # --- NodePort range from admin only (Task 11 uses 31090)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "30000-32767"
    source_addresses = local.admin_cidrs
  }

  # --- Unrestricted intra-VPC traffic: etcd, kubelet, CNI, kube-proxy, DNS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_cidr]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [var.vpc_cidr]
  }

  # Calico VXLAN / BGP and pod-to-pod encapsulated traffic
  inbound_rule {
    protocol         = "icmp"
    source_addresses = concat(local.admin_cidrs, [var.vpc_cidr])
  }

  # --- Egress: unrestricted (apt, container registries, Helm repos)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# ---------------------------------------------------------------------------
# Project grouping (cosmetic, keeps the DO console tidy)
# ---------------------------------------------------------------------------
resource "digitalocean_project" "lab" {
  name        = var.project_name
  description = "Deliberately broken kubeadm clusters for CKA practice. Destroy when done."
  purpose     = "Service or API"
  environment = "Development"

  resources = concat(
    [for d in digitalocean_droplet.control_plane : d.urn],
    [for d in digitalocean_droplet.worker : d.urn],
  )
}

# ---------------------------------------------------------------------------
# Generated Ansible inventory
# ---------------------------------------------------------------------------
resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    control_planes = {
      for k, d in digitalocean_droplet.control_plane :
      k => {
        public_ip  = d.ipv4_address
        private_ip = d.ipv4_address_private
        cluster    = local.control_planes[k].cluster
        short      = local.control_planes[k].short
      }
    }
    workers = {
      for k, d in digitalocean_droplet.worker :
      k => {
        public_ip  = d.ipv4_address
        private_ip = d.ipv4_address_private
        cluster    = local.workers[k].cluster
        short      = local.workers[k].short
      }
    }
    ssh_private_key_path = var.ssh_private_key_path
  })
}

# Convenience: /etc/hosts fragment used by the common role so node names resolve
resource "local_file" "hosts_fragment" {
  filename        = "${path.module}/../ansible/files/etc_hosts_fragment"
  file_permission = "0644"

  content = join("\n", concat(
    [for k, d in digitalocean_droplet.control_plane : "${d.ipv4_address_private} ${k}"],
    [for k, d in digitalocean_droplet.worker : "${d.ipv4_address_private} ${k}"],
    [""],
  ))
}
