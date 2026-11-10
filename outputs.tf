output "workspace_id" {
  description = "Resource ID of the Databricks workspace."
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  description = "Workspace URL. It resolves to the private endpoint from inside the VNet (or any network linked to the private DNS zone)."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "vnet_id" {
  description = "ID of the workspace VNet, for peering to a hub or to on-premises connectivity."
  value       = azurerm_virtual_network.this.id
}

output "private_dns_zone_id" {
  description = "ID of privatelink.azuredatabricks.net. Link it to any other VNet that must reach the workspace."
  value       = azurerm_private_dns_zone.databricks.id
}

output "egress_public_ip" {
  description = "The single public IP clusters egress from (NAT gateway or firewall). Null when egress_mode is \"none\". Useful for allow-lists on external systems."
  value = try(
    azurerm_public_ip.nat[0].ip_address,
    azurerm_public_ip.firewall[0].ip_address,
    null,
  )
}
