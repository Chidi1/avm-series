terraform {
  backend "azurerm" {
    resource_group_name  = "rg-avm-demo-001"
    storage_account_name = "avmtfstate"
    container_name       = "tfstate"
    key                  = "avm.tfstate"
  }
}