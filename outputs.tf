output "static_primary_addresses" {
    value = [for instance in google_compute_instance.gw_instance : instance.network_interface[0].network_ip]
    description = "List of static primary internal IP addresses of the Gateway instances. Populated only if autoscaling is disabled."
}

output "static_management_addresses" {
    value = local.is_dual_nic ? [for instance in google_compute_instance.gw_instance : instance.network_interface[1].network_ip] : []
    description = "List of static management internal IP addresses of the Gateway instances. Populated only if dual NIC is enabled and autoscaling is disabled."
}

output "instance_names" {
    value = [for instance in google_compute_instance.gw_instance : instance.name]
    description = "List of names of the Gateway instances. Populated only if autoscaling is disabled."
}

output "instance_group_name" {
    value = local.is_autoscaling ? google_compute_region_instance_group_manager.gw_igm[0].name : ""
    description = "Name of the instance group manager for Gateway instances. Populated only if autoscaling is enabled."
}

output "load_balancer_names" {
    value = local.is_global_load_balancing ? [for lb in google_compute_url_map.gw_lb_url_map : lb.name] : local.is_regional_load_balancing ? [for lb in google_compute_region_url_map.gw_lb_url_map : lb.name] : []
    description = "List of load balancer names associated with the Gateway instances. Populated only if load balancing is enabled."
}