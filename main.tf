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
# 2. AKS
############################################
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"

  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks"

  default_node_pool = {
    name       = "system"
    vm_size    = "Standard_DS2_v2"
    node_count = 2
  }

  network_profile = {
    network_plugin = "azure"
  }
}

############################################
# 3. VM
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
# 3. APP SERVICE
############################################
module "appservice" {
  source = "Azure/avm-res-web-site/azurerm"

  name                = "${var.prefix}-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  https_only = true
  
  version = "~> 0.1"
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

module "aks_private" {
  source = "Azure/avm-res-containerservice-managedcluster/azurerm"

  name                    = "${var.prefix}-aks-private"
  location                = var.location
  resource_group_name     = azurerm_resource_group.rg.name
  private_cluster_enabled = true
  dns_prefix              = "akspriv"
  
  default_node_pool = {
    name       = "default"
    vm_size    = "Standard_D2s_v3"
    node_count = 2
  }
  
  identity = {
    type = "SystemAssigned"
  }
  
  network_profile = {
    network_plugin = "azure"
    network_policy = "azure"
  }
  
  version = "~> 0.1"
  
  depends_on = [module.acr]
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