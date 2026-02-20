terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Remote state stored in Azure Blob Storage.
  # Run bootstrap.sh first to create this storage account.
  # Then replace "dataentrytfstateXXXX" with the name printed by bootstrap.sh.
  backend "azurerm" {
    resource_group_name  = "data-entry-tf-state"
    storage_account_name = "dataentrytfstate7241"
    container_name       = "tfstate"
    key                  = "data-entry.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ── Resource Group ─────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "data-entry-app"
    environment = "production"
    managed_by  = "terraform"
  }
}
