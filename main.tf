############################################
# RESOURCE GROUP
############################################
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

############################################
# 1. VNET FOUNDATION
############################################
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"

  name                = "${var.prefix}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  address_space = ["10.0.0.0/16"]

  subnets = {
    aks = { address_prefixes = ["10.0.1.0/24"] }
    app = { address_prefixes = ["10.0.2.0/24"] }
    db  = { address_prefixes = ["10.0.3.0/24"] }
  }
}

############################################
# 2. VM
############################################
module "vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"

  name                = "${var.prefix}-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  admin_username = var.admin_username
  size           = "Standard_B2s"
}


############################################
# 4. REDIS
############################################
module "redis" {
  source = "Azure/avm-res-cache-redis/azurerm"

  name                = "${var.prefix}-redis"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = "Premium"
  family   = "P"
  capacity = 1
  
  version = "~> 0.1"
}

############################################
# 5. PRIVATE AKS + ACR
############################################
module "acr" {
  source = "Azure/avm-res-containerregistry-registry/azurerm"

  name                = replace("${var.prefix}acr", "-", "")
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  sku = "Premium"
  admin_enabled = true
  
  version = "~> 0.1"
}


############################################
# 6. AVD
############################################
module "avd" {
  source = "Azure/avm-res-desktopvirtualization-hostpool/azurerm"

  name                = "${var.prefix}-avd"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  
  type                = "Pooled"
  load_balancer_type  = "BreadthFirst"
  
  version = "~> 0.1"
}

############################################
# 7. PRIVATE DNS
############################################
module "privatedns" {
  source = "Azure/avm-res-network-privatednszone/azurerm"

  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  
  # Add virtual network links
  virtual_network_links = {
    link1 = {
      vnet_id = module.hubspoke.hub_vnet_id
    }
  }
  
  version = "~> 0.1"
}

# Additional resource for storage account needed for SQL auditing
module "storage_account" {
  source = "Azure/avm-res-storage-storageaccount/azurerm"
  
  name                = replace("${var.prefix}stgaudit", "-", "")
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  version = "~> 0.1"
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}