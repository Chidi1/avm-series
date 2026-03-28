terraform {
  backend "azurerm" {
    resource_group_name  = "rg-avm-demo-001"
    storage_account_name = "avmtfstate"
    container_name       = "tfstate"
    key                  = "avm.tfstate"
    subscription_id      = "3f08161e-7132-4a28-85ba-a39a7365e2d7" 
    use_azuread_auth     = true
  }
}