locals {
  managed_rg_name = coalesce(var.managed_resource_group_name, "${var.name}-dbw-managed-rg")
  databricks_subnets = {
    host      = var.host_subnet_cidr
    container = var.container_subnet_cidr
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Two delegated subnets for VNet injection. Databricks requires the delegation
# and an NSG association on both.
resource "azurerm_subnet" "databricks" {
  for_each = local.databricks_subnets

  name                 = "${var.name}-dbw-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "${var.name}-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_cidr]
  private_endpoint_network_policies = "Enabled"
}

# With network_security_group_rules_required = "NoAzureDatabricksRules"
# Databricks adds no rules of its own, so the NSG carries exactly what the
# clusters need and nothing else.
resource "azurerm_network_security_group" "databricks" {
  name                = "${var.name}-dbw-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-worker-to-worker-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-worker-to-worker-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-control-plane-outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "3306", "8443-8451"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureDatabricks"
  }

  security_rule {
    name                       = "allow-metastore-outbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "allow-storage-outbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "allow-eventhub-outbound"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9093"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "EventHub"
  }
}

resource "azurerm_subnet_network_security_group_association" "databricks" {
  for_each = azurerm_subnet.databricks

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

# ---------------------------------------------------------------------------
# Workspace: no public IPs on clusters, no public network access
# ---------------------------------------------------------------------------

resource "azurerm_databricks_workspace" "this" {
  name                                  = "${var.name}-dbw"
  location                              = var.location
  resource_group_name                   = var.resource_group_name
  sku                                   = "premium" # Private Link needs Premium
  managed_resource_group_name           = local.managed_rg_name
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"
  tags                                  = var.tags

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.this.id
    public_subnet_name                                   = azurerm_subnet.databricks["host"].name
    private_subnet_name                                  = azurerm_subnet.databricks["container"].name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.databricks["host"].id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.databricks["container"].id
  }
}

# ---------------------------------------------------------------------------
# Private Link: front end (UI/API) and browser authentication
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "databricks" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks" {
  name                  = "${var.name}-dbw-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.databricks.name
  virtual_network_id    = azurerm_virtual_network.this.id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "ui_api" {
  name                = "${var.name}-dbw-ui-api-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-dbw-ui-api"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    subresource_names              = ["databricks_ui_api"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "databricks"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }
}

resource "azurerm_private_endpoint" "browser_auth" {
  count = var.create_browser_auth_endpoint ? 1 : 0

  name                = "${var.name}-dbw-auth-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-dbw-auth"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    subresource_names              = ["browser_authentication"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "databricks-auth"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }

  depends_on = [azurerm_private_endpoint.ui_api]
}
