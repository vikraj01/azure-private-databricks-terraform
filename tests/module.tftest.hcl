# Plan-level tests with a mocked provider: they run in CI with no Azure
# credentials and check the security properties this module promises.

mock_provider "azurerm" {}

variables {
  name                = "unit-test"
  location            = "westeurope"
  resource_group_name = "unit-test-rg"
}

run "workspace_is_private_by_default" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "Workspace must not accept public network access."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "Clusters must run without public IPs (secure cluster connectivity)."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.network_security_group_rules_required == "NoAzureDatabricksRules"
    error_message = "Back-end Private Link needs NoAzureDatabricksRules."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "Private Link requires the premium SKU."
  }

  assert {
    condition     = alltrue([for s in azurerm_subnet.databricks : s.delegation[0].service_delegation[0].name == "Microsoft.Databricks/workspaces"])
    error_message = "Both Databricks subnets must be delegated to Microsoft.Databricks/workspaces."
  }

  assert {
    condition     = length(azurerm_private_endpoint.browser_auth) == 1
    error_message = "Browser authentication endpoint should be created by default."
  }
}

run "nat_gateway_is_default_egress" {
  command = plan

  assert {
    condition     = length(azurerm_nat_gateway.this) == 1 && length(azurerm_firewall.this) == 0
    error_message = "Default egress should be a NAT gateway and no firewall."
  }

  assert {
    condition     = length(azurerm_subnet_nat_gateway_association.databricks) == 2
    error_message = "Both Databricks subnets should use the NAT gateway."
  }
}

run "firewall_egress_forces_default_route" {
  command = plan

  variables {
    egress_mode = "firewall"
  }

  assert {
    condition     = length(azurerm_firewall.this) == 1 && length(azurerm_nat_gateway.this) == 0
    error_message = "Firewall mode should create a firewall and no NAT gateway."
  }

  assert {
    condition     = anytrue([for r in azurerm_route_table.databricks[0].route : r.address_prefix == "0.0.0.0/0" && r.next_hop_type == "VirtualAppliance"])
    error_message = "Firewall mode must force the default route through the firewall."
  }

  assert {
    condition     = length(azurerm_subnet_route_table_association.databricks) == 2
    error_message = "Both Databricks subnets should use the firewall route table."
  }
}

run "no_egress_mode_creates_nothing" {
  command = plan

  variables {
    egress_mode                  = "none"
    create_browser_auth_endpoint = false
  }

  assert {
    condition     = length(azurerm_nat_gateway.this) == 0 && length(azurerm_firewall.this) == 0
    error_message = "egress_mode none should create neither NAT nor firewall."
  }

  assert {
    condition     = length(azurerm_private_endpoint.browser_auth) == 0
    error_message = "Browser auth endpoint should be skippable."
  }
}

run "rejects_unknown_egress_mode" {
  command = plan

  variables {
    egress_mode = "vpn"
  }

  expect_failures = [var.egress_mode]
}
