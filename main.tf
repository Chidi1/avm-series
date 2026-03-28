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
# 4. SQL + AUDITING
############################################
module "sql_server" {
  source  = "Azure/avm-res-sql-server/azurerm"

  name                = "${var.prefix}-sql"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  administrator_login          = var.sql_admin
  administrator_login_password = var.sql_password
  
  # Add version tag for stability
  version = "~> 0.1"
}

module "sql_db" {
  source = "Azure/avm-res-sql-database/azurerm"

  name      = "${var.prefix}-db"
  server_id = module.sql_server.id
  
  version = "~> 0.1"
}

resource "azurerm_mssql_server_extended_auditing_policy" "audit" {
  server_id                              = module.sql_server.id
  enabled                                = true
  storage_endpoint                       = module.storage_account.primary_blob_endpoint
  storage_account_access_key             = module.storage_account.primary_access_key
  
  depends_on = [module.sql_server]
}

############################################
# 5. APP SERVICE
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
# 6. REDIS
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
# 7. PRIVATE AKS + ACR
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
# 8. HUB & SPOKE
############################################
module "hubspoke" {
  source = "Azure/avm-ptn-network-hubspoke/azurerm"

  hub_vnet_cidr   = "10.10.0.0/16"
  spoke_vnet_cidr = "10.20.0.0/16"
  
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  
  version = "~> 0.1"
}

############################################
# 9. POLICY + RBAC
############################################
module "policy" {
  source = "Azure/avm-res-authorization-policyassignment/azurerm"

  policy_definition_id = var.policy_definition_id
  scope                = var.subscription_id
  name                 = "${var.prefix}-policy-assignment"
  
  version = "~> 0.1"
}

############################################
# 10. CI/CD AGENTS
############################################
module "agents" {
  source = "Azure/avm-res-compute-virtualmachinescaleset/azurerm"

  name                = "${var.prefix}-agents"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  instances           = 2
  
  sku = {
    name     = "Standard_D2s_v3"
    tier     = "Standard"
    capacity = 2
  }
  
  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
  
  admin_username = "azureuser"
  
  admin_ssh_key = [{
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }]
  
  version = "~> 0.1"
}

############################################
# 11. MONITORING
############################################
module "monitor" {
  source = "Azure/avm-res-insights-diagnosticsetting/azurerm"

  target_resource_id         = module.vm.id
  name                       = "${var.prefix}-diag-setting"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  
  enabled_log = [
    {
      category = "Audit"
    }
  ]
  
  metric = [
    {
      category = "AllMetrics"
    }
  ]
  
  version = "~> 0.1"
}

############################################
# 12. FUNCTION + PRIVATE ENDPOINT
############################################
module "function" {
  source = "Azure/avm-res-web-functionapp/azurerm"

  name                = "${var.prefix}-func"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  
  runtime_stack = "dotnet"
  runtime_version = "6.0"
  
  version = "~> 0.1"
}

resource "azurerm_private_endpoint" "func_pe" {
  name                = "${var.prefix}-func-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = module.vnet.subnets["app"].id
  
  private_service_connection {
    name                           = "${var.prefix}-func-psc"
    private_connection_resource_id = module.function.id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }
  
  depends_on = [module.function]
}

############################################
# 13. LANDING ZONE
############################################
module "landingzone" {
  source = "Azure/avm-ptn-landingzone/azurerm"

  environment = var.environment
  location    = var.location
  
  # Add common landing zone configuration
  subscription_id = var.subscription_id
  
  version = "~> 0.1"
}

############################################
# 14. AVD
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
# 15. PRIVATE DNS
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