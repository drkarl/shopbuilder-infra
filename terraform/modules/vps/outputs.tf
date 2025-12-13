output "id" {
  description = "ID of the VPS instance"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_instance_server.this) > 0 ? scaleway_instance_server.this[0].id : null
    ) : (
    length(ovh_cloud_project_instance.this) > 0 ? ovh_cloud_project_instance.this[0].id : null
  )
}

output "public_ip" {
  description = "Public IP address of the VPS instance"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_instance_ip.this) > 0 ? scaleway_instance_ip.this[0].address : null
    ) : (
    length(ovh_cloud_project_instance.this) > 0 ? try(tolist(ovh_cloud_project_instance.this[0].addresses)[0].ip, null) : null
  )
}

output "private_ip" {
  description = "Private IP address of the VPS instance"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_instance_server.this) > 0 ? try(scaleway_instance_server.this[0].private_ips[0], null) : null
  ) : null # OVH Cloud instances may not have private IPs without vRack
}

output "ip_address" {
  description = "Public IP address of the VPS instance (alias for public_ip)"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_instance_ip.this) > 0 ? scaleway_instance_ip.this[0].address : null
    ) : (
    length(ovh_cloud_project_instance.this) > 0 ? try(tolist(ovh_cloud_project_instance.this[0].addresses)[0].ip, null) : null
  )
}

output "ssh_connection_string" {
  description = "SSH connection string to connect to the VPS"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_instance_ip.this) > 0 ? "ssh ${var.ssh_user}@${scaleway_instance_ip.this[0].address}" : null
    ) : (
    length(ovh_cloud_project_instance.this) > 0 ? try("ssh ${var.ssh_user}@${tolist(ovh_cloud_project_instance.this[0].addresses)[0].ip}", null) : null
  )
}

output "ssh_key_id" {
  description = "ID of the SSH key resource"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_iam_ssh_key.this) > 0 ? scaleway_iam_ssh_key.this[0].id : null
    ) : (
    length(ovh_cloud_project_ssh_key.this) > 0 ? ovh_cloud_project_ssh_key.this[0].id : null
  )
}

output "security_group_id" {
  description = "ID of the security group (Scaleway only)"
  value = var.provider_type == "scaleway" ? (
    length(scaleway_instance_security_group.this) > 0 ? scaleway_instance_security_group.this[0].id : null
  ) : null
}

output "provider_type" {
  description = "Cloud provider type used for this VPS"
  value       = var.provider_type
}

output "instance_name" {
  description = "Name of the VPS instance"
  value       = var.name
}
