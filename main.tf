locals {
  resource_prefix = var.deployment_name != "" ? var.deployment_name : random_string.resource_prefix[0].result
  waf_image_url = "${module.commons.constants.gcp.image_url_prefix}${module.commons.builds[var.waf_version]}"
  is_dual_nic = var.management_vpc_network != ""
  is_autoscaling = var.auto_scaling_config != null
  is_load_balancing = var.load_balancer_config != null
  is_global_load_balancing = local.is_load_balancing ? var.load_balancer_config.type == "GLOBAL" : false
  is_regional_load_balancing = local.is_load_balancing ? var.load_balancer_config.type == "REGIONAL" : false
  lb_rule_mapping = local.is_load_balancing ? {
    for rule in var.load_balancer_config.rules: "${rule.frontend_protocol}-${rule.frontend_port}_TO_${rule.backend_protocol}-${rule.backend_port}" => rule
  } : {}
  lb_grouped_backends = local.is_load_balancing ? {for rule in var.load_balancer_config.rules: "${rule.backend_protocol}-${rule.backend_port}" => {
    protocol=rule.backend_protocol
    port=rule.backend_port
    named_port="gw-port-${rule.backend_port}"
  }...} : {}
  lb_unique_backends = {for key, backend_set in local.lb_grouped_backends: key => backend_set[0]}
  lb_http_rules = {for key, rule in local.lb_rule_mapping: key => rule if rule.frontend_protocol == "HTTP"}
  lb_https_rules = {for key, rule in local.lb_rule_mapping: key => rule if rule.frontend_protocol == "HTTPS"}
  lb_provision_ip = local.is_load_balancing ? var.load_balancer_config.ip_address == null : false
  lb_provision_proxy_subnet = local.is_regional_load_balancing ? length(data.google_compute_subnetworks.proxy_only_subnets[0].subnetworks) == 0 : false
  gw_management_network = local.is_dual_nic ? var.management_vpc_network : var.primary_vpc_network
  is_mx_in_gcp = var.management_server_config.vpc_network != ""
  is_mx_in_same_vpc = var.management_server_config.vpc_network == local.gw_management_network
  create_vpc_connector_resources = local.is_mx_in_gcp && local.is_autoscaling
  mx_tag = var.management_server_config.network_tag
  mx_secret_id = google_secret_manager_secret.gw_registration_secret.secret_id
  management_ip = var.management_server_config.ip
  unique_zones = tolist(toset(var.zones))
  cloud_eiops_ranges = try([for range in regexall("ip4:?[^ ]+", join(" ", data.dns_txt_record_set.google_cloud_eiops[0].records)): replace(range, "ip4:", "")], [])
  gw_tag = "${local.resource_prefix}-gw"
  gw_fw_rules = merge(
    length(var.ssh_access_source_ranges) > 0 ? {
      SSH = {
        name = "${local.resource_prefix}-gw-ssh-access"
        direction = "INGRESS"
        network = local.gw_management_network
        source_ranges = var.ssh_access_source_ranges
        source_tags = []
        target_tags = [
          local.gw_tag
        ]
        allow = [
          {
            protocol = "tcp"
            ports = [
              "22"
            ]
          }
        ]
      }
    } : {},
    local.is_mx_in_same_vpc ? {
      GW_TO_MX = {
        name = "${local.resource_prefix}-gw-to-mx-access"
        direction = "INGRESS"
        network = local.gw_management_network
        source_ranges = []
        source_tags = [
          local.gw_tag
        ]
        target_tags = [
          local.mx_tag
        ]
        allow = [
          {
            protocol = "tcp"
            ports = [
              "8083"
            ]
          }
        ]
      }
    } : {},
    {
      MX_TO_GW = {
        name = "${local.resource_prefix}-mx-to-gw-access"
        direction = "INGRESS"
        network = local.gw_management_network
        source_ranges = !local.is_mx_in_same_vpc ? [
          "${var.management_server_config.ip}/32"
        ]: []
        source_tags = local.is_mx_in_same_vpc ? [
          local.mx_tag
        ]: []
        target_tags = [
          local.gw_tag
        ]
        allow = [
          {
            protocol = "tcp"
            ports = [
              "443"
            ]
          }
        ]
      }
    },
    local.is_autoscaling ? {
      AUTOHEALING = {
        name = "${local.resource_prefix}-gw-autohealing"
        direction = "INGRESS"
        network = var.primary_vpc_network
        source_ranges = module.commons.constants.gcp.healthcheck_source_ranges
        source_tags = []
        target_tags = [
          local.gw_tag
        ]
        allow = [
          {
            protocol = "tcp"
            ports = [module.commons.constants.gcp.gw_healthcheck_port]
          }
        ]
      }
    } : {},
    local.create_vpc_connector_resources ? {
      VPC_CONNECTOR = {
        name = "${local.resource_prefix}-vpc-serverless-access"
        direction = "INGRESS"
        network = var.management_server_config.vpc_network
        source_ranges = []
        source_tags = [
          "vpc-connector-${data.google_client_config.this.region}-${google_vpc_access_connector.vpc_access_connector[0].name}"          
        ]
        target_tags = [
          local.mx_tag
        ]
        allow = [
          {
            protocol = "tcp"
            ports = [
              "8083"
            ]
          }
        ]
      }
    } : {},
    local.is_load_balancing ? {
      GFE_TO_GW = {
        name = "${local.resource_prefix}-gfe-to-gw-access"
        direction = "INGRESS"
        network = var.primary_vpc_network
        source_ranges = concat(
          module.commons.constants.gcp.healthcheck_source_ranges, 
          local.is_global_load_balancing ? local.cloud_eiops_ranges : [],
          local.is_regional_load_balancing ? local.lb_provision_proxy_subnet ? [
            google_compute_subnetwork.gw_lb_proxy_subnet[0].ip_cidr_range
          ] : [
            data.google_compute_subnetworks.proxy_only_subnets[0].subnetworks[0].ip_cidr_range
          ] : []
        )
        source_tags = []
        target_tags = [
          local.gw_tag
        ]
        allow = [
          {
            protocol = "tcp"
            ports = concat([module.commons.constants.gcp.gw_healthcheck_port], [for key, backend in local.lb_unique_backends : backend.port])
          }
        ]
      }
    } : {}
  )
  gw_group = "gcp"
  is_private_google_access_enabled = (
    local.is_dual_nic 
    ? alltrue([data.google_compute_subnetwork.gw_data_subnet.private_ip_google_access, 
               data.google_compute_subnetwork.gw_mgmt_subnet[0].private_ip_google_access])
             : data.google_compute_subnetwork.gw_data_subnet.private_ip_google_access
  )
}

data "google_compute_network" "primary_vpc_network" {
  name = var.primary_vpc_network
}

data "google_compute_subnetworks" "proxy_only_subnets" {
  count = local.is_regional_load_balancing ? 1 : 0
  region = data.google_client_config.this.region
  filter = "(network = \"${data.google_compute_network.primary_vpc_network.self_link}\") AND (purpose = REGIONAL_MANAGED_PROXY)"
}

data "google_compute_subnetwork" "gw_data_subnet" {
  name   = var.primary_subnet_name
  region = data.google_client_config.this.region
}

data "google_compute_subnetwork" "gw_mgmt_subnet" {
  count = local.is_dual_nic ? 1 : 0
  name   = var.management_subnet_name 
  region = data.google_client_config.this.region
}

data "google_compute_zones" "available" {
}

data "dns_txt_record_set" "google_cloud_eiops" {
  # Additional source GFE proxy ranges for global external Application Load Balancers
  count = local.is_global_load_balancing ? 1 : 0
  host = "_cloud-eoips.googleusercontent.com"
}

data "google_client_config" "this" {}

module "commons" {
  source = "imperva/wafgateway-commons/google"
  version = "1.0.1"
}

resource "random_string" "resource_prefix" {
  count = var.deployment_name != "" ? 0 : 1
  length  = 4
  special = false
  upper = false
  numeric = false
}

resource "google_service_account" "deployment_service_account" {
  account_id = "${local.resource_prefix}-gw-svc-acc"
}

resource "google_compute_firewall" "gw_firewall" {
  for_each = local.gw_fw_rules
  name = each.value.name
  network = each.value.network
  direction = each.value.direction
  source_ranges = each.value.source_ranges
  source_tags = each.value.source_tags
  target_tags = each.value.target_tags
  dynamic "allow" {
    for_each = each.value.allow
    content {
      protocol = allow.value.protocol
      ports = allow.value.ports
    }
  }
}

resource "google_secret_manager_secret" "gw_registration_secret" {
  secret_id = "${local.resource_prefix}-gw-registration-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "gw_registration_secret_version" {
  secret = google_secret_manager_secret.gw_registration_secret.id
  secret_data = var.management_server_config.password
}

resource "google_secret_manager_secret_iam_member" "gw_registration_secret_iam_member" {
  secret_id = local.mx_secret_id
  role = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${google_service_account.deployment_service_account.email}"
}

resource "google_compute_instance" "gw_instance" {
  count = !local.is_autoscaling ? var.number_of_gateways : 0
  depends_on = [
    google_secret_manager_secret_version.gw_registration_secret_version,
    google_compute_firewall.gw_firewall
  ]
  name = format("${local.resource_prefix}-gw-%d", count.index)
  description = "Imperva WAF Gateway (Deployment ID: ${local.resource_prefix})"
  zone = element(local.unique_zones, count.index)
  tags = [
    local.gw_tag
  ]
  machine_type = var.instance_type
  boot_disk {
    initialize_params {
      image = local.waf_image_url
    }
  }
  network_interface {
    network = var.primary_vpc_network
    subnetwork = var.primary_subnet_name
  }
  dynamic "network_interface" {
    for_each = local.is_dual_nic ? [1] : []
    content {
      network = local.gw_management_network
      subnetwork = var.management_subnet_name
    }
  }
  metadata = {
    startup-script = data.template_cloudinit_config.gw_gcp_deploy.rendered
    block-project-ssh-keys = var.block_project_ssh_keys
  }
  service_account {
    email = google_service_account.deployment_service_account.email
    scopes = [
      "cloud-platform"
    ]
  }
  lifecycle {
    precondition {
      condition = local.is_private_google_access_enabled
      error_message = module.commons.validation.gcp.subnet.private_google_access.error_message
    }
  }
}

resource "google_compute_instance_template" "gw_instance_template" {
  count = local.is_autoscaling ? 1 : 0
  name_prefix = "${local.resource_prefix}-gw-template-"
  description = "Template for creating auto-scaling WAF Gateway instances."
  tags = [
    local.gw_tag
  ]
  instance_description = "Imperva WAF Gateway (Deployment ID: ${local.resource_prefix})"
  machine_type = var.instance_type
  scheduling {
    automatic_restart = true
    on_host_maintenance = "MIGRATE"
  }
  disk {
    source_image = local.waf_image_url
    auto_delete = true
    boot = true
  }
  network_interface {
    network = var.primary_vpc_network
    subnetwork = var.primary_subnet_name
  }
  dynamic "network_interface" {
    for_each = local.is_dual_nic ? [1] : []
    content {
      network = local.gw_management_network
      subnetwork = var.management_subnet_name
    }
  }
  service_account {
    email = google_service_account.deployment_service_account.email
    scopes = [
      "cloud-platform"
    ]
  }
  metadata = {
    startup-script = data.template_cloudinit_config.gw_gcp_deploy.rendered
    block-project-ssh-keys = var.block_project_ssh_keys
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "time_sleep" "await_gw_deletion" {
  count = local.is_autoscaling ? 1 : 0
  depends_on = [
    google_logging_project_sink.gw_termination_log_sink,
    google_pubsub_topic_iam_member.gw_termination_pubsub_iam_member,
    google_secret_manager_secret_version.gw_registration_secret_version,
    google_secret_manager_secret_iam_member.gw_registration_secret_iam_member,
    google_vpc_access_connector.vpc_access_connector,
    google_compute_firewall.gw_firewall,
    google_cloudfunctions2_function.gw_termination_handler,
    google_project_service.eventarc_enable,
    google_cloudfunctions2_function_iam_member.invoker,
    google_cloud_run_service_iam_member.cloud_run_invoker
  ]
  destroy_duration = "3m"
}

resource "google_compute_health_check" "gw_igm_healthcheck" {
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-igm-hc"
  check_interval_sec = module.commons.constants.gcp.autoscaling.health_check.interval_sec
  timeout_sec = module.commons.constants.gcp.autoscaling.health_check.timeout_sec
  healthy_threshold = module.commons.constants.gcp.autoscaling.health_check.healthy_threshold
  unhealthy_threshold = module.commons.constants.gcp.autoscaling.health_check.unhealthy_threshold
  http_health_check {
    port = module.commons.constants.gcp.autoscaling.health_check.port
  }
}

resource "google_compute_region_instance_group_manager" "gw_igm" {
  depends_on = [
    time_sleep.await_gw_deletion,
    google_compute_firewall.gw_firewall
  ]
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-igm"
  base_instance_name = "${local.resource_prefix}-gw"
  distribution_policy_zones = local.unique_zones
  distribution_policy_target_shape = "EVEN"
  update_policy {
    type = "OPPORTUNISTIC"
    minimal_action = "REPLACE"
    max_surge_fixed = length(local.unique_zones)
    max_unavailable_fixed = length(local.unique_zones)
  }
  version {
    name = "primary"
    instance_template = google_compute_instance_template.gw_instance_template[0].id
  }
  auto_healing_policies {
    health_check = google_compute_health_check.gw_igm_healthcheck[0].id
    initial_delay_sec = 360
  }
  dynamic "named_port" {
    for_each = local.is_load_balancing ? local.lb_unique_backends : {}
    iterator = each
    content {
      name = each.value.named_port
      port = each.value.port
    }
  }
  lifecycle {
    precondition {
      condition = local.is_private_google_access_enabled
      error_message = module.commons.validation.gcp.subnet.private_google_access.error_message
    }
  }
}

resource "google_compute_region_autoscaler" "gw_autoscaler" {
  depends_on = [
    google_secret_manager_secret_version.gw_registration_secret_version
  ]
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-autoscaler"
  target = google_compute_region_instance_group_manager.gw_igm[0].id
  autoscaling_policy {
    cpu_utilization {
      target = module.commons.constants.gcp.autoscaling.cpu_threshold
    }
    metric {
      filter = "resource.type = \"gce_instance\""
      name = "compute.googleapis.com/instance/network/received_bytes_count"
      single_instance_assignment = 0
      target = module.commons.constants.gcp.model_throughput_capping[var.model] * module.commons.constants.gcp.autoscaling.throughput_threshold
      type = "DELTA_PER_SECOND"
    }
    min_replicas = var.auto_scaling_config.min_size
    max_replicas = var.auto_scaling_config.max_size
    cooldown_period = module.commons.constants.gcp.autoscaling.cooldown_period
  }
}

resource "time_sleep" "await_gw_ftl" {
  depends_on = [
    google_compute_instance.gw_instance
  ]
  create_duration = "8m"

  triggers = local.is_autoscaling ? {
    GW_INSTANCE_GROUP_MANAGER = google_compute_region_instance_group_manager.gw_igm[0].id
    GW_INSTANCE_TEMPLATE = google_compute_instance_template.gw_instance_template[0].id
  } : {
    for index, instance in google_compute_instance.gw_instance: "GW${index}" => instance.id
  }
}

resource "google_pubsub_topic" "gw_termination_pubsub_topic" {
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-termination-pubsub"
}

resource "google_pubsub_topic_iam_member" "gw_termination_pubsub_iam_member" {
  count = local.is_autoscaling ? 1 : 0
  topic = google_pubsub_topic.gw_termination_pubsub_topic[0].id
  role = "roles/pubsub.publisher"
  member = "serviceAccount:cloud-logs@system.gserviceaccount.com"
}

resource "google_logging_project_sink" "gw_termination_log_sink" {
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-termination-log-sink"
  destination = "pubsub.googleapis.com/${google_pubsub_topic.gw_termination_pubsub_topic[0].id}"
  filter = "resource.type=gce_instance AND protoPayload.methodName=(v1.compute.instances.delete OR compute.instances.repair.recreateInstance) AND proto_payload.resource_name:${local.resource_prefix}-gw AND operation.last=true"
  unique_writer_identity = false
}

resource "random_integer" "random_ip_octet" {
  count = local.is_autoscaling ? 1 : 0
  min = 200
  max = 255
}

resource "google_vpc_access_connector" "vpc_access_connector" {
  count = local.create_vpc_connector_resources ? 1 : 0
  name = "${local.resource_prefix}-conn"
  network = var.management_server_config.vpc_network
  ip_cidr_range = "10.${random_integer.random_ip_octet[0].result}.0.0/28"
  min_instances = 2
  max_instances = 3
}

resource "random_id" "bucket_random_id" {
  count = local.is_autoscaling ? 1 : 0
  byte_length = 4
}

data "archive_file" "gw_termination_handler" {
  count = local.is_autoscaling ? 1 : 0
  type = "zip"
  source_dir = "${path.module}/addons/termination_handler"
  output_path = "${path.module}/addons/termination_handler.zip"
}

resource "google_project_service" "eventarc_enable" {
  count = local.is_autoscaling ? 1 : 0
  service = "eventarc.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "gw_termination_function_source_bucket" {
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-termination-func-src-${random_id.bucket_random_id[0].hex}"
  location = data.google_client_config.this.region
}

resource "google_storage_bucket_object" "gw_termination_function_source_object" {
  count = local.is_autoscaling ? 1 : 0
  name = "gw_termination_handler.zip"
  bucket = google_storage_bucket.gw_termination_function_source_bucket[0].name
  source = data.archive_file.gw_termination_handler[0].output_path
}

resource "google_cloudfunctions2_function" "gw_termination_handler" {
  count = local.is_autoscaling ? 1 : 0
  name = "${local.resource_prefix}-gw-termination-handler"
  description = "Removes auto-scaling WAF Gateway entries from the Management Server"
  location = data.google_client_config.this.region
  build_config {
    runtime = "python39"
    entry_point = "handler"
    source {
      storage_source {
        bucket = google_storage_bucket.gw_termination_function_source_bucket[0].name
        object = google_storage_bucket_object.gw_termination_function_source_object[0].name
      }
    }
  }
  service_config {
    available_memory = "128Mi"
    timeout_seconds = 270
    environment_variables = {
      MX_HOST = local.management_ip
    }
    secret_environment_variables {
      project_id = data.google_client_config.this.project
      key = "MX_PASSWORD"
      secret = local.mx_secret_id
      version = "latest"
    }
    vpc_connector = local.create_vpc_connector_resources ? google_vpc_access_connector.vpc_access_connector[0].id : null
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
    service_account_email = google_service_account.deployment_service_account.email
  }
  event_trigger {
    event_type = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.gw_termination_pubsub_topic[0].id
    service_account_email = google_service_account.deployment_service_account.email
    retry_policy = "RETRY_POLICY_DO_NOT_RETRY"
  }
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  count = local.is_autoscaling ? 1 : 0
  cloud_function = google_cloudfunctions2_function.gw_termination_handler[0].name
  role = "roles/cloudfunctions.invoker"
  member = "serviceAccount:${google_service_account.deployment_service_account.email}"
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  count = local.is_autoscaling ? 1 : 0
  service = google_cloudfunctions2_function.gw_termination_handler[0].name
  role = "roles/run.invoker"
  member = "serviceAccount:${google_service_account.deployment_service_account.email}"
}

resource "google_compute_health_check" "gw_lb_healthcheck" {
  count = local.is_global_load_balancing ? 1 : 0
  name = "${local.resource_prefix}-gw-lb-hc"
  check_interval_sec = module.commons.constants.gcp.lb.health_check.interval_sec
  timeout_sec = module.commons.constants.gcp.lb.health_check.timeout_sec
  healthy_threshold = module.commons.constants.gcp.lb.health_check.healthy_threshold
  unhealthy_threshold = module.commons.constants.gcp.lb.health_check.unhealthy_threshold
  http_health_check {
    port = module.commons.constants.gcp.lb.health_check.port
  }
}

resource "google_compute_region_health_check" "gw_lb_healthcheck" {
  count = local.is_regional_load_balancing ? 1 : 0
  name = "${local.resource_prefix}-gw-lb-hc"
  check_interval_sec = module.commons.constants.gcp.lb.health_check.interval_sec
  timeout_sec = module.commons.constants.gcp.lb.health_check.timeout_sec
  healthy_threshold = module.commons.constants.gcp.lb.health_check.healthy_threshold
  unhealthy_threshold = module.commons.constants.gcp.lb.health_check.unhealthy_threshold
  http_health_check {
    port = module.commons.constants.gcp.lb.health_check.port
  }
}

resource "google_compute_backend_service" "gw_backend_service" {
  for_each = local.is_global_load_balancing ? local.lb_unique_backends : {}  
  name = "${local.resource_prefix}-gw-${lower(replace(each.value.protocol, "/", ""))}-${each.value.port}-svc"
  health_checks = [
    google_compute_health_check.gw_lb_healthcheck[0].id
  ]
  load_balancing_scheme = var.load_balancer_config.scheme
  protocol = each.value.protocol
  port_name = each.value.named_port
  backend {
    group = google_compute_region_instance_group_manager.gw_igm[0].instance_group
    max_utilization = 1.0
    capacity_scaler = 1.0
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_region_backend_service" "gw_backend_service" {
  for_each = local.is_regional_load_balancing ? local.lb_unique_backends : {}  
  name = "${local.resource_prefix}-gw-${lower(replace(each.value.protocol, "/", ""))}-${each.value.port}-svc"
  health_checks = [
    google_compute_region_health_check.gw_lb_healthcheck[0].id
  ]
  load_balancing_scheme = var.load_balancer_config.scheme
  protocol = each.value.protocol
  port_name = each.value.named_port
  backend {
    group = google_compute_region_instance_group_manager.gw_igm[0].instance_group
    max_utilization = 1.0
    capacity_scaler = 1.0
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_url_map" "gw_lb_url_map" {
  # One URL map per unique backend
  # Multiple forwarding rules can point to the same URL map
  for_each = local.is_global_load_balancing ? local.lb_unique_backends : {}
  name = "${local.resource_prefix}-gw-${lower(replace(each.value.protocol, "/", ""))}-${each.value.port}-lb"
  default_service = google_compute_backend_service.gw_backend_service[each.key].id
}

resource "google_compute_region_url_map" "gw_lb_url_map" {
  # One URL map per unique backend
  # Multiple forwarding rules can point to the same URL map
  for_each = local.is_regional_load_balancing ? local.lb_unique_backends : {}
  name = "${local.resource_prefix}-gw-${lower(replace(each.value.protocol, "/", ""))}-${each.value.port}-lb"
  default_service = google_compute_region_backend_service.gw_backend_service[each.key].id
}

resource "google_compute_target_http_proxy" "gw_lb_http_proxy" {
  for_each = local.is_global_load_balancing ? local.lb_http_rules : {}
  name = "${local.resource_prefix}-gw-lb-http-${each.value.frontend_port}-proxy"
  url_map = google_compute_url_map.gw_lb_url_map["${each.value.backend_protocol}-${each.value.backend_port}"].id
}

resource "google_compute_region_target_http_proxy" "gw_lb_http_proxy" {
  for_each = local.is_regional_load_balancing ? local.lb_http_rules : {}
  name = "${local.resource_prefix}-gw-lb-http-${each.value.frontend_port}-proxy"
  url_map = google_compute_region_url_map.gw_lb_url_map["${each.value.backend_protocol}-${each.value.backend_port}"].id
}

data "google_compute_ssl_certificate" "gw_lb_ssl_certificate" {
  for_each = {for key, rule in local.lb_https_rules: key => rule if rule.tls.certificate_name != null}
  name = each.value.tls.certificate_name
}

resource "google_compute_ssl_certificate" "gw_lb_ssl_certificate" {
  for_each = {for key, rule in local.lb_https_rules: key => rule if rule.tls.certificate_name == null}
  name = "${local.resource_prefix}-gw-lb-${each.value.frontend_port}-ssl-cert"
  private_key = each.value.tls.key
  certificate = each.value.tls.certificate
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_https_proxy" "gw_lb_https_proxy" {
  for_each = local.is_global_load_balancing ? local.lb_https_rules : {}
  name = "${local.resource_prefix}-gw-lb-https${each.value.frontend_port}-proxy"
  url_map = google_compute_url_map.gw_lb_url_map["${each.value.backend_protocol}-${each.value.backend_port}"].id
  ssl_certificates = [
    can(data.google_compute_ssl_certificate.gw_lb_ssl_certificate[each.key]) ? 
      data.google_compute_ssl_certificate.gw_lb_ssl_certificate[each.key].id : 
      google_compute_ssl_certificate.gw_lb_ssl_certificate[each.key].id
  ]
}

resource "google_compute_region_target_https_proxy" "gw_lb_https_proxy" {
  for_each = local.is_regional_load_balancing ? local.lb_https_rules : {}
  name = "${local.resource_prefix}-gw-lb-https${each.value.frontend_port}-proxy"
  url_map = google_compute_region_url_map.gw_lb_url_map["${each.value.backend_protocol}-${each.value.backend_port}"].id
  ssl_certificates = [
    can(data.google_compute_ssl_certificate.gw_lb_ssl_certificate[each.key]) ? 
      data.google_compute_ssl_certificate.gw_lb_ssl_certificate[each.key].id : 
      google_compute_ssl_certificate.gw_lb_ssl_certificate[each.key].id
  ]
}

resource "google_compute_global_address" "gw_lb_frontend_ip_address" {
  count = local.lb_provision_ip && local.is_global_load_balancing ? 1 : 0
  name = "${local.resource_prefix}-gw-lb-frontend-ip"
}

resource "google_compute_address" "gw_lb_frontend_ip_address" {
  count = local.lb_provision_ip && local.is_regional_load_balancing ? 1 : 0
  name = "${local.resource_prefix}-gw-lb-frontend-ip"
}

resource "null_resource" "gw_lb_ip_change" {
  count = local.is_load_balancing ? 1 : 0 
  triggers = {
    ip_address = local.lb_provision_ip ? (
      local.is_global_load_balancing ? google_compute_global_address.gw_lb_frontend_ip_address[0].address : google_compute_address.gw_lb_frontend_ip_address[0].address
    ) : var.load_balancer_config.ip_address
  }
}

resource "google_compute_global_forwarding_rule" "gw_lb_forwarding_rule" {
  for_each = local.is_global_load_balancing ? local.lb_rule_mapping : {}
  name = "${local.resource_prefix}-${lower(each.value.frontend_protocol)}${each.value.frontend_port}-forwarding-rule"
  target = each.value.frontend_protocol == "HTTPS" ? google_compute_target_https_proxy.gw_lb_https_proxy[each.key].id : google_compute_target_http_proxy.gw_lb_http_proxy[each.key].id
  port_range = each.value.frontend_port
  load_balancing_scheme = var.load_balancer_config.scheme
  ip_address = local.lb_provision_ip ? google_compute_global_address.gw_lb_frontend_ip_address[0].address : var.load_balancer_config.ip_address
  lifecycle {
    replace_triggered_by = [
      null_resource.gw_lb_ip_change[0]
    ]
  }
}

resource "random_integer" "gw_lb_proxy_subnet_ip_octet" {
  count = local.lb_provision_proxy_subnet ? 1 : 0
  min = 150
  max = 199
}

resource "google_compute_subnetwork" "gw_lb_proxy_subnet" {
  count = local.lb_provision_proxy_subnet ? 1 : 0
  name = "${local.resource_prefix}-gw-lb-proxy-subnet"
  ip_cidr_range = "10.${random_integer.gw_lb_proxy_subnet_ip_octet[0].result}.0.0/24"
  purpose = "REGIONAL_MANAGED_PROXY"
  role = "ACTIVE"
  network = data.google_compute_network.primary_vpc_network.id
}

resource "google_compute_forwarding_rule" "gw_lb_forwarding_rule" {
  depends_on = [
    google_compute_subnetwork.gw_lb_proxy_subnet
  ]
  for_each = local.is_regional_load_balancing ? local.lb_rule_mapping : {}
  name = "${local.resource_prefix}-${lower(each.value.frontend_protocol)}${each.value.frontend_port}-forwarding-rule"
  target = each.value.frontend_protocol == "HTTPS" ? google_compute_region_target_https_proxy.gw_lb_https_proxy[each.key].id : google_compute_region_target_http_proxy.gw_lb_http_proxy[each.key].id
  port_range = each.value.frontend_port
  load_balancing_scheme = var.load_balancer_config.scheme
  network = var.primary_vpc_network
  ip_address = local.lb_provision_ip ? google_compute_address.gw_lb_frontend_ip_address[0].address : var.load_balancer_config.ip_address
  lifecycle {
    replace_triggered_by = [
      null_resource.gw_lb_ip_change[0]
    ]
  }
}