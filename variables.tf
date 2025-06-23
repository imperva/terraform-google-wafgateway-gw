variable "deployment_name" {
  type        = string
  description = "A unique prefix for all deployed resources."
  default = ""
  validation {
    condition     = var.deployment_name == "" || can(regex(module.commons.validation.gcp.standard_name.regex, var.deployment_name))
    error_message = module.commons.validation.gcp.standard_name.error_message
  }
}

variable "timezone" {
  type        = string
  default     = "UTC"
  description = "The desired timezone for your Management Server instance."
  validation {
    condition = contains(
      module.commons.validation.global.timezone.allowed_values,
      var.timezone
    )
    error_message = module.commons.validation.global.timezone.error_message
  }
}

variable "management_vpc_network" {
  type = string
  description = "The management VPC network for your Gateway instances. Must be different from the primary VPC network. Leave empty for a single-interface configuration."
  default = ""
  validation {
    condition = var.management_vpc_network == "" || can(
      regex(
        module.commons.validation.gcp.standard_name.regex,
        var.management_vpc_network
      )
    )
    error_message = module.commons.validation.gcp.standard_name.error_message
  }

  validation {
    condition = var.management_vpc_network == "" || (var.management_vpc_network != var.primary_vpc_network)
    error_message = "The management VPC network must be different from the specified primary VPC network (${var.primary_vpc_network})."
  }
}

variable "primary_vpc_network" {
  type = string
  description = "The primary (data) VPC network for your Gateway instances."
  validation {
    condition = can(
      regex(
        module.commons.validation.gcp.standard_name.regex, 
        var.primary_vpc_network
      )
    )
    error_message = module.commons.validation.gcp.standard_name.error_message
  }
}

variable "block_project_ssh_keys" {
  type = bool
  description = "When true, project-wide SSH keys cannot be used to access the deployed instances."
  default = false
}

variable "model" {
  type = string
  description = "The desired model for your Gateway instances. This setting affects the maximum network throughput of your Gateway instances."
  validation {
    condition = contains(
      module.commons.validation.gcp.gw_model.allowed_values, 
      var.model
    )
    error_message = module.commons.validation.gcp.gw_model.error_message
  }
}

variable "ssh_access_source_ranges" {
  type        = list(string)
  default     = []
  description = "A list of IPv4 ranges in CIDR format that should have access to your Management Server via port 22 (e.g. 10.0.1.0/24)."
  validation {
    condition = alltrue(
      [
        for range in var.ssh_access_source_ranges : can(
          regex(
            module.commons.validation.global.ipv4_cidr.regex,
            range
          )
        )
      ]
    )
    error_message = module.commons.validation.global.ipv4_cidr.error_message
  }
}

variable "management_server_config" {
  type = object({
    ip = string
    password = string
    vpc_network = optional(string, "")
    network_tag = optional(string, "")
  })
  description = "Properties of the Management Server to which the Gateway(s) will be registered."
  validation {
    condition = can(
      regex(
        module.commons.validation.global.ipv4_address.regex, 
        var.management_server_config.ip
      )
    )
    error_message = module.commons.validation.global.ipv4_address.error_message
  }
  validation {
    condition = length(var.management_server_config.password) >= 7
    error_message = "Password must be at least 7 characters long."
  }
  validation {
    condition = can(
      regex(
        module.commons.validation.gcp.standard_name.regex, 
        var.management_server_config.network_tag
      )
    )
    error_message = module.commons.validation.gcp.standard_name.error_message
  }
  validation {
    condition = var.management_server_config.vpc_network != local.gw_management_network || var.management_server_config.network_tag != ""
    error_message = "When the Management Server and Gateways are in the same VPC, 'network_tag' must be populated with the Management Server's network tag." 
  }
}

variable "primary_subnet_name" {
  type = string
  description = "The primary (data) subnet name for your WAF Gateway instance(s). The subnet must belong to the specified primary VPC network."
  validation {
    condition = can(
      regex(
        module.commons.validation.gcp.standard_name.regex, 
        var.primary_subnet_name
      )
    )
    error_message = module.commons.validation.gcp.standard_name.error_message
  }
}

variable "management_subnet_name" {
  type = string
  description = "The management subnet name for your WAF Gateway instance(s). The subnet must belong to the specified management VPC network."
  default = ""
  validation {
    condition = var.management_subnet_name == "" || can(
      regex(
        module.commons.validation.gcp.standard_name.regex,
        var.management_subnet_name
      )
    )
    error_message = module.commons.validation.gcp.standard_name.error_message
  }
  validation {
    condition = var.management_vpc_network == "" || var.management_subnet_name != ""
    error_message = "When 'management_vpc_network' is set, 'management_subnet_name' must be specified."
  }
}

variable "number_of_gateways" {
  type = number
  description = "The number of WAF Gateway instances to deploy (optional). Use this setting to deploy static (non-scaling) Gateway instances."
  default = null
  validation {
    condition = var.number_of_gateways == null ? true : var.number_of_gateways >= module.commons.validation.gcp.gw_count.minimum && var.number_of_gateways <= module.commons.validation.gcp.gw_count.maximum
    error_message = "Value must be greater than or equal to ${module.commons.validation.gcp.gw_count.minimum} and smaller than or equal to ${module.commons.validation.gcp.gw_count.maximum}."
  }
}

variable "zones" {
  type = list(string)
  description = "The zones where your Gateway instance(s) will be deployed. All zones must be under the region configured for the google provider."
  validation {
    condition = alltrue([
      for zone in var.zones: contains(
        data.google_compute_zones.available.names, 
        zone
      )
    ])
    error_message = "One or more invalid zones specified (available: ${join(", ", data.google_compute_zones.available.names)})."
  }
}

variable "instance_type" {
  type = string
  description = "The desired machine type for your WAF Gateway instances."
  validation {
    condition = contains(
      module.commons.validation.gcp.gw_instance_type.allowed_values,
      var.instance_type
    )
    error_message = module.commons.validation.gcp.gw_instance_type.error_message
  }
}

variable "waf_version" {
  type = string
  description = "The Imperva WAF Gateway version to deploy (format: 'x.y.0.z')."
  validation {
    condition = contains(
      module.commons.validation.gcp.waf_version.allowed_values,
      var.waf_version
    )
    error_message = module.commons.validation.gcp.waf_version.error_message
  }
}

variable "auto_scaling_config" {
  type = object({
    min_size = number
    max_size = number
  })
  default = null
  description = "Configuration for the auto-scaling group that will manage the Gateway instances (optional)."
  validation {
    condition = (var.auto_scaling_config != null && var.number_of_gateways == null) || (var.auto_scaling_config == null && var.number_of_gateways != null)
    error_message = "Either 'auto_scaling_config' or 'number_of_gateways' must be set exclusively."
  }
  validation {
    condition = var.auto_scaling_config == null ? true : var.auto_scaling_config.min_size >= module.commons.validation.gcp.gw_count.minimum && var.auto_scaling_config.max_size <= module.commons.validation.gcp.gw_count.maximum && var.auto_scaling_config.min_size <= var.auto_scaling_config.max_size
    error_message = "Autoscaling group size must be between ${module.commons.validation.gcp.gw_count.minimum} and ${module.commons.validation.gcp.gw_count.maximum} and min_size must be less than or equal to max_size."
  }
}

variable "load_balancer_config" {
  type = object({
    scheme = optional(string, "EXTERNAL_MANAGED")
    type = optional(string, "GLOBAL")
    ip_address = optional(string)
    rules = list(object({
      frontend_port = number
      frontend_protocol = string
      backend_port = number
      backend_protocol = string
      tls = optional(object({
        certificate_name = optional(string)
        key = optional(string)
        certificate = optional(string)
      }), null)
    })
  )})
  description = "Configuration for the load balancer(s) that will distribute traffic to the Gateway instances (optional)."
  default = null
  validation {
    condition = var.load_balancer_config == null || var.auto_scaling_config != null
    error_message = "Load balancer configuration is only supported when var.auto_scaling_config is configured."
  }

  validation {
    condition = var.load_balancer_config == null ? true : contains(
      module.commons.validation.gcp.lb.scheme.allowed_values,
      var.load_balancer_config.scheme
    )
    error_message = module.commons.validation.gcp.lb.scheme.error_message
  }

  validation {
    condition = var.load_balancer_config == null ? true : contains(
      module.commons.validation.gcp.lb.type.allowed_values,
      var.load_balancer_config.type
    )
    error_message = module.commons.validation.gcp.lb.type.error_message
  }

  validation {
    condition = var.load_balancer_config == null ? true : alltrue([
      for lb_rule in var.load_balancer_config.rules:
      lb_rule.frontend_port >= 1 && lb_rule.frontend_port <= 65535 &&
      lb_rule.backend_port >= 1 && lb_rule.backend_port <= 65535
    ])
    error_message = "Frontend and backend ports must be between 1 and 65535."
  }

  validation {
    condition = var.load_balancer_config == null ? true : alltrue([
      for lb_rule in var.load_balancer_config.rules:
      contains(
        module.commons.validation.gcp.lb.frontend_protocol.allowed_values,
        lb_rule.frontend_protocol
      )
    ])
    error_message = module.commons.validation.gcp.lb.frontend_protocol.error_message
  }

  validation {
    condition = var.load_balancer_config == null ? true : alltrue([
      for lb_rule in var.load_balancer_config.rules:
      contains(
        module.commons.validation.gcp.lb.backend_protocol.allowed_values,
        lb_rule.backend_protocol
      )
    ])
    error_message = module.commons.validation.gcp.lb.backend_protocol.error_message
  }

  validation {
    condition = var.load_balancer_config == null ? true : alltrue([
      for lb_rule in var.load_balancer_config.rules:
      lb_rule.frontend_protocol != "HTTPS" || (lb_rule.tls != null ? (lb_rule.tls.certificate_name != null && lb_rule.tls.key == null && lb_rule.tls.certificate == null) || (lb_rule.tls.certificate_name == null && lb_rule.tls.key != null && lb_rule.tls.certificate != null) : false)
    ])
    error_message = "When the frontend protocol is HTTPS, the 'tls' attribute must be populated with either PEM-encoded 'key' AND 'certificate' (to create a new certificate) OR 'certificate_name' (to use an existing SSL certificate) exculsively."
  }  

  validation {
    condition = var.load_balancer_config == null ? true : length(var.load_balancer_config.rules) == length(toset([
      for lb_rule in var.load_balancer_config.rules: lb_rule.frontend_port
    ]))
    error_message = "Frontend ports must be unique."
  }

  validation {
    condition = var.load_balancer_config == null ? true : alltrue([
      for port, protocols in {for rule in var.load_balancer_config.rules: rule.backend_port => rule.backend_protocol...}: length(toset(protocols)) == 1
    ])
    error_message = "Backend port and protocol combinations must be unique."
  }

  validation {
    condition = var.load_balancer_config == null ? true : var.load_balancer_config.ip_address == null || can(
      regex(
        module.commons.validation.global.ipv4_address.regex,
        var.load_balancer_config.ip_address
      )
    )
    error_message = module.commons.validation.global.ipv4_address.error_message
  }
}