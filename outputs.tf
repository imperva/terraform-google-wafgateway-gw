output "static_primary_addresses" {
    value = [for instance in google_compute_instance.gw_instance : instance.network_interface[0].network_ip]
}

output "static_management_addresses" {
    value = local.is_dual_nic ? [for instance in google_compute_instance.gw_instance : instance.network_interface[1].network_ip] : []
}

output "instance_names" {
    value = [for instance in google_compute_instance.gw_instance : instance.name]
}

output "instance_group_name" {
    value = local.is_autoscaling ? google_compute_region_instance_group_manager.gw_igm[0].name : ""
}

output "load_balancer_names" {
    value = local.is_global_load_balancing ? [for lb in google_compute_url_map.gw_lb_url_map : lb.name] : local.is_regional_load_balancing ? [for lb in google_compute_region_url_map.gw_lb_url_map : lb.name] : []
}