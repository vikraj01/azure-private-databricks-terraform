variable "name" {
  description = "Base name used for every resource (for example \"analytics-dev\"). Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3 to 40 characters of lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group that will hold the network and the workspace."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space of the workspace VNet."
  type        = list(string)
  default     = ["10.20.0.0/22"]
}

variable "host_subnet_cidr" {
  description = "CIDR of the Databricks host (\"public\") subnet. With secure cluster connectivity no public IPs are used despite the name. /26 or larger."
  type        = string
  default     = "10.20.0.0/24"
}

variable "container_subnet_cidr" {
  description = "CIDR of the Databricks container (\"private\") subnet. Same size as the host subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_endpoint_subnet_cidr" {
  description = "CIDR of the subnet that holds the private endpoints."
  type        = string
  default     = "10.20.2.0/27"
}

variable "firewall_subnet_cidr" {
  description = "CIDR of AzureFirewallSubnet. Only used when egress_mode is \"firewall\". /26 or larger."
  type        = string
  default     = "10.20.3.0/26"
}

variable "egress_mode" {
  description = <<-EOT
    How clusters reach the internet and the Databricks control plane:
    "nat_gateway" (simple, default), "firewall" (Azure Firewall with service-tag rules and a forced route),
    or "none" (you provide egress yourself, for example through a hub firewall and peering).
  EOT
  type        = string
  default     = "nat_gateway"

  validation {
    condition     = contains(["nat_gateway", "firewall", "none"], var.egress_mode)
    error_message = "egress_mode must be one of: nat_gateway, firewall, none."
  }
}

variable "create_browser_auth_endpoint" {
  description = "Create the browser_authentication private endpoint. Azure needs one per region per DNS zone; set false if another workspace in the region already has it."
  type        = bool
  default     = true
}

variable "managed_resource_group_name" {
  description = "Name of the Databricks managed resource group. Defaults to \"<name>-dbw-managed-rg\"."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
