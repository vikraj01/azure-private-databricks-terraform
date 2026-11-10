# Clusters have no public IPs (secure cluster connectivity), so they need an
# explicit way out to the control plane relay, storage and package mirrors.

locals {
  use_nat      = var.egress_mode == "nat_gateway"
  use_firewall = var.egress_mode == "firewall"
}

# ---------------------------------------------------------------------------
# Option 1: NAT gateway (default)
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "nat" {
  count = local.use_nat ? 1 : 0

  name                = "${var.name}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count = local.use_nat ? 1 : 0

  name                = "${var.name}-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = local.use_nat ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "databricks" {
  for_each = local.use_nat ? azurerm_subnet.databricks : {}

  subnet_id      = each.value.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

# ---------------------------------------------------------------------------
# Option 2: Azure Firewall with a forced default route
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "firewall" {
  count = local.use_firewall ? 1 : 0

  name                 = "AzureFirewallSubnet" # name is mandated by Azure
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.firewall_subnet_cidr]
}

resource "azurerm_public_ip" "firewall" {
  count = local.use_firewall ? 1 : 0

  name                = "${var.name}-fw-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  count = local.use_firewall ? 1 : 0

  name                = "${var.name}-fw-policy"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "databricks" {
  count = local.use_firewall ? 1 : 0

  name               = "databricks"
  firewall_policy_id = azurerm_firewall_policy.this[0].id
  priority           = 200

  network_rule_collection {
    name     = "databricks-required"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "control-plane"
      protocols             = ["TCP"]
      source_addresses      = [var.host_subnet_cidr, var.container_subnet_cidr]
      destination_addresses = ["AzureDatabricks"]
      destination_ports     = ["443", "3306", "8443-8451"]
    }

    rule {
      name                  = "metastore"
      protocols             = ["TCP"]
      source_addresses      = [var.host_subnet_cidr, var.container_subnet_cidr]
      destination_addresses = ["Sql"]
      destination_ports     = ["3306"]
    }

    rule {
      name                  = "storage"
      protocols             = ["TCP"]
      source_addresses      = [var.host_subnet_cidr, var.container_subnet_cidr]
      destination_addresses = ["Storage"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "eventhub-logs"
      protocols             = ["TCP"]
      source_addresses      = [var.host_subnet_cidr, var.container_subnet_cidr]
      destination_addresses = ["EventHub"]
      destination_ports     = ["9093"]
    }
  }

  application_rule_collection {
    name     = "package-mirrors"
    priority = 300
    action   = "Allow"

    rule {
      name = "python-and-maven"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses  = [var.host_subnet_cidr, var.container_subnet_cidr]
      destination_fqdns = ["pypi.org", "*.pypi.org", "files.pythonhosted.org", "repo1.maven.org", "repo.maven.apache.org"]
    }
  }
}

resource "azurerm_firewall" "this" {
  count = local.use_firewall ? 1 : 0

  name                = "${var.name}-fw"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.this[0].id
  tags                = var.tags

  ip_configuration {
    name                 = "primary"
    subnet_id            = azurerm_subnet.firewall[0].id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }

  depends_on = [azurerm_firewall_policy_rule_collection_group.databricks]
}

resource "azurerm_route_table" "databricks" {
  count = local.use_firewall ? 1 : 0

  name                = "${var.name}-dbw-rt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this[0].ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "databricks" {
  for_each = local.use_firewall ? azurerm_subnet.databricks : {}

  subnet_id      = each.value.id
  route_table_id = azurerm_route_table.databricks[0].id
}
