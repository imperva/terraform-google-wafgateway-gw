
# Imperva WAF Gateway on Google Cloud
This Terraform module provisions Imperva WAF Gateway instances on GCP in multiple supported configurations.
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0.0 |

For the GCP prerequisites, please see the [documentation](https://docs.imperva.com/bundle/v15.3-waf-on-google-cloud-platform-installation-guide/page/84150.htm).

## Usage
### Basic example
```hcl
provider "google" {
  project = "my-project"
  region = "europe-west3"
}

variable "mx_password" {
  type = string
  description = "The password for the WAF Management Server"
  sensitive = true
}

module "imperva_gw" {
  source = "imperva/wafgateway/gw/google"
  waf_version = "15.4.0.10"
  model = "GV2500"
  management_server_config = { # Required
    ip = "10.2.3.4" # Can be replaced with the MX module output
    password = var.mx_password
    vpc_network = "my-management-network"
    network_tag = "imperva-mx" # Can be replaced with the MX module output
  }
  # Optional auto-scaling configuration (remove for static instances)
  auto_scaling_config = {
    min_size = 2
    max_size = 3
  }
  # Optional load balancer configuration (remove for no load balancer)
  load_balancer_config = {
    rules = [
      {
        frontend_port = 80
        frontend_protocol = "HTTP"
        backend_port = 8080
        backend_protocol = "HTTP"
      },
      {
        frontend_port = 443
        frontend_protocol = "HTTPS"
        backend_port = 8080
        backend_protocol = "HTTP"
        tls = {
          key = file("key.pem")
          certificate = file("cert.pem")
        }
      }
    ]
    type = "GLOBAL"
  }
  instance_type = "n2-standard-4"
  zones = [
    "europe-west3-a",
    "europe-west3-b",
    "europe-west3-c"
  ]
  primary_vpc_network = "my-primary-network"
  primary_subnet_name = "my-primary-subnet"
  # Optional management interface configuration (remove for single interface configuration)
  management_vpc_network = "my-management-network"
  management_subnet_name = "my-management-subnet"
} 
```
### Supported WAF Gateway versions
This version of the module supports the following WAF Gateway versions:
* 14.7.0.150
* 14.7.0.160
* 14.7.0.170
* 15.3.0.10
* 15.3.0.20
* 15.4.0.10

The `waf_version` input variable must be set to one of these versions. If you need to use a different version, please open an issue or pull request.

### Cross-module reference
If you are using the Gateway module in conjunction with the MX module, you can reference the MX outputs directly in the Gateway module configuration:
```hcl
module "imperva_gw" {
  source = "imperva/wafgateway-gw/google"
  waf_version = "15.4.0.10"
  management_server_config = {
    ip = module.imperva_mx.management_server_ip
    password = var.mx_password
    vpc_network = "my-vpc-network"
    network_tag = module.imperva_mx.network_tag
  }
  ...
}
```
This allows you to register your WAF Gateway instances to your MX without defining explicit dependencies or hard-coding the MX IP address or network tag.
  
## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_commons"></a> [commons](#module\_commons) | imperva/wafgateway-commons/google | 1.2.1 |
## Resources

| Name | Type |
|------|------|
| [google_cloud_run_service_iam_member.cloud_run_invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service_iam_member) | resource |
| [google_cloudfunctions2_function.gw_termination_handler](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloudfunctions2_function) | resource |
| [google_cloudfunctions2_function_iam_member.invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloudfunctions2_function_iam_member) | resource |
| [google_compute_address.gw_lb_frontend_ip_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_backend_service.gw_backend_service](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_backend_service) | resource |
| [google_compute_firewall.gw_firewall](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall) | resource |
| [google_compute_forwarding_rule.gw_lb_forwarding_rule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule) | resource |
| [google_compute_global_address.gw_lb_frontend_ip_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_global_forwarding_rule.gw_lb_forwarding_rule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_forwarding_rule) | resource |
| [google_compute_health_check.gw_igm_healthcheck](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_health_check.gw_lb_healthcheck](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_instance.gw_instance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance) | resource |
| [google_compute_instance_template.gw_instance_template](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template) | resource |
| [google_compute_region_autoscaler.gw_autoscaler](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_autoscaler) | resource |
| [google_compute_region_backend_service.gw_backend_service](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_backend_service) | resource |
| [google_compute_region_health_check.gw_lb_healthcheck](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_health_check) | resource |
| [google_compute_region_instance_group_manager.gw_igm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_instance_group_manager) | resource |
| [google_compute_region_target_http_proxy.gw_lb_http_proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_target_http_proxy) | resource |
| [google_compute_region_target_https_proxy.gw_lb_https_proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_target_https_proxy) | resource |
| [google_compute_region_url_map.gw_lb_url_map](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_url_map) | resource |
| [google_compute_ssl_certificate.gw_lb_ssl_certificate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_ssl_certificate) | resource |
| [google_compute_subnetwork.gw_lb_proxy_subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_compute_target_http_proxy.gw_lb_http_proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_http_proxy) | resource |
| [google_compute_target_https_proxy.gw_lb_https_proxy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_https_proxy) | resource |
| [google_compute_url_map.gw_lb_url_map](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_url_map) | resource |
| [google_logging_project_sink.gw_termination_log_sink](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_sink) | resource |
| [google_project_service.eventarc_enable](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_pubsub_topic.gw_termination_pubsub_topic](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_pubsub_topic_iam_member.gw_termination_pubsub_iam_member](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam_member) | resource |
| [google_secret_manager_secret.gw_registration_secret](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_iam_member.gw_registration_secret_iam_member](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_secret_manager_secret_version.gw_registration_secret_version](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_service_account.deployment_service_account](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_storage_bucket.gw_termination_function_source_bucket](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_object.gw_termination_function_source_object](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_object) | resource |
| [google_vpc_access_connector.vpc_access_connector](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vpc_access_connector) | resource |
| [null_resource.gw_lb_ip_change](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_id.bucket_random_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_integer.gw_lb_proxy_subnet_ip_octet](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/integer) | resource |
| [random_integer.random_ip_octet](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/integer) | resource |
| [random_string.resource_prefix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [time_sleep.await_gw_deletion](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [time_sleep.await_gw_ftl](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [archive_file.gw_termination_handler](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [dns_txt_record_set.google_cloud_eiops](https://registry.terraform.io/providers/hashicorp/dns/latest/docs/data-sources/txt_record_set) | data source |
| [google_client_config.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config) | data source |
| [google_compute_network.primary_vpc_network](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_network) | data source |
| [google_compute_ssl_certificate.gw_lb_ssl_certificate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_ssl_certificate) | data source |
| [google_compute_subnetwork.gw_data_subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_subnetwork) | data source |
| [google_compute_subnetwork.gw_mgmt_subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_subnetwork) | data source |
| [google_compute_subnetworks.proxy_only_subnets](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_subnetworks) | data source |
| [google_compute_zones.available](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/compute_zones) | data source |
| [template_cloudinit_config.gw_gcp_deploy](https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/cloudinit_config) | data source |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | The desired machine type for your WAF Gateway instances. | `string` | n/a | yes |
| <a name="input_management_server_config"></a> [management\_server\_config](#input\_management\_server\_config) | Properties of the Management Server to which the Gateway(s) will be registered. | <pre>object({<br/>    ip = string<br/>    password = string<br/>    vpc_network = optional(string, "")<br/>    network_tag = optional(string, "")<br/>  })</pre> | n/a | yes |
| <a name="input_model"></a> [model](#input\_model) | The desired model for your Gateway instances. This setting affects the maximum network throughput of your Gateway instances. | `string` | n/a | yes |
| <a name="input_primary_subnet_name"></a> [primary\_subnet\_name](#input\_primary\_subnet\_name) | The primary (data) subnet name for your WAF Gateway instance(s). The subnet must belong to the specified primary VPC network. | `string` | n/a | yes |
| <a name="input_primary_vpc_network"></a> [primary\_vpc\_network](#input\_primary\_vpc\_network) | The primary (data) VPC network for your Gateway instances. | `string` | n/a | yes |
| <a name="input_waf_version"></a> [waf\_version](#input\_waf\_version) | The Imperva WAF Gateway version to deploy (format: 'x.y.0.z'). | `string` | n/a | yes |
| <a name="input_zones"></a> [zones](#input\_zones) | The zones where your Gateway instance(s) will be deployed. All zones must be under the region configured for the google provider. | `list(string)` | n/a | yes |
| <a name="input_auto_scaling_config"></a> [auto\_scaling\_config](#input\_auto\_scaling\_config) | Configuration for the auto-scaling group that will manage the Gateway instances (optional). | <pre>object({<br/>    min_size = number<br/>    max_size = number<br/>  })</pre> | `null` | no |
| <a name="input_block_project_ssh_keys"></a> [block\_project\_ssh\_keys](#input\_block\_project\_ssh\_keys) | When true, project-wide SSH keys cannot be used to access the deployed instances. | `bool` | `false` | no |
| <a name="input_deployment_name"></a> [deployment\_name](#input\_deployment\_name) | A unique prefix for all deployed resources. If not provided, a random prefix will be generated. | `string` | `""` | no |
| <a name="input_load_balancer_config"></a> [load\_balancer\_config](#input\_load\_balancer\_config) | Configuration for the load balancer(s) that will distribute traffic to the Gateway instances (optional). | <pre>object({<br/>    scheme = optional(string, "EXTERNAL_MANAGED")<br/>    type = optional(string, "GLOBAL")<br/>    ip_address = optional(string)<br/>    rules = list(object({<br/>      frontend_port = number<br/>      frontend_protocol = string<br/>      backend_port = number<br/>      backend_protocol = string<br/>      tls = optional(object({<br/>        certificate_name = optional(string)<br/>        key = optional(string)<br/>        certificate = optional(string)<br/>      }), null)<br/>    })<br/>  )})</pre> | `null` | no |
| <a name="input_management_subnet_name"></a> [management\_subnet\_name](#input\_management\_subnet\_name) | The management subnet name for your WAF Gateway instance(s). The subnet must belong to the specified management VPC network. | `string` | `""` | no |
| <a name="input_management_vpc_network"></a> [management\_vpc\_network](#input\_management\_vpc\_network) | The management VPC network for your Gateway instances. Must be different from the primary VPC network. Leave empty for a single-interface configuration. | `string` | `""` | no |
| <a name="input_number_of_gateways"></a> [number\_of\_gateways](#input\_number\_of\_gateways) | The number of WAF Gateway instances to deploy (optional). Use this setting to deploy static (non-scaling) Gateway instances. | `number` | `null` | no |
| <a name="input_post_script"></a> [post\_script](#input\_post\_script) | An optional bash script or command that will be executed at the end of the Gateway instance startup. | `string` | `""` | no |
| <a name="input_ssh_access_source_ranges"></a> [ssh\_access\_source\_ranges](#input\_ssh\_access\_source\_ranges) | A list of IPv4 ranges in CIDR format that should have access to your Gateway instances via port 22 (e.g. 10.0.1.0/24). | `list(string)` | `[]` | no |
| <a name="input_timezone"></a> [timezone](#input\_timezone) | The desired timezone for your Management Server instance. | `string` | `"UTC"` | no |
| <a name="input_traffic_ports"></a> [traffic\_ports](#input\_traffic\_ports) | A list of additional TCP ports (besides the load balancer ports) that should be allowed for inbound traffic to the Gateway instances. | `list(number)` | `[]` | no |
| <a name="input_traffic_source_ranges"></a> [traffic\_source\_ranges](#input\_traffic\_source\_ranges) | A list of IPv4 ranges in CIDR format that should have access to your Gateways' traffic ports (e.g. 10.0.1.0/24). | `list(string)` | `[]` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_group_name"></a> [instance\_group\_name](#output\_instance\_group\_name) | Name of the instance group manager for Gateway instances. Populated only if autoscaling is enabled. |
| <a name="output_instance_names"></a> [instance\_names](#output\_instance\_names) | List of names of the Gateway instances. Populated only if autoscaling is disabled. |
| <a name="output_load_balancer_names"></a> [load\_balancer\_names](#output\_load\_balancer\_names) | List of load balancer names associated with the Gateway instances. Populated only if load balancing is enabled. |
| <a name="output_static_management_addresses"></a> [static\_management\_addresses](#output\_static\_management\_addresses) | List of static management internal IP addresses of the Gateway instances. Populated only if dual NIC is enabled and autoscaling is disabled. |
| <a name="output_static_primary_addresses"></a> [static\_primary\_addresses](#output\_static\_primary\_addresses) | List of static primary internal IP addresses of the Gateway instances. Populated only if autoscaling is disabled. |
