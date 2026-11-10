terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }

  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "<your-state-account>"
  #   container_name       = "tfstate"
  #   key                  = "private-databricks/basic.tfstate"
  #   use_azuread_auth     = true
  # }
}

provider "azurerm" {
  features {}
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

resource "azurerm_resource_group" "this" {
  name     = "analytics-dev-rg"
  location = var.location
}

module "databricks" {
  source = "../.."

  name                = "analytics-dev"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  egress_mode         = "nat_gateway"

  tags = {
    environment = "dev"
    managed_by  = "terraform"
  }
}

output "workspace_url" {
  value = module.databricks.workspace_url
}

output "egress_public_ip" {
  value = module.databricks.egress_public_ip
}
