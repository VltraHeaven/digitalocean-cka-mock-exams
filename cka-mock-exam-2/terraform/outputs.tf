output "cluster1_control_plane" {
  description = "Public IP of the cluster-1 control plane. This is your exam workstation."
  value       = { for k, d in digitalocean_droplet.control_plane : k => d.ipv4_address if local.control_planes[k].cluster == "cluster-1" }
}

output "cluster2_control_plane" {
  description = "Public IP of the cluster-2 control plane."
  value       = { for k, d in digitalocean_droplet.control_plane : k => d.ipv4_address if local.control_planes[k].cluster == "cluster-2" }
}

output "workers" {
  description = "Public IPs of all worker nodes."
  value       = { for k, d in digitalocean_droplet.worker : k => d.ipv4_address }
}

output "private_ips" {
  description = "VPC-internal addresses, used for kubeadm advertise addresses and etcd peering."
  value = merge(
    { for k, d in digitalocean_droplet.control_plane : k => d.ipv4_address_private },
    { for k, d in digitalocean_droplet.worker : k => d.ipv4_address_private },
  )
}

output "admin_cidrs" {
  description = "CIDRs the firewall permits for SSH, API and NodePort access."
  value       = local.admin_cidrs
}

output "ssh_workstation" {
  description = "SSH straight into the exam workstation."
  value       = "ssh root@${[for k, d in digitalocean_droplet.control_plane : d.ipv4_address if local.control_planes[k].cluster == "cluster-1"][0]}"
}

output "estimated_hourly_cost_usd" {
  description = "Rough burn rate. Destroy the lab when you finish."
  value = format(
    "~$%.3f/hr for %d droplets",
    (length(local.control_planes) * 0.03571) + (length(local.workers) * 0.02679),
    length(local.control_planes) + length(local.workers)
  )
}

output "next_steps" {
  value = <<-EOT

    Infrastructure is up. Now build the clusters and arm the exam:

      cd ../ansible
      ansible-playbook site.yml          # build both clusters (~12-15 min)
      ansible-playbook exam-setup.yml    # create the exam's healthy prerequisites
      ansible-playbook break.yml         # inject the faults

    Then fetch a merged kubeconfig for your laptop:

      scp root@<cluster1_control_plane>:/root/.kube/config ./kubeconfig
      export KUBECONFIG=$PWD/kubeconfig
      kubectl config get-contexts         # cluster-1, cluster-2

    When you are done:  terraform destroy
  EOT
}
